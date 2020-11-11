function mqtt_thread_func(pipe, config_json)
   local lunajson = require('lunajson')
   local conf = lunajson.decode(config_json)
   local inspect = require('inspect')

   local logger
   local log_level = string.lower(conf.LogLevel or "warn")
   local log_device = string.lower(conf.LogDevice or "syslog")
   if log_device == "stdout" or log_device == "console" then
      require('logging.console')
      logger = logging.console()
   else
      require('logging.syslog')
      logger = logging.syslog("collectd-monitor-remote")
   end
   if log_level == "debug" then
      logger:setLevel(logging.DEBUG)
   elseif log_level == "info" then
      logger:setLevel(logging.INFO)
   elseif log_level == "warn" or log_level == "warning"then
      logger:setLevel(logging.WARN)
   elseif log_level == "err" or log_level == "error" then
      logger:setLevel(logging.ERROR)
   elseif log_level == "fatal" then
      logger:setLevel(logging.FATAL)
   end

   function join_messages(...)
      local result = ""
      for i = 1, select('#', ...) do
         result = result .. tostring(select(i, ...))
      end
      return result
   end

   function debug(...)
      logger:debug(join_messages(...))
   end

   function info(...)
      logger:info(join_messages(...))
   end

   function warn(...)
      logger:warn(join_messages(...))
   end

   function error(...)
      logger:error(join_messages(...))
   end

   function execute_command(command)
      local file, err, errnum = io.open(conf.MonitorConfigPath, "rb")
      if not file then
         error(err)
         return
      end
      local content = file:read("*all")
      file:close()

      local succeeded, monitor_settings = pcall(lunajson.decode, content)
      if not succeeded or not monitor_settings or not monitor_settings["commands"] then
         error("No command is configured!")
         return
      end

      if not monitor_settings["commands"][command] then
         error("Cannot find command: ", command)
         return
      end

      debug("Command found: ", command)
      os.execute(monitor_settings["commands"][command])
   end

   local mqtt = require('mqtt')
   local cqueues = require("cqueues")
   local cq = cqueues.new()
   local loop = mqtt.get_ioloop()
   local client = mqtt.client {
      uri = conf.Host,
      username = conf.User,
      password = conf.Password,
      secure = conf.Secure,
      clean = conf.CleanSession,
   }
   client:on {
      connect = function(reply)
         if reply.rc ~= 0 then
            print("Failed to connect to broker: ",
                  reply:reason_string(), reply)
            return
         end

         local subscribe_options = {
            topic = conf.CommandTopic,
            qos = conf.QoS,
         }

         local packet_id, err = client:subscribe(subscribe_options)
         if not packet_id then
            error("Failed to subscribe: ", err)
         end
      end,

      subscribe = function(packet)
         debug("MQTT subscribe callback: ", inspect(packet))
      end,

      unsubscribe = function(packet)
         debug("MQTT unsubscribe callback: ", inspect(reply))
      end,

      message = function(packet)
         debug("received message", packet)

         local succeeded, msg = client:acknowledge(packet)
         if not succeeded then
            error("Failed to acknowledge: ", msg)
            return
         end

         succeeded, msg = pcall(lunajson.decode, packet.payload)
         if not succeeded or not msg or not msg.command then
            error("Failed to decode MQTT message:", msg)
            return
         end
         debug("Received command: ", msg.command)
         execute_command(msg.command)
      end,

      acknowledge = function(packet)
         debug("MQTT acknowledge callback: ", ispect(packet))
      end,

      error = function(msg)
         warn("MQTT client error: ", msg)
      end,

      close = function(connection)
         debug("MQTT connection closed: ", connection.close_reason)
      end,

      auth = function(packet)
         debug("MQTT auth callback: ", inspect(packet))
      end,
   }

   loop:add(client)
   while true do
      loop:iteration()
      line, why = pipe:recv("*L", "t")
      if line == "finish\n" then
         break
      end
   end
   client:disconnect()
   loop:remove(client)
   info("MQTT thread finished")
end


local mqtt_config_json
local mqtt_thread
local mqtt_thread_pipe

function config(conf)
   collectd.log_debug("monitor-remote.lua: config")
   mqtt_config_json = require('lunajson').encode(conf)
   return 0
end

function init()
   local conf = mqtt_config
   mqtt_thread, mqtt_thread_pipe =
      require('cqueues.thread').start(mqtt_thread_func, mqtt_config_json)
   return 0
end

function shutdown()
   collectd.log_debug("monitor-remote.lua: shutdown")
   mqtt_thread_pipe:write("finish\n")
   mqtt_thread:join()
   return 0
end

collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)

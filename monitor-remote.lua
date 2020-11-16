--[[
   Register collectd callback functions
]]--

local mqtt_config_json
local mqtt_thread
local mqtt_thread_pipe

collectd.register_config(function(conf)
   collectd.log_debug("monitor-remote.lua: config")

   local lunajson = require('lunajson')
   mqtt_config_json = lunajson.encode(conf)

   local debug_config_json = mqtt_config_json
   if conf.Password then
      conf.Password = "********"
      debug_config_json = lunajson.encode(conf)
   end
   collectd.log_debug("config: " .. debug_config_json)

   return 0
end)

collectd.register_init(function()
   collectd.log_debug("monitor-remote.lua: init")
   local conf = mqtt_config
   mqtt_thread, mqtt_thread_pipe =
      require('cqueues.thread').start(mqtt_thread_func, mqtt_config_json)
   return 0
end)

collectd.register_shutdown(function()
   collectd.log_debug("monitor-remote.lua: shutdown")
   mqtt_thread_pipe:write("finish\n")
   mqtt_thread:join()
   return 0
end)


--[[
   Poll MQTT messages and handle commands in another thread.
   Since it uses cqueues.thread, it can't refer parent objects, it can just
   only receive string arguments from the caller.
   refs:
     https://github.com/wahern/cqueues
     https://raw.githubusercontent.com/wahern/cqueues/master/doc/cqueues.pdf
]]--

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

   function dispatch_command(command_name, task_id)
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

      if not monitor_settings["commands"][command_name] then
         error("Cannot find command: ", command_name)
         return
      end

      debug("Command found: ", command_name)

      run_command(monitor_settings["commands"][command_name])
   end

   function run_command(command_line)
      local cmdline = command_line .. "; echo $?"
      local pipe = io.popen(cmdline)

      local lines = {}
      for line in pipe:lines() do
         lines[#lines + 1] = line
      end

      local command_output = ""
      for i = 1, #lines - 1 do
         command_output = command_output .. lines[i]
      end
      local return_code = tonumber(lines[#lines])

      debug("Return code: ", return_code)
      debug("Command output: ", command_output)

      return return_code, command_output
   end

   local mqtt = require('mqtt')
   local client = mqtt.client {
      uri = conf.Host,
      username = conf.User,
      password = conf.Password,
      secure = conf.Secure,
      clean = conf.CleanSession,
      reconnect = conf.ReconnectInterval,
   }
   client:on {
      connect = function(reply)
         if reply.rc ~= 0 then
            error("Failed to connect to broker: ",
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
         debug("Received message: ", packet)

         local succeeded, msg = client:acknowledge(packet)
         if not succeeded then
            error("Failed to acknowledge: ", msg)
            return
         end

         succeeded, msg = pcall(lunajson.decode, packet.payload)
         if not succeeded or not msg or not msg.task_id or not msg.command then
            error("Failed to decode MQTT message: ", packet.payload)
            return
         end
         debug("Received command: ", msg.command, ", task_id: ", msg.task_id)

         dispatch_command(msg.command, msg.task_id)
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

   --[[
      Main I/O loop
   ]]--
   local autocreate = true
   local loop_options = {
      --[[
       timeout = 0.005, -- network operations timeout in seconds
       sleep = 0,       -- sleep interval after each iteration
       sleep_function = require("socket").sleep,
      ]]--
   }
   local loop = mqtt.get_ioloop(autocreate, loop_options)
   loop:add(client)
   while true do
      loop:iteration()
      local line, why = pipe:recv("*L", "t")
      if line == "finish\n" then
         break
      end
   end
   client:disconnect()
   loop:remove(client)
   info("MQTT thread finished")
end

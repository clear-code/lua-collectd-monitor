local inspect = require('inspect')
local mqtt = require('mqtt')
local cqueues = require('cqueues')
local thread = require('cqueues.thread')
local lunajson = require('lunajson')
local mqtt_config_json
local mqtt_thread
local mqtt_thread_pipe

local DEBUG  = collectd.log_debug
local ERROR  = collectd.log_error
local INFO   = collectd.log_info
local NOTICE = collectd.log_notice
local WARN   = collectd.log_warning

function config(conf)
   DEBUG("monitor-remote.lua: config")
   mqtt_config_json = lunajson.encode(conf)
   return 0
end

function mqtt_thread_func(pipe, config_json)
   local inspect = require('inspect')
   local mqtt = require('mqtt')
   local cqueues = require("cqueues")
   local lunajson = require('lunajson')
   local conf = lunajson.decode(config_json)
   local cq = cqueues.new()
   local loop = mqtt.get_ioloop()
   local client = mqtt.client {
      uri = conf.Host,
      username = conf.User,
      password = conf.Password,
      secure = conf.Secure,
      clean = conf.CleanSession,
   }

   function get_log_level()
      local level = string.lower(conf.LogLevel or "warn")
      if level == "debug" then
         return 7
      elseif level == "info" then
         return 6
      elseif level == "notice" then
         return 5
      elseif level == "warn" or level == "warning"then
         return 4
      elseif level == "err" or level == "error" then
         return 3
      elseif level == "crit" or level == "critical" then
         return 2
      elseif level == "alert" then
         return 1
      elseif level == "emerg" then
         return 0
      end
      return 4
   end

   local log_level = get_log_level()

   function debug(...)
      if (log_level >= 7) then
         print(...)
      end
   end

   function info(...)
      if (log_level <= 6) then
         print(...)
      end
   end

   function warn(...)
      if (log_level <= 4) then
         print(...)
      end
   end

   function error(...)
      if (log_level <= 3) then
         print(...)
      end
   end

   client:on {
      connect = function(reply)
         if reply.rc ~= 0 then
            print("Failed to connect to broker: ",
                  reply:reason_string(), reply)
            return
         end

         subscribe_options = {
            topic = conf.CommandTopic,
         }
         assert(client:subscribe(subscribe_options))
      end,

      subscribe = function(packet)
         debug("MQTT subscribe callback:", inspect(packet))
      end,

      unsubscribe = function(packet)
         debug("MQTT unsubscribe callback:", inspect(reply))
      end,

      message = function(msg)
         assert(client:acknowledge(msg))
         debug("received message", msg)
      end,

      acknowledge = function(packet)
         debug("MQTT acknowledge callback:", ispect(packet))
      end,

      error = function(msg)
         warn("MQTT client error:", msg)
      end,

      close = function(connection)
         debug("MQTT connection closed:", connection.close_reason)
      end,

      auth = function(packet)
         debug("MQTT auth callback:", packet)
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

function init()
   local conf = mqtt_config
   mqtt_thread, mqtt_thread_pipe =
      thread.start(mqtt_thread_func, mqtt_config_json)
   return 0
end

function shutdown()
   DEBUG("monitor-remote.lua: shutdown")
   mqtt_thread_pipe:write("finish\n")
   mqtt_thread:join()
   return 0
end


collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)

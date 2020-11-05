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

function mqtt_thread_func(conn, config_json)
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
      clean = true,
   }
   client:on {
      connect = function(reply)
	 if reply.rc ~= 0 then
	    print("Failed to connect to broker: ",
		  reply:reason_string(), reply)
	 end

	 subscribe_options = {
	    topic = conf.CommandTopic,
	 }
	 assert(client:subscribe(subscribe_options))
      end,

      subscribe = function(reply)
	 print(inspect(reply))
      end,

      unsubscribe = function(reply)
	 print(inspect(reply))
      end,

      message = function(msg)
	 assert(client:acknowledge(msg))
	 print("received message", msg)
      end,

      acknowledge = function()
	 print("acknowledge")
      end,

      error = function()
	 print("error")
      end,

      close = function()
	 print("close")
      end,

      auth = function()
	 print("auth")
      end,
   }

   loop:add(client)
   while true do
      loop:iteration()
      line, why = conn:recv("*L", "t")
      if line == "finish\n" then
	 break
      end
   end
   print("thread finished")
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

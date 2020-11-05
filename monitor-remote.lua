local inspect = require('inspect')
local mqtt = require('mqtt')
local cqueues = require('cqueues')
local thread = require('cqueues.thread')
local mqtt_config
local mqtt_thread
local mqtt_thread_pipe

function config(conf)
   print("monitor-remote.lua: config")
   mqtt_config = conf
   return 0
end

function mqtt_thread_func(conn, host, user, password, topic)
   local inspect = require('inspect')
   local mqtt = require('mqtt')
   local cqueues = require("cqueues")
   local cq = cqueues.new()
   local loop = mqtt.get_ioloop()
   local client = mqtt.client {
      uri = host,
      username = user,
      password = password,
      clean = true,
   }
   client:on {
      connect = function(reply)
	 if reply.rc ~= 0 then
	    print("Failed to connect to broker: ",
		  reply:reason_string(), reply)
	 end

	 subscribe_options = {
	    topic = topic,
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
      thread.start(mqtt_thread_func,
		   conf.Host,
		   conf.User,
		   conf.Password,
		   conf.CommandTopic)
   return 0
end

function shutdown()
   print("monitor-remote.lua: shutdown")
   mqtt_thread_pipe:write("finish\n")
   mqtt_thread:join()
   return 0
end


collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)

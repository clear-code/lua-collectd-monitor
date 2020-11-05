local inspect = require('inspect')
local mqtt = require('mqtt')

local mqtt_client
local mqtt_loop = mqtt.get_ioloop()
local mqtt_handled = false

function config(conf)
   print("monitor-remote.lua: config")

   mqtt_client = mqtt.client {
      uri = conf.Host,
      username = conf.User,
      password = conf.Password,
      clean = true,
   }
   mqtt_client:on {
      connect = function(reply)
	 if reply.rc ~= 0 then
	    print("Failed to connect to broker: ",
		  reply:reason_string(), reply)
	 end

	 subscribe_options = {
	    topic = conf.CommandTopic,
	 }
	 assert(mqtt_client:subscribe(subscribe_options))

	 mqtt_handled = true
      end,

      subscribe = function(reply)
	 print(inspect(reply))
	 mqtt_handled = true
      end,

      unsubscribe = function(reply)
	 print(inspect(reply))
	 mqtt_handled = true
      end,

      message = function(msg)
	 assert(mqtt_client:acknowledge(msg))
	 print("received message", msg)
	 mqtt_handled = true
      end,

      acknowledge = function()
	 print("acknowledge")
	 mqtt_handled = true
      end,

      error = function()
	 print("error")
	 mqtt_handled = true
      end,

      close = function()
	 print("close")
	 mqtt_handled = true
      end,

      auth = function()
	 print("auth")
	 mqtt_handled = true
      end,
   }

   return 0
end

function init()
   mqtt_loop:add(mqtt_client)
   return 0
end

function read()
   print("monitor-remote.lua: read")
   while true do
      mqtt_loop:iteration()
      if not mqtt_handled then
	 break
      end
      mqtt_handled = false
   end
   return 0
end

function shutdown()
   print("monitor-remote.lua: shutdown")
   mqtt_loop:remove(mqtt_client)
   return 0
end


collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_read(read)

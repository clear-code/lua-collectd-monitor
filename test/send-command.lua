local inspect = require('inspect')
local mqtt = require('mqtt')
local lunajson = require('lunajson')

local conf = {
   Host = "localhost",
   User = "test-user",
   Password = "test-user",
   secure = false,
   CleanSession = false,
   CommandTopic = "test-topic",
   QoS = 0,
   Command = "Command",
}

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

      command = {
         command = conf.Command,
         timestamp = os.date("!%Y-%m-%dT%TZ"),
      }

      options = {
         topic = conf.CommandTopic,
         payload = lunajson.encode(command),
         qos = conf.QoS,
         callback = function(packet)
            print(inspect(packet))
            client:disconnect()
         end,
      }

      client:publish(options)
   end,

   error = function(msg)
      print(msg)
   end,
}

mqtt.run_ioloop(client)

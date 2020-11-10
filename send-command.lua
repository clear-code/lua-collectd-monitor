#!/usr/bin/env lua

local inspect = require('inspect')
local mqtt = require('mqtt')
local lunajson = require('lunajson')
local argparse = require('argparse')

local parser = argparse("send-command", "Send a command to monitor-remote.lua")
parser:argument("command", "A command to send")
parser:option("-h --host", "MQTT Broker", "localhost")
parser:option("-u --user", "MQTT User")
parser:option("-p --password", "Password for the MQTT user")
parser:flag("-s --secure", "Use TLS", false)
parser:option("-q --qos", "QoS for the command", 0)
parser:option("-t --topic", "Topic to send")

local args = parser:parse()

local client = mqtt.client {
   uri = args.host,
   username = args.user,
   password = args.password,
   secure = args.secure,
   clean = true,
}

client:on {
   connect = function(reply)
      if reply.rc ~= 0 then
         print("Failed to connect to broker: ",
               reply:reason_string(), reply)
         return
      end

      command = {
         command = args.command,
         timestamp = os.date("!%Y-%m-%dT%TZ"),
      }

      options = {
         topic = args.topic,
         payload = lunajson.encode(command),
         qos = args.qos,
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

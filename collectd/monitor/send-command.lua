#!/usr/bin/env lua

local inspect = require('inspect')
local mqtt = require('mqtt')
local lunajson = require('lunajson')
local argparse = require('argparse')

local parser = argparse("send-command", "Send a command to monitor-remote.lua")
parser:argument("service", "A service name to interact")
parser:argument("command", "A command for the service to send")
parser:option("-h --host", "MQTT Broker", "localhost")
parser:option("-u --user", "MQTT User")
parser:option("-p --password", "Password for the MQTT user")
parser:flag("-s --secure", "Use TLS", false)
parser:option("-q --qos", "QoS for the command", 2)
parser:option("-t --topic", "Topic to send")
parser:option("-r --result-topic", "Topic to receive command result")

local args = parser:parse()

local client = mqtt.client {
   uri = args.host,
   username = args.user,
   password = args.password,
   secure = args.secure,
   clean = false,
}

function subscribe()
   if not args.result_topic then
      return
   end

   local subscribe_options = {
      topic = args.result_topic,
      qos = tonumber(args.qos),
   }
   assert(client:subscribe(subscribe_options))
end

client:on {
   connect = function(reply)
      if reply.rc ~= 0 then
         io.stderr:write("Failed to connect to broker: ",
                         reply:reason_string(), "\n")
         return
      end

      subscribe()

      math.randomseed(os.clock())
      local command = {
         task_id = math.random(1, 2^32),
         service = args.service,
         command = args.command,
         timestamp = os.date("!%Y-%m-%dT%TZ"),
      }
      local command_json = lunajson.encode(command)

      print("Send command: " .. command_json)

      local publish_options = {
         topic = args.topic,
         payload = command_json,
         qos = tonumber(args.qos),
         callback = function(packet)
            print(inspect(packet))
            if not args.result_topic then
               assert(client:disconnect())
            end
         end,
      }
      assert(client:publish(publish_options))
   end,

   message = function(packet)
      print("Received a result: " .. inspect(packet))
      assert(client:acknowledge(packet))
      assert(client:disconnect())
   end,

   error = function(msg)
      io.stderr:write(msg, "\n")
      assert(client:disconnect())
   end,
}

mqtt.run_ioloop(client)

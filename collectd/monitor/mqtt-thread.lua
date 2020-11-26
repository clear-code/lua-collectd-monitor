function mqtt_thread(monitor_thread_pipe, conf, logger)
   local errno = require('cqueues.errno')
   local lunajson = require('lunajson')
   local inspect = require('inspect')
   local command_threads = {}

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
         if packet_id then
            debug("Subscribed to ", conf.CommandTopic, ", packet_id: ", packet_id)
         else
            error("Failed to subscribe: ", err)
         end
      end,

      subscribe = function(packet)
         debug("MQTT subscribe callback: ", inspect(packet))
      end,

      unsubscribe = function(packet)
         debug("MQTT unsubscribe callback: ", inspect(packet))
      end,

      message = function(packet)
         debug("Received message: ", packet)

         local succeeded, msg = client:acknowledge(packet)
         if not succeeded then
            error("Failed to acknowledge: ", msg)
            return
         end

         function is_valid_message(msg)
            return msg and msg.task_id and msg.service and msg.command
         end

         succeeded, msg = pcall(lunajson.decode, packet.payload)
         if not succeeded then
            error("Failed to decode MQTT message: ", packet.payload)
            return
         elseif not is_valid_message(msg) then
            error("Invalid message: ", packet.payload)
            return
         end

         debug("Received a command: ", msg.command, ", task_id: ", msg.task_id)
         dispatch_command(msg.task_id, msg.service, msg.command)
      end,

      acknowledge = function(packet)
         debug("MQTT acknowledge callback: ", inspect(packet))
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

   function dispatch_command(task_id, service_name, command_name)
      local ERROR_NO_CONFIG  = 0x1001
      local ERROR_NO_SERVICE = 0x1002
      local ERROR_NO_COMMAND = 0x1003
      local ERROR_DUPLICATE_TASK_ID = 0x1100

      if command_threads[task_id] then
         local err_msg = "Received duplicate task_id: " .. tostring(task_id)
         error(err_msg)
         send_reply(task_id, ERROR_DUPLICATE_TASK_ID, err_msg)
         return
      end

      local file, err_msg, err, errnum = io.open(conf.MonitorConfigPath, "rb")
      if not file then
         error(err_msg)
         send_reply(task_id, ERROR_NO_CONFIG, err_msg)
         return
      end
      local content = file:read("*all")
      file:close()

      local succeeded, monitor_settings = pcall(lunajson.decode, content)
      if not succeeded or not monitor_settings or not monitor_settings["services"] then
         err_msg = "Cannot handle \"" .. command_name .. "\" command: No service is configured!"
         error(err_msg)
         send_reply(task_id, ERROR_NO_CONFIG, err_msg)
         return
      end

      local service_settings = monitor_settings["services"][service_name]

      if not service_settings then
         err_msg = "Cannot find the service settings for: " .. service_name
         error(err_msg)
         send_reply(task_id, ERROR_NO_SERVICE, err_msg)
         return
      end

      local commands = service_settings["commands"]

      if not commands or not commands[command_name] then
         err_msg = "Cannot find " .. command_name .. " command for " .. service_name
         error(err_msg)
         send_reply(task_id, ERROR_NO_COMMAND, err_msg)
         return
      end

      debug("Found a command: ",
            "service_name: ", service_name, ", ",
            "command_name: ", command_name, ", ",
            "command: ", commands[command_name])

      local thread = require('cqueues.thread')
      local command_thread, command_thread_pipe =
         thread.start(run_command,
                      commands[command_name],
                      tostring(task_id))
      command_threads[task_id] = {
         service = service_name,
         command = command_name,
         thread = command_thread,
         pipe = command_thread_pipe,
         result_json = "",
      }
   end

   function run_command(thread_pipe, command_line, task_id)
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

      local result = {
         task_id = tonumber(task_id),
         code = tonumber(lines[#lines]),
         message = command_output,
      }

      thread_pipe:write(require('lunajson').encode(result) .. "\n")
   end

   function send_reply(task_id, code, msg)
      if not conf.CommandResultTopic then
         return
      end

      local result_json = lunajson.encode(
         {
            task_id = task_id,
            code = code,
            message = msg,
            timestamp = os.date("!%Y-%m-%dT%TZ"),
         }
      )
      debug("Command result reply: ", result_json)

      local succeeded_or_packet_id, msg = client:publish(
         {
            topic = conf.CommandResultTopic,
            payload = result_json,
            qos = conf.QoS,
         }
      )
      if not succeeded_or_packet_id then
         error("Failed to send command result: ", msg)
      end
   end

   function handle_command_task(task_id, ctx)
      local line, why = ctx.pipe:recv("*L", "t")
      if line ~= nil then
         ctx.result_json = ctx.result_json .. line
      end
      if why ~= errno.EAGAIN then
         ctx.thread:join()
         local succeeded, result = pcall(lunajson.decode, ctx.result_json)
         if succeeded and result then
            send_reply(result.task_id, result.code, result.message)
         else
            error("Failed to decode result JSON: ", ctx.result_json)
            send_reply(tonumber(key), 0x1100,
                       "Failed to decode result json" .. ctx.result_json)
         end
         command_threads[task_id] = nil
      end
   end

   --
   -- Main I/O loop
   --
   local autocreate = true
   local loop_options = {
      -- timeout = 0.005, -- network operations timeout in seconds
      -- sleep = 0,       -- sleep interval after each iteration
      -- sleep_function = require("socket").sleep,
   }
   local loop = mqtt.get_ioloop(autocreate, loop_options)
   loop:add(client)

   while true do
      loop:iteration()

      for task_id, ctx in pairs(command_threads) do
         handle_command_task(task_id, ctx)
      end

      local line, why = monitor_thread_pipe:recv("*L", "t")
      if (line == "finish\n") or (why ~= errno.EAGAIN) then
         break
      end
   end

   client:disconnect()
   loop:remove(client)
   info("MQTT thread finished")
end

return mqtt_thread

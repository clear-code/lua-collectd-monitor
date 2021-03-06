function mqtt_thread(monitor_thread_pipe, monitor_config)
   local utils = require('collectd/monitor/utils')
   local logger = utils.get_logger("collectd-monitor-remote", monitor_config)
   local ConfigReplacer = require('collectd/monitor/config-replacer')
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
      uri = monitor_config.Host,
      username = monitor_config.User,
      password = monitor_config.Password,
      secure = monitor_config.Secure,
      clean = monitor_config.CleanSession,
      reconnect = monitor_config.ReconnectInterval,
   }
   client:on {
      connect = function(reply)
         if reply.rc ~= 0 then
            error("Failed to connect to broker: ",
                  reply:reason_string(), reply)
            return
         end

         local subscribe_options = {
            topic = monitor_config.CommandTopic,
            qos = monitor_config.QoS,
         }

         local packet_id, err = client:subscribe(subscribe_options)
         if packet_id then
            debug("Subscribed to ", monitor_config.CommandTopic, ", packet_id: ", packet_id)
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
            if not msg or not msg.task_id then
               return false
            end

            if msg.service and msg.command then
               return true
            elseif msg.config then
               return true
            else
               return false
            end
         end

         succeeded, msg = pcall(lunajson.decode, packet.payload)
         if not succeeded then
            error("Failed to decode MQTT message: ", packet.payload)
            return
         elseif not is_valid_message(msg) then
            error("Invalid message: ", packet.payload)
            return
         end

         if msg.command then
            debug("Received a command: ", msg.command, ", task_id: ", msg.task_id)
            dispatch_command(msg.task_id, msg.service, msg.command)
         elseif msg.config then
            debug("Received a config: ", msg.config, ", task_id: ", msg.task_id)
            dispatch_config(msg.task_id, msg.config)
         end
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
      local ERROR_NOT_IMPLEMENTED  = 0x1000
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

      local file, err_msg, err, errnum = io.open(monitor_config.MonitorConfigPath, "rb")
      if not file then
         error(err_msg)
         send_reply(task_id, ERROR_NO_CONFIG, err_msg)
         return
      end
      local content = file:read("*all")
      file:close()

      local succeeded, monitor_settings = pcall(lunajson.decode, content)
      if not succeeded or not monitor_settings or not monitor_settings["Services"] then
         err_msg = "Cannot handle \"" .. command_name .. "\" command: No service is configured!"
         error(err_msg)
         send_reply(task_id, ERROR_NO_CONFIG, err_msg)
         return
      end

      local service_settings = monitor_settings["Services"][service_name]

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
      function command(command_line)
         local cmdline = command_line .. "; echo $?"
         local pipe = io.popen(cmdline)

         local lines = {}
         for line in pipe:lines() do
            lines[#lines + 1] = line
         end

         local command_output = ""
         for i = 1, #lines - 1 do
            if i ~= 1 then
               command_output = command_output .. "\n"
            end
            command_output = command_output .. lines[i]
         end

         return tonumber(lines[#lines]), command_output
      end

      local code, command_output = command(command_line)
      local result = {
         task_id = tonumber(task_id),
         code = code,
         message = command_output,
      }
      thread_pipe:write(require('lunajson').encode(result) .. "\n")
   end

   function dispatch_config(task_id, config)
      local replacer = ConfigReplacer.new(task_id, monitor_config)
      local replaceable = replacer:prepare(config)
      local succeeded, message
      if not replaceable then
         if logger.level ~= "DEBUG" and replacer.result.code == ConfigReplacer.ERROR_BROKEN_CONFIG then
            -- Shouln't show detailed message because received collectd.conf may incldue
            -- secret information.
            error("Cannot launch collectd with new config with task_id:" .. task_id)
         else
            error(replacer.result.message)
         end
         send_reply(task_id, replacer.result.code, replacer.result.message)
         return
      end

      if replacer:is_using_systemd() then
         succeeded = replacer:run_by_systemd()
      else
         succeeded = replacer:kill_collectd(true)
         if succeeded then
            monitor_thread_pipe:write("run_config_replacer " .. task_id .."\n")
         end
      end

      if not succeeded then
         replacer:abort()
         error(replacer.result.message)
         send_reply(task_id, replacer.result.code, replacer.result.message)
      end
   end

   function send_reply(task_id, code, msg)
      if not monitor_config.CommandResultTopic then
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
            topic = monitor_config.CommandResultTopic,
            payload = result_json,
            qos = monitor_config.QoS,
         }
      )
      if not succeeded_or_packet_id then
         error("Failed to send command result: ", msg)
      end
   end

   function try_sending_config_replacer_result()
      local replacer = ConfigReplacer.new(0, monitor_config)
      local path = replacer:report_path()
      local file, err_msg, err, errnum = io.open(path, "rb")
      if not file then
         return
      end
      local result_json = file:read("*all")
      file:close()

      function is_valid_config_replacer_result(result)
         return result and result.task_id and result.code and result.message
      end

      local succeeded, result = pcall(lunajson.decode, result_json)
      if succeeded and is_valid_config_replacer_result(result) then
         send_reply(result.task_id, result.code, result.message)
      else
         error("Invalid log for replacing collectd.conf: ", result_json)
      end

      os.remove(path)

      return true
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

   local config_replacer_result_checker = {
      first_check_time = os.time(),
      last_check_time = 0,
      done = false,
      check = function(self)
         if self.done then
            return
         end

         local curr_time = os.time()
         local elapsed_time = curr_time - self.first_check_time
         if curr_time ~= self.last_check_time and elapsed_time <= 120 then
            self.done = try_sending_config_replacer_result()
         end
         self.last_check_time = curr_time
      end,
   }

   while true do
      loop:iteration()

      config_replacer_result_checker:check()

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

local utils = require('collectd/monitor/utils')
local inspect = require('inspect')
local lunajson = require('lunajson')
local unix = require('unix')

local monitor_config
local default_config = {}
local metric_handlers = {}
local notification_handlers = {}

local PLUGIN_NAME = "lua-collectd-monitor-local"

NOTIF_FAILURE = 1
NOTIF_WARNING = 2
NOTIF_OKAY = 4
HANDLER_TYPE_METRIC = "metric"
HANDLER_TYPE_NOTIFICATION = "notification"


function config(collectd_conf)
   monitor_config = utils.copy_table(default_config)
   utils.merge_table(monitor_config, collectd_conf)
   local config_path = monitor_config.MonitorConfigPath
   if config_path then
      local conf, err_msg = utils.load_config(config_path)
      if err_msg then
         log_error(err_msg)
      end
      utils.merge_table(monitor_config, conf)
   end

   log_debug("config: " .. inspect(monitor_config))

   return 0
end

function init()
   log_debug("init")

   math.randomseed(os.time())

   local pl_dir = require('pl.dir')
   local config_dir = monitor_config.LocalMonitorConfigDir
   if not config_dir then
      return 0
   end

   local succeeded, ret = pcall(pl_dir.getfiles, config_dir, "*.lua")
   if not succeeded then
      local err = ret
      log_error(err)
      return 0
   end

   local files = ret
   if not files then
      return 0
   end

   for i = 1, #files do
      load_local_monitoring_config(files[i])
   end

   return 0
end

function shutdown()
   log_debug("shutdown")
   return 0
end

function write(metrics)
   log_debug("write")
   for i = 1, #metric_handlers do
      dispatch_handler(metric_handlers[i], metrics)
   end
   return 0
end

function notification(notification)
   log_debug("notification")
   for i = 1, #notification_handlers do
      if notification.plugin ~= PLUGIN_NAME then
         dispatch_handler(notification_handlers[i], notification)
      end
   end
   return 0
end


function load_local_monitoring_config(path)
   local pl_file = require('pl.file')

   local content = pl_file.read(path)
   if not content then
      log_error("Failed to load " .. path)
      return false
   end

   local func, err = load(content)
   if not func then
      log_error("Failed to load " .. path .. ": " .. err)
      return false
   end

   local succeeded, metric_cb, notification_cb = pcall(func)
   if not succeeded then
      log_error("Failed to load " .. path)
      return false
   end

   register_handlers(path, metric_handlers, metric_cb)
   register_handlers(path, notification_handlers, notification_cb)

   return true
end

function register_handlers(filename, handlers, cb)
   local handler_type = HANDLER_TYPE_METRIC
   if handlers == notification_handlers then
      handler_type = HANDLER_TYPE_NOTIFICATION
   end

   if type(cb) == "function" then
      handlers[#handlers + 1] = {
         filename = filename,
         type = handler_type,
         name = nil,
         func = cb
      }
   elseif type(cb) == "table" then
      for key, func in pairs(cb) do
         handlers[#handlers + 1] = {
            filename = filename,
            type = handler_type,
            name = key,
            func = func,
         }
      end
   else
      log_error("Invalid type for local monitoring handler: " .. type(cb))
   end
end

function dispatch_handler(handler, data)
   local cb_name = get_handler_name(handler)

   local succeeded, task = pcall(handler.func, data)
   if not succeeded then
      local message = "Failed to evaluate a local monitoring config!: " .. cb_name
      log_error(message)
      return
   end

   if not task then
      return
   end

   if not is_valid_task(task) then
      log_error("Invalid task: ", inspect(task))
   end

   local command = get_command(task)

   if not command then
      local err = cb_name
      err = err .. ": Cannot find service:" .. task.service
      err = err .. ", command: " .. task.command
      log_error(err)
      return
   end

   local code, message = utils.run_command(command)

   if code == 0 then
      log_info("Succeeded to run a recovery command of " .. cb_name)
   else
      local err = "Failed to run a recovery command of "
      err = err .. cb_name .. "\nmessage: " .. message
      log_error(err)
   end

   emit_notification(handler, task, code, message)
end

function emit_notification(handler, task, code, message)
   local cb_name = get_handler_name(handler)

   local severity = NOTIF_OKAY
   if code ~= 0 then
      severity = NOTIF_FAILURE
   end

   local result = {
      task_id = math.random(1, 2^32),
      code = code,
      message = message,
   }
   local result_json = lunajson.encode(result)
   if #result_json > 127 then
      result.message = "Omitted due to exceeding max message length!"
      result_json = lunajson.encode(result)
   end

   local notification = {
      host = unix.gethostname(),
      message = result_json,
      plugin = PLUGIN_NAME,
      plugin_instance = "",
      severity = severity,
      time = os.time(),
      type = cb_name,
      type_instance = "",
      meta = {},
   }
   dispatch_notification(notification)
end

function get_handler_name(handler)
   local name = handler.filename
   name = name .. "::" .. handler.type
   if handler.name then
      name = name .. "::" .. handler.name
   end
   return name
end

function get_service_config(task)
   if not monitor_config.Services then
      return nil
   end
   if not monitor_config.Services[task.service] then
      return nil
   end
   return monitor_config.Services[task.service]
end

function get_command(task)
   local config = get_service_config(task)
   if not config then
      return nil
   end
   if not config.commands then
      return nil
   end
   return config.commands[task.command]
end

function is_valid_task(task)
   if type(task) ~= "table" then
      return false
   end
   if type(task.service) ~= "string" then
      return false
   end
   if type(task.command) ~= "string" then
      return false
   end
   return true
end

function log_error(msg)
   collectd.log_error(PLUGIN_NAME .. ": " .. msg)
end

function log_warn(msg)
   collectd.log_warning(PLUGIN_NAME .. ": " .. msg)
end

function log_info(msg)
   collectd.log_info(PLUGIN_NAME .. ": " .. msg)
end

function log_debug(msg)
   collectd.log_debug(PLUGIN_NAME .. ": " .. msg)
end


collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_write(write)
collectd.register_notification(notification)

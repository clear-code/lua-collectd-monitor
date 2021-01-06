local utils = require('collectd/monitor/utils')
local inspect = require('inspect')
local monitor_config
local default_config = {}
local write_callbacks = {}
local notification_callbacks = {}

function config(collectd_conf)
   monitor_config = utils.copy_table(default_config)
   utils.merge_table(monitor_config, collectd_conf)
   local config_path = monitor_config.MonitorConfigPath
   if config_path then
      local conf, err_msg = utils.load_config(config_path)
      if err_msg then
         collectd.log_error(err_msg)
      end
      utils.merge_table(monitor_config, conf)
   end

   collectd.log_debug("config: " .. inspect(monitor_config))

   return 0
end

function register_callbacks(callbacks, cb)
   if type(cb) == "function" then
      callbacks[#callbacks + 1] = cb
   elseif type(cb) == "table" then
      for i = 0, #cb do
         callbacks[#callbacks + 1] = cb[i]
      end
   else
      collectd.log_error("Invalid type for callback: " .. type(cb))
   end
end

function load_local_monitoring_config(path)
   local pl_file = require('pl.file')

   local content = pl_file.read(path)
   if not content then
      collectd.log_error("Failed to load " .. path)
      return false
   end

   local func, err = load(content)
   if not func then
      collectd.log_error("Failed to load " .. path .. ": " .. err)
      return false
   end

   local succeeded, write_cb, notification_cb = pcall(func)
   if not succeeded then
      collectd.log_error("Failed to load " .. path)
      return false
   end

   register_callbacks(write_callbacks, write_cb)
   register_callbacks(notification_callbacks, notification_cb)

   return true
end

function init()
   collectd.log_debug("collectd.monitor.local: init")

   local pl_dir = require('pl.dir')
   local config_dir = monitor_config.LocalMonitorConfigDir
   if not config_dir then
      return 0
   end

   local succeeded, ret = pcall(pl_dir.getfiles, config_dir, "*.lua")
   if not succeeded then
      local err = ret
      collectd.log_error(err)
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
   return 0
end

function write(metrics)
   return 0
end

function notification(notification)
   return 0
end

collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_write(write)
collectd.register_notification(notification)

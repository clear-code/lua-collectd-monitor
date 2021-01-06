local utils = require('collectd/monitor/utils')
local inspect = require('inspect')
local monitor_config
local default_config = {}

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
end

function init()
   return 0
end

function shutdown()
   return 0
end

function read()
   return 0
end

function write(metrics)
   return 0
end

collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_read(read)
collectd.register_write(write)

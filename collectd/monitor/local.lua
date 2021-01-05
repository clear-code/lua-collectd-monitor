local utils = require('collectd/monitor/utils')
local inspect = require('inspect')
local monitor_config
local default_config = {}

function config(collectd_conf)
   local conf = utils.copy_table(default_config)
   utils.merge_table(conf, collectd_conf)
   if conf.MonitorConfigPath then
      local err_msg
      monitor_config, err_msg = utils.load_config(conf.MonitorConfigPath)
      if err_msg then
         collectd.log_error(err_msg)
      end
      utils.merge_table(conf, monitor_config)
   end

   collectd.log_debug("config: " .. inspect(conf))
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

--
-- Register collectd callback functions
--

local lunajson = require('lunajson')
local utils = require('monitor-utils')

local monitor_config_json
local monitor_thread
local monitor_thread_pipe
local default_config = {
   ClearSession = false,
   QoS = 2,
}

collectd.register_config(
   function(collectd_conf)
      collectd.log_debug("monitor-remote.lua: config")

      local conf = utils.copy_table(default_config)
      utils.merge_table(conf, collectd_conf)
      if conf.MonitorConfigPath then
         local monitor_config, err_msg = utils.load_config(conf.MonitorConfigPath)
         if err_msg then
            collectd.log_error(err_msg)
         end
         utils.merge_table(conf, monitor_config)
      end

      monitor_config_json = lunajson.encode(conf)

      local debug_config_json = monitor_config_json
      if conf.Password then
         conf.Password = "********"
         debug_config_json = lunajson.encode(conf)
      end
      collectd.log_debug("config: " .. debug_config_json)

      return 0
   end
)

collectd.register_init(
   function()
      collectd.log_debug("monitor-remote.lua: init")
      local conf = monitor_config
      monitor_thread, monitor_thread_pipe =
         require('cqueues.thread').start(require('monitor-thread'),
                                         monitor_config_json)
      return 0
   end
)

collectd.register_shutdown(
   function()
      collectd.log_debug("monitor-remote.lua: shutdown")
      monitor_thread_pipe:write("finish\n")
      monitor_thread:join()
      return 0
   end
)

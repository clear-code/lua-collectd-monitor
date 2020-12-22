--
-- Register collectd callback functions
--

local lunajson = require('lunajson')
local utils = require('collectd/monitor/utils')

local monitor_config_json
local monitor_thread
local monitor_thread_pipe
local default_config = {
   CleanSession = false,
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

-- Poll MQTT messages and handle commands in another thread.
-- Since it will be called by cqueues.thread, it can't refer parent objects,
-- it can just only receive string arguments from the caller.
-- refs:
--   https://github.com/wahern/cqueues
--   https://raw.githubusercontent.com/wahern/cqueues/master/doc/cqueues.pdf
local monitor_thread_func = function(pipe, conf_json, load_path)
   local inspect = require('inspect')
   local lunajson = require('lunajson')
   local utils = require('collectd/monitor/utils')
   local conf = lunajson.decode(conf_json)

   if load_path then
      package.path = load_path
   end

   local logger = utils.get_logger("collectd-monitor-remote", conf)
   local ret, err = pcall(require('collectd/monitor/mqtt-thread'), pipe, conf, logger)

   if err then
      logger:error(err)
   end
end

collectd.register_init(
   function()
      collectd.log_debug("monitor-remote.lua: init")
      local conf = monitor_config
      monitor_thread, monitor_thread_pipe =
         require('cqueues.thread').start(monitor_thread_func,
                                         monitor_config_json,
                                         package.path)
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

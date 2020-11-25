--
-- Register collectd callback functions
--

local monitor_config_json
local monitor_thread
local monitor_thread_pipe

collectd.register_config(
   function(conf)
      collectd.log_debug("monitor-remote.lua: config")

      conf.ClearSession = conf.ClearSession or false
      conf.QoS = conf.QoS or 2

      local lunajson = require('lunajson')
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

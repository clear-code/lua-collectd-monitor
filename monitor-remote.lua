--
-- Register collectd callback functions
--

local mqtt_config_json
local mqtt_thread
local mqtt_thread_pipe

collectd.register_config(
   function(conf)
      collectd.log_debug("monitor-remote.lua: config")

      conf.ClearSession = conf.ClearSession or false
      conf.QoS = conf.QoS or 2

      local lunajson = require('lunajson')
      mqtt_config_json = lunajson.encode(conf)

      local debug_config_json = mqtt_config_json
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
      local conf = mqtt_config
      mqtt_thread, mqtt_thread_pipe =
         require('cqueues.thread').start(require('monitor-thread'),
                                         mqtt_config_json)
      return 0
   end
)

collectd.register_shutdown(
   function()
      collectd.log_debug("monitor-remote.lua: shutdown")
      mqtt_thread_pipe:write("finish\n")
      mqtt_thread:join()
      return 0
   end
)

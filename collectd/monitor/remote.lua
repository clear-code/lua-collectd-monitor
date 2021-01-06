local lunajson = require('lunajson')
local utils = require('collectd/monitor/utils')

local monitor_config
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

      monitor_config_json = lunajson.encode(monitor_config)

      local debug_config_json = monitor_config_json
      if monitor_config.Password then
         monitor_config.Password = "********"
         debug_config_json = lunajson.encode(monitor_config)
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

   local ret, err = pcall(require('collectd/monitor/mqtt-thread'), pipe, conf)

   if err then
      local logger = utils.get_logger("collectd-monitor-remote", conf)
      logger:error(err)
   end
end

collectd.register_init(
   function()
      collectd.log_debug("monitor-remote.lua: init")
      monitor_thread, monitor_thread_pipe =
         require('cqueues.thread').start(monitor_thread_func,
                                         monitor_config_json,
                                         package.path)
      return 0
   end
)

function run_config_replacer(task_id)
   local unix = require('unix')
   local pid = unix.fork()

   if pid > 0 then
      -- parent process
      return
   elseif pid < 0 then
      return
   end

   -- in child process
   unix.setsid()
   pid = unix.fork()

   if pid > 0 then
      -- parent process
      os.exit(0)
   elseif pid < 0 then
      -- error
      os.exit(1)
   end

   -- in grand child process
   unix.setsid()

   local ConfigReplacer = require('collectd/monitor/config-replacer')
   local replacer = ConfigReplacer.new(task_id, monitor_config)
   replacer:run()
   replacer:report()

   os.exit(0)
end

collectd.register_shutdown(
   function()
      collectd.log_debug("monitor-remote.lua: shutdown")

      local config_replacer_task_id

      monitor_thread_pipe:write("finish\n")

      for line in monitor_thread_pipe:lines() do
         local task_id = line:match("run_config_replacer (%d+)")
         if task_id then
            config_replacer_task_id = tonumber(task_id)
         end
      end

      monitor_thread:join()

      if config_replacer_task_id then
         run_config_replacer(config_replacer_task_id)
      end

      return 0
   end
)

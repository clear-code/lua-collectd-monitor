#!/usr/bin/env luajit

local argparse = require('argparse')
local parser = argparse("replace-config", "Replace the collectd's config and restart the daemon")
parser:argument({
      name = "new_config_path",
      description = "A path to collectd's config file",
      args = "?"
})
parser:option("-c --command", "collectd command path", nil)
parser:option("-C --config", "collectd config path", nil)
parser:option("-P --pid-file", "collectd pid file path", nil)
parser:option("-T --task-id", "A task ID allocated by a caller", 0)
parser:option("--log-device", "Log device [syslog or stdout]", "stdout")
parser:option("--log-level", "Log level [err, warn, info, debug]", "info")
parser:flag("-S --skip-prepare", "Skip preparing a new config")
local args = parser:parse()

function new_config(path)
   local file = io.open(path)
   local config = file:read("*a")
   file:close()
   return config
end

local options = {
   LogDevice = args.log_device,
   LogLevel = args.log_level,
   Services = {
      collectd = {
         CommandPath = args.command,
         ConfigPath = args.config,
         PIDPath = args.pid_file,
      },
   },
}

local Replacer = require('collectd/monitor/config-replacer')
local replacer = Replacer.new(args.task_id, options)

if not args.skip_prepare then
   if not args.new_config_path then
      replacer:error("Config path isn't specified!")
      os.exit(1)
   end
   local config = new_config(args.new_config_path)
   local replaceable, err = replacer:prepare(config)
   if not replaceable then
      replacer:report()
      os.exit(1)
   end
end

if replacer:kill_collectd() then
   local succeeded, err = replacer:run()
   replacer:report()
   if succeeded then
      os.exit(0)
   else
      replacer:abort()
      os.exit(1)
   end
else
   replacer:report()
   replacer:abort()
   os.exit(1)
end

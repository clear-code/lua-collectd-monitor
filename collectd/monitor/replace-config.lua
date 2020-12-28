#!/usr/bin/env luajit

local argparse = require('argparse')
local parser = argparse("replace-config", "Replace the collectd's config and restart the daemon")
parser:argument("new_config_path", "A path to collectd's config file")
parser:option("-c --command", "collectd command path", nil)
parser:option("-C --config", "collectd config path", nil)
parser:option("-P --pid-file", "collectd pid file path", nil)
local args = parser:parse()

function new_config(path)
   local file = io.open(path)
   local config = file:read("*a")
   file:close()
   return config
end

local config = new_config(args.new_config_path)
local options = {
   LogDevice = "stdout",
   LogLevel = "debug",
   Services = {
      collectd = {
         CommandPath = args.command,
         ConfigPath = args.config,
         PIDPath = args.pid_file,
      },
   },
}

local Replacer = require('collectd/monitor/config-replacer')
local replacer = Replacer.new(0, options)
local replaceable, err = replacer:prepare(config)
if not replaceable then
   replacer:report()
   os.exit(1)
end

if replacer:kill_collectd() then
   replacer:run()
   replacer:report()
   if succeeded then
      os.exit(0)
   else
      os.exit(1)
   end
else
   replacer:abort()
   os.exit(1)
end

#!/usr/bin/env luajit

local argparse = require('argparse')
local parser = argparse("replace-config", "Replace the collectd's config and restart the daemon")
parser:argument("new_config_path", "A path to collectd's config file")
parser:option("-c --command", "collectd command path", "/usr/sbin/collectd")
parser:option("-C --config", "collectd config path", "/etc/collectd/collectd.conf")
parser:option("-P --pid-file", "collectd pid file path", "/run/collectd.pid")
local args = parser:parse()

function new_config(path)
   local file = io.open(path)
   local config = file:read("*a")
   file:close()
   return config
end

local config = new_config(args.new_config_path)
local options = {
   CommandPath = args.command,
   ConfigPath = args.config,
   PIDPath = args.pid_file,
}

local logger_options = {
   LogDevice = "stdout",
   LogLevel = "debug",
}

local Replacer = require('collectd/monitor/config-replacer')
local replacer = Replacer.new(0, options, logger_options)
local replaceable, err = replacer:prepare(config)
if not replaceable then
   print(err)
   os.exit(1)
end

if replacer:kill_collectd(true) then
   replacer:run()
   os.exit(0)
else
   replacer:abort()
   os.exit(1)
end

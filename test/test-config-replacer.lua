local luaunit = require("luaunit")
local Replacer = require("collectd/monitor/config-replacer")

local options = {
   CommandPath = "collectd",
   ConfigPath = "collectd.conf",
   PIDPath = "collectd.pid",
}

TestReplacer = {}

function TestReplacer:test_config_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:config_path(),
                         "collectd.conf")
end

function TestReplacer:test_new_config_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:new_config_path(),
                         "collectd.conf.lock")
end

function TestReplacer:test_old_config_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:old_config_path(),
                         "collectd.conf.orig")
end

function TestReplacer:test_pid_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:pid_path(),
                         "collectd.pid")
end

function TestReplacer:test_default_start_command()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:start_command(),
                         "collectd -P collectd.pid -C collectd.conf 2>&1")
end

function TestReplacer:test_start_command()
   local options = {
      CommandPath = "collectd",
      ConfigPath = "collectd.conf",
      PIDPath = "collectd.pid",
      commands = {
         start = "start",
      },
   }
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:start_command(),
                         "start")
end

function TestReplacer:test_stop_command()
   local options = {
      CommandPath = "collectd",
      ConfigPath = "collectd.conf",
      PIDPath = "collectd.pid",
      commands = {
         start = "stop",
      },
   }
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals(replacer:start_command(),
                         "stop")
end

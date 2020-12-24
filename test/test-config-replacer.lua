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
   luaunit.assert_equals("collectd.conf",
                         replacer:config_path())
end

function TestReplacer:test_new_config_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals("collectd.conf.lock",
                         replacer:new_config_path())
end

function TestReplacer:test_old_config_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals("collectd.conf.orig",
                         replacer:old_config_path())
end

function TestReplacer:test_pid_path()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals("collectd.pid",
                         replacer:pid_path())
end

function TestReplacer:test_default_start_command()
   local replacer = Replacer.new(0, options)
   luaunit.assert_equals("collectd -P collectd.pid -C collectd.conf 2>&1",
                         replacer:start_command())
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
   luaunit.assert_equals("start",
                         replacer:start_command())
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
   luaunit.assert_equals("stop",
                         replacer:start_command())
end

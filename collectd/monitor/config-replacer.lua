local utils = require('collectd/monitor/utils')
local unix = require('unix')

local ConfigReplacer = {
   SUCCEEDED = 0,
   ERROR_LOCK_FILE_EXISTS = 0x2000,
   ERROR_CANNOT_WRITE_NEW_CONFIG = 0x2001,
   ERROR_BROKEN_CONFIG = 0x2002,
   ERROR_CANNOT_STOP_COLLECTD = 0x2003,
   ERROR_CANNOT_REMOVE_PID = 0x2004,
   ERROR_CANNOT_BACKUP_CONFIG = 0x2005,
   ERROR_CANNOT_REPLACE_CONFIG = 0x2006,
   ERROR_RECOVERED = 0x2007,
   ERROR_CANNOT_RECOVER = 0x2008,
   ERROR_CANNOT_GET_NEW_PID = 0x2009,
   ERROR_CANNOT_FIND_PATH = 0x200a,
}

function sleep(sec)
   os.execute("sleep " .. tonumber(sec) .. " > /dev/null 2>&1")
end

function collectd_pid(self)
   local command, code, output
   if has_systemd_service(self) then
      command = "/bin/systemctl show --property MainPID --value collectd 2>&1"
   else
      command = "/bin/cat " .. self:pid_path() .. " 2>&1"
   end
   code, output = utils.run_command(command)
   if code ~= 0 then
      return nil, output
   end
   local pid = tonumber(output)
   if pid and pid > 0 then
      return pid
   end
   return nil
end

function collectd_dry_run(self)
   local command = self:command_path()
   local options = " -T -C " .. self:new_config_path()
   local result, err = utils.run_command(command .. options .. " 2>&1")
   if result ~= 0 then
      return false, err
   end
   return true
end

function collectd_start(self)
   local pid = collectd_pid(self)
   if pid then
      return true
   end
   local result, err = utils.run_command(self:start_command())
   if result ~= 0 then
      -- TODO: collectd always returns 0 even if it fails to start.
      return false, err
   end

   for i = 1, 3 do
      pid = collectd_pid(self)
      if pid then
         return true
      else
         sleep(1)
      end
   end
   return false, "Cannot detect new pid of collectd!"
end

function collectd_stop(self, kill_own)
   local pid = collectd_pid(self)

   if kill_own then
      if not pid then
         self.code = ConfigReplacer.ERROR_CANNOT_STOP_COLLECTD
         self.result.message = "Cannot get pid from " .. self:pid_path()
         return false, self.result.message
      end
      local current_pid = unix.getpid()
      if not current_pid then
         self.code = ConfigReplacer.ERROR_CANNOT_STOP_COLLECTD
         self.result.message = "Cannot get current pid!"
         return false, self.result.message
      end
      if pid ~= current_pid then
         self.code = ConfigReplacer.ERROR_CANNOT_STOP_COLLECTD
         self.result.message = "PID in " .. self:pid_path() .. " isn't myself!"
         return false, self.result.message
      end
   end

   if not pid then
      return true
   end

   local result, err = utils.run_command(self:stop_command())
   if result ~= 0 then
      self.code = ConfigReplacer.ERROR_CANNOT_STOP_COLLECTD
      self.result.message = err
      return false, self.result.message
   end

   return true
end

function wait_collectd_stopped(self)
   for i = 1, 10 do
      pid = collectd_pid(self)
      if pid then
         sleep(1)
      else
         return true
      end
   end
   return false, "Cannot detect removing pid file of collectd!"
end

function recover_old_config(self)
   local message
   self:info("Trying to recover old config ...")
   local succeeded, err = os.rename(self:old_config_path(), self:config_path())
   if not succeeded then
      message = "Failed to recover old config file!: " .. err
      self:error(message)
      return false, messagea
   end

   succeeded, err = collectd_start(self)
   if not succeeded then
      message = "Failed to start collectd with old config!: " .. err
      self:error(message)
      return false, message
   end

   return true
end

function prepare(self, collectd_config)
   local new_config_path = self:new_config_path()
   if utils.file_exists(new_config_path) then
      self.result.code = ConfigReplacer.ERROR_LOCK_FILE_EXISTS
      self.result.message = "Already attempting to replace collectd config!"
      return false, self.result.message
   end

   local file, err = io.open(new_config_path, "wb")
   if not file then
      self.result.code = ConfigReplacer.ERROR_CANNOT_WRITE_NEW_CONFIG
      self.result.message = "Failed to write new config: " .. err
      return false, self.result.message
   end
   file:write(collectd_config)
   file:close()
   utils.run_command("chmod 600 " .. new_config_path)

   local succeeded, err = collectd_dry_run(self)
   if not succeeded then
      self.result.code = ConfigReplacer.ERROR_BROKEN_CONFIG
      self.result.message = "New config seems broken!: " .. err
      os.remove(new_config_path)
      return false, self.result.message
   end

   return true
end

function run(self)
   local message

   -- check the running process
   local succeeded, err = wait_collectd_stopped(self)
   if not succeeded then
      self.result.code = ConfigReplacer.ERROR_CANNOT_REMOVE_PID
      self.result.message = err
      return false, self.result.message
   end

   local config_path = self:config_path()
   local old_config_path = self:old_config_path()
   local new_config_path = self:new_config_path()

   -- save old config
   succeeded, err = os.rename(config_path, old_config_path)
   if not succeeded then
      message = string.format("Failed to back up old config file! (<%s> => <%s>): %s",
                              config_path, old_config_path, err)
      self:error(message)
      self.result.code = ConfigReplacer.ERROR_CANNOT_BACKUP_CONFIG
      self.result.message = message
      return false, self.result.message
   end

   -- replace the config with new one
   succeeded, err = os.rename(new_config_path, config_path)
   if not succeeded then
      message = string.format("Failed to replace config file! (%s => %s): %s",
                              new_config_path, config_path, err)
      self:error(message)
      self.result.code = ConfigReplacer.ERROR_CANNOT_REPLACE_CONFIG
      self.result.message = message
      return false, self.result.message
   end

   -- try to restart
   succeeded, err = collectd_start(self)
   if not succeeded then
      self:error("Failed to start collectd!: " .. err)
      succeeded, message = recover_old_config(self)
      if not succeeded then
         self.result.code = ConfigReplacer.ERROR_CANNOT_RECOVER
         self.result.message = message
         return false, self.result.message
      end
      succeeded = false
      message = err
   end

   pid = collectd_pid(self)
   if pid then
      self:debug("collectd has been restarted with PID " .. pid)
      if succeeded then
         self.result.code = ConfigReplacer.SUCCEEDED
         self.result.message = "Succeeded to replace the config."
         return true
      else
         self.result.code = ConfigReplacer.ERROR_RECOVERED
         self.result.message = message
         return false, self.result.message
      end
   else
      self.result.code = ConfigReplacer.ERROR_CANNOT_GET_NEW_PID
      self.result.message = "Failed to get new pid of collectd!"
      return false, self.result.message
   end
end

function get_lua_path(self)
   local succeeded, output = utils.run_command("which luajit")
   if succeeded then
      return output
   end
   local succeeded, output = utils.run_command("which lua")
   if succeeded then
      return output
   end
   return nil
end

function run_by_systemd(self)
   local pl_path = require('pl.path')
   local pl_stringx = require('pl.stringx')
   local lua_path = self:lua_path()
   local script_path = nil
   local options = "--skip-prepare"

   if not lua_path then
      self.code = ConfigReplacer.ERROR_CANNOT_FIND_PATH
      self.result.message = "Cannot find lua or luajit"
      return false, self.result.message
   end

   for i, path in pairs(pl_stringx.split(package.path, ";")) do
      if pl_stringx.endswith(path, "?.lua") then
         path = pl_path.dirname(path) .. "/collectd/monitor/replace-config.lua"
         if utils.file_exists(path) then
            script_path = path
            break
         end
      end
   end

   if not script_path then
      self.code = ConfigReplacer.ERROR_CANNOT_FIND_PATH
      self.result.message = "Cannot find replace-config.lua"
      return false, self.result.message
   end

   options = options .. " --task-id " .. self.task_id
   if self.options.LogDevice then
      options = options .. " --log-device " .. self.options.LogDevice
   else
      options = options .. " --log-device syslog"
   end
   if self.options.LogLevel then
      options = options .. " --log-level " .. self.options.LogLevel
   end

   local command = "/bin/systemd-run " .. self:lua_path() .. " " .. script_path .. " " .. options
   local code, message = utils.run_command(command)
   if code == 0 then
      return true
   else
      self.code = ConfigReplacer.ERROR_CANNOT_STOP_COLLECTD
      self.result.message = message
      return false, message
   end
end

function abort(self)
   local new_config_path = self:new_config_path()
   -- TODO: Check a running process
   os.remove(new_config_path)
end

function has_systemd_service(self)
   if self.has_systemd_service == nil then
      local code, err = utils.run_command("/bin/systemctl status collectd 2>&1")
      if code == 0 or code == 3 then
         self.has_systemd_service = true
      else
         self.has_systemd_service = false
      end
   end
   return self.has_systemd_service
end

function report(self)
   local lunajson = require('lunajson')
   local report = {
      task_id = self.task_id,
      code = self.result.code,
      message = self.result.message,
   }
   local report_json = lunajson.encode(report)
   local report_path = self:report_path()

   if report.code == 0 then
      self:info(report.message)
   else
      self:error(report.message)
   end

   local file, err = io.open(report_path, "wb")
   if not file then
      message = "Failed to write collectd-config-replacer result: " .. err
      return false, message
   end
   file:write(report_json)
   file:close()
   utils.run_command("chmod 600 " .. report_path)
   return true
end

ConfigReplacer.new = function(task_id, options)
   local replacer = {
      task_id = task_id,
      options = {},
      result = {},
   }
   if options and options.Services and options.Services.collectd then
      replacer.options = options.Services.collectd
   end
   replacer.logger = utils.get_logger("collectd-config-replacer",
                                      options)
   replacer.prepare = prepare
   replacer.kill_collectd = collectd_stop
   replacer.run = run
   replacer.run_by_systemd = run_by_systemd
   replacer.abort = abort
   replacer.report = report
   replacer.command_path = function(self)
      if self.options.CommandPath then
         return self.options.CommandPath
      elseif utils.file_exists("/usr/sbin/collectd") then
         return "/usr/sbin/collectd"
      elseif utils.file_exists("/opt/collectd/sbin/collectd") then
         return "/opt/collectd/sbin/collectd"
      end
   end
   replacer.config_path = function(self)
      if self.options.ConfigPath then
         return self.options.ConfigPath
      elseif utils.file_exists("/usr/sbin/collectd") then
         if utils.file_exists("/etc/collectd/collectd.conf") then
            return "/etc/collectd/collectd.conf"
         else
            return "/etc/collectd.conf"
         end
      elseif utils.file_exists("/opt/collectd/sbin/collectd") then
         return "/opt/collectd/etc/collectd.conf"
      end
   end
   replacer.new_config_path = function(self)
      return self:config_path() .. ".lock"
   end
   replacer.old_config_path = function(self)
      return self:config_path() .. ".orig"
   end
   replacer.pid_path = function(self)
      if self.options.PIDPath then
         return self.options.PIDPath
      elseif utils.file_exists("/usr/sbin/collectd") then
         return "/var/run/collectd.pid"
      elseif utils.file_exists("/opt/collectd/sbin/collectd") then
         return "/opt/collectd/var/run/collectd.pid"
      end
   end
   replacer.lua_path = function(self)
      if self.options.LuaPath then
         return self.options.LuaPath
      else
         return get_lua_path(self)
      end
   end
   replacer.is_using_systemd = has_systemd_service
   replacer.report_path = function(self)
      if self.options.ReplacerReportPath then
         return self.options.ReplacerReportPath
      elseif utils.file_exists("/usr/sbin/collectd") then
         return "/var/log/collectd-config-replacer.log"
      elseif utils.file_exists("/opt/collectd/sbin/collectd") then
         return "/opt/collectd/var/log/collectd-config-replacer.log"
      end
   end
   replacer.is_using_systemd = has_systemd_service
   replacer.start_command = function(self)
      if self.options.commands and self.options.commands.start then
         return self.options.commands.start
      elseif has_systemd_service(self) then
         return "/bin/systemctl start collectd 2>&1"
      else
         local command = self:command_path()
         local options = " -P " .. self:pid_path() .. " -C " .. self:config_path()
         return command .. options .. " 2>&1"
      end
   end
   replacer.stop_command = function(self)
      if self.options.commands and self.options.commands.stop then
         return self.options.commands.stop
      elseif has_systemd_service(self) then
         return "/bin/systemctl stop collectd 2>&1"
      else
         return "kill " .. collectd_pid(self) .. " 2>&1"
      end
   end

   replacer.debug = function(self, ...)
      self.logger:debug(...)
   end
   replacer.info = function(self, ...)
      self.logger:info(...)
   end
   replacer.warn = function(self, ...)
      self.logger:warn(...)
   end
   replacer.error = function(self, ...)
      self.logger:error(...)
   end

   return replacer
end

return ConfigReplacer

local utils = require('collectd/monitor/utils')
local unix = require('unix')

local ConfigReplacer = {}

function sleep(sec)
   os.execute("sleep " .. tonumber(sec) .. " > /dev/null 2>&1")
end

function collectd_pid(self)
   local code, output = utils.run_command("/bin/cat " .. self:pid_path() .. " 2>&1")
   if code ~= 0 then
      return nil, output
   end
   local pid = tonumber(output)
   if pid and pid > 0 then
      return pid
   end
   return nil
end

function rename_file(src, dest)
   local code, err = utils.run_command("/bin/mv \"" .. src .. "\" \"" .. dest .. "\" 2>&1")
   if code ~= 0 then
      return false, err
   end
   return true
end

function remove_file(path)
   local code, err = utils.run_command("/bin/rm -f \"" .. path .. "\" >2&1")
   if code ~= 0 then
      return false, err
   end
   return true
end

function collectd_is_running(self, pid)
   pid = pid or collectd_pid(self)
   if not pid then
      return false
   end
   local result = utils.run_command("ps " .. pid .. " > /dev/null 2>&1")
   return result == 0
end

function collectd_dry_run(self)
   local command = self.options.CommandPath
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
      local current_pid = unix.getpid()
      if not current_pid then
         return false, "Cannot get current pid!"
      end
      if pid ~= current_pid then
         return false, "PID in " .. self:pid_path() .. " isn't myself!"
      end
   end

   if not pid then
      return true
   end

   local result, err = utils.run_command(self:stop_command())
   if result ~= 0 then
      return false, err
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
   self:info("Trying to recover old config ...")
   local succeeded, err = rename_file(self:old_config_path(), self:config_path())
   if not succeeded then
      self:error("Failed to recover old config file!: " .. err)
      return false
   end

   succeeded, err = collectd_start(self)
   if not succeeded then
      self:error("Failed to start collectd with old config!: " .. err)
      return false
   end

   pid = collectd_pid(self)
   if pid then
      self:debug("collectd has been restarted with old config. PID: " .. pid)
      return true
   else
      self:error("Failed to recover old confog: Failed to get new pid of collectd!")
      return false
   end
end

function prepare(self, collectd_config)
   local new_config_path = self:new_config_path()
   local message
   if utils.file_exists(new_config_path) then
      message = "Already attempting to replace collectd config!"
      return false, message
   end

   local file, err = io.open(new_config_path, "wb")
   if not file then
      message = "Failed to write new config: " .. err
      return false, message
   end
   file:write(collectd_config)
   file:close()
   utils.run_command("chmod 600 " .. new_config_path)

   local succeeded, err = collectd_dry_run(self)
   if not succeeded then
      message = "New config seems broken!: " .. err
      remove_file(new_config_path)
      return false, message
   end

   return true
end

function run(self)
   -- check the running process
   local succeeded, err = wait_collectd_stopped(self)
   if not succeeded then
      self:error(err)
      return false
   end

   -- save old config
   succeeded, err = rename_file(self:config_path(), self:old_config_path())
   if not succeeded then
      self:error("Failed to back up old config file!: " .. err)
      return false
   end

   -- replace the config with new one
   succeeded, err = rename_file(self:new_config_path(), self:config_path())
   if not succeeded then
      self:error("Failed to replace config file!: " .. err)
      return false
   end

   -- try to restart
   succeeded, err = collectd_start(self)
   if not succeeded then
      self:error("Failed to start collectd!: " .. err)
      recover_old_config(self)
      return false
   end

   pid = collectd_pid(self)
   -- TODO: report the result
   if pid then
      self:debug("collectd has been restarted with PID " .. pid)
      return true
   else
      self:error("Failed to get new pid of collectd!")
      return false
   end
end

function abort(self)
   local new_config_path = self:new_config_path()
   -- TODO: Check a running process
   remove_file(new_config_path)
end

ConfigReplacer.new = function(task_id, options, logger_options)
   local replacer = {}
   replacer.options = options
   replacer.logger = utils.get_logger("collectd-config-replacer",
                                      logger_options)
   replacer.prepare = prepare
   replacer.kill_collectd = collectd_stop
   replacer.run = run
   replacer.abort = abort
   replacer.config_path = function(self)
      return self.options.ConfigPath
   end
   replacer.new_config_path = function(self)
      return self:config_path() .. ".lock"
   end
   replacer.old_config_path = function(self)
      return self:config_path() .. ".orig"
   end
   replacer.pid_path = function(self)
      return self.options.PIDPath
   end
   replacer.start_command = function(self)
      if self.options.commands and self.options.commands.start then
         return self.options.commands.start
      else
         local command = self.options.CommandPath
         local options = " -P " .. self:pid_path() .. " -C " .. self:config_path()
         return command .. options .. " 2>&1"
      end
   end
   replacer.stop_command = function(self)
      if self.options.commands and self.options.commands.stop then
         return self.options.commands.stop
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

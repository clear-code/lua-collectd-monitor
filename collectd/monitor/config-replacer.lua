local utils = require('collectd/monitor/utils')

local ConfigReplacer = {}

function sleep(sec)
   os.execute("sleep " .. tonumber(sec) .. " > /dev/null 2>&1")
end

function collectd_pid(self)
   local file, err = io.open(self:pid_path())
   if not file then
      return nil, err
   end
   local pid_string = file:read("*a")
   file:close()
   local pid = tonumber(pid_string)
   if pid and pid > 0 then
      return pid
   end
   return nil
end

function collectd_is_running(self, pid)
   pid = pid or collectd_pid(self)
   if not pid then
      return false
   end
   local result = os.execute("ps " .. pid .. " > /dev/null 2>&1")
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

function collectd_stop(self)
   local pid = collectd_pid(self)
   if not pid then
      return true
   end
   local result, err = utils.run_command(self:stop_command())
   if result ~= 0 then
      return false, err
   end
   for i = 1, 10 do
      pid = collectd_pid(self)
      if pid then
         sleep(1)
      else
         return true
      end
   end
   return false, "Cannot to detect removing pid file of collectd!"
end

function ensure_remove_pid_file(self)
   local pid_path = self:pid_path()
   if utils.file_exists(pid_path) then
      os.remove(pid_path)
   end
   return not utils.file_exists(pid_path)
end

function recover_old_config(self)
   self:info("Trying to recover old config ...")
   local succeeded, err = os.rename(self:old_config_path(), self:config_path())
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

function prepare(self)
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
   file:write(self.collectd_config)
   file:close()
   utils.run_command("chmod 600 " .. new_config_path)

   local succeeded, err = collectd_dry_run(self)
   if not succeeded then
      message = "New config seems broken!: " .. err
      os.remove(new_config_path)
      return false, message
   end

   return true
end

function run(self)
   -- check the running process
   local pid = collectd_pid(self)
   if pid and collectd_is_running(self) then
      self:debug("collectd is running with PID " .. pid)
      local succeeded, err = collectd_stop(self)
      if not succeeded then
         self:error("Failed to stop collectd!: " .. err)
         os.exit(1)
      end
   end

   if not ensure_remove_pid_file(self) then
      self:error("Failed to remove pid file of collectd!")
      os.exit(1)
   end

   -- save old config
   succeeded, err = os.rename(self:config_path(), self:old_config_path())
   if not succeeded then
      self:error("Failed to back up old config file!: " .. err)
      os.exit(1)
   end

   -- replace with new config
   succeeded, err = os.rename(self:new_config_path(), self:config_path())
   if not succeeded then
      self:error("Failed to replace config file!: " .. err)
      os.exit(1)
   end

   -- try to restart
   succeeded, err = collectd_start(self)
   if not succeeded then
      self:error("Failed to start collectd!: " .. err)
      recover_old_config(self)
      os.exit(1)
   end

   pid = collectd_pid(self)
   if pid then
      self:debug("collectd has been restarted with PID " .. pid)
   else
      self:error("Failed to get new pid of collectd!")
   end
end

ConfigReplacer.new = function(collectd_config, options)
   local replacer = {}
   local logger_options = {
      LogDevice = "stdout",
      LogLevel = "debug",
   }
   replacer.options = options
   replacer.logger = utils.get_logger("collectd-config-replacer",
                                      logger_options)
   replacer.collectd_config = collectd_config
   replacer.prepare = prepare
   replacer.run = run
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
   replacer.info = function(...)
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

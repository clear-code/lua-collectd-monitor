local utils = {}

utils.load_config = function(path)
   local lunajson = require('lunajson')
   local file, err_msg, err, errnum = io.open(path, "rb")
   if not file then
      return {}, err_msg
   end
   local content = file:read("*all")
   file:close()

   local succeeded, conf = pcall(lunajson.decode, content)
   if not succeeded or not conf then
      local err_msg = "Failed to load " .. path
      return {}, err_msg
   end

   return conf, nil
end

utils.merge_table = function(conf1, conf2)
   if not conf1 then
      conf1 = {}
   end
   local conf1_type = type(conf2)
   if type(conf2) == 'table' then
      for key, value in pairs(conf2) do
         conf1[key] = value
      end
      setmetatable(conf1, utils.copy_table(nil, getmetatable(conf2)))
   else
      conf1 = conf2
   end
   return conf1
end

utils.copy_table = function(conf)
   return utils.merge_table(nil, conf)
end

utils.file_exists = function(path)
   local file = io.open(path, "r")
   if file then
      file:close()
      return true
   else
      return false
   end
end

utils.directory_exists = function(path)
   local unix = require('unix')
   local dir, err = unix.stat(path)
   if err then
      return false
   else
      return unix.S_ISDIR(dir.mode)
   end
end

utils.run_command = function(command_line)
   local cmdline = command_line .. "; echo $?"
   local pipe = io.popen(cmdline)

   local lines = {}
   for line in pipe:lines() do
      lines[#lines + 1] = line
   end

   local command_output = ""
   for i = 1, #lines - 1 do
      if i ~= 1 then
         command_output = command_output .. "\n"
      end
      command_output = command_output .. lines[i]
   end

   return tonumber(lines[#lines]), command_output
end

utils.get_logger = function(name, conf)
   conf = conf or {}

   local logger
   local log_level = string.lower(conf.LogLevel or "warn")
   local log_device = string.lower(conf.LogDevice or "syslog")

   if log_device == "stdout" or log_device == "console" then
      logger = require('logging.console')()
   else
      local logging = require('logging')
      require('logging.syslog')
      logger = logging.syslog(name)
   end
   if log_level == "debug" then
      logger:setLevel(logger.DEBUG)
   elseif log_level == "info" then
      logger:setLevel(logger.INFO)
   elseif log_level == "warn" or log_level == "warning"then
      logger:setLevel(logger.WARN)
   elseif log_level == "err" or log_level == "error" then
      logger:setLevel(logger.ERROR)
   elseif log_level == "fatal" then
      logger:setLevel(logger.FATAL)
   end

   return logger
end

return utils

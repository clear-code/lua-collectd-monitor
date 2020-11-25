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

return utils

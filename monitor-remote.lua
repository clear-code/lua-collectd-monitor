local inspect = require('inspect')
local mqtt = require('mqtt')

print("monitor-remote.lua: dump collectd")
print(inspect(collectd))

function config(conf)
   print("monitor-remote.lua: config")
   print(inspect(conf))
   return 0
end

function init()
   print("monitor-remote.lua: init")
   return 0
end

function read()
   print("monitor-remote.lua: read")
   return 0
end

function write(metrics)
   print("monitor-remote.lua: write")
   print(inspect(metrics))
   return 0
end

function shutdown()
   print("monitor-remote.lua: shutdown")
   return 0
end


collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_read(read)
collectd.register_write(write)

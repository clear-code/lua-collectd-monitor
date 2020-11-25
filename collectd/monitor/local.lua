local inspect = require('inspect')

print("monitor-local.lua: dump collectd")
print(inspect(collectd))

function config(conf)
   print("monitor-local.lua: config")
   print(inspect(conf))
   return 0
end

function init()
   print("monitor-local.lua: init")
   return 0
end

function read()
   print("monitor-local.lua: read")
   return 0
end

function write(metrics)
   print("monitor-local.lua: write")
   print(inspect(metrics))
   return 0
end

function shutdown()
   print("monitor-local.lua: shutdown")
   return 0
end


collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_read(read)
collectd.register_write(write)

function config(conf)
end

function init()
   return 0
end

function shutdown()
   return 0
end

function read()
   return 0
end

function write(metrics)
   return 0
end

collectd.register_config(config)
collectd.register_init(init)
collectd.register_shutdown(shutdown)
collectd.register_read(read)
collectd.register_write(write)

-- Example of recovery conditions for local.lua plugin

local metric_handlers = {
   memory_free_is_under_10GB = function(metric)
      -- Example of metric:
      -- {
      --    dsnames = {
      --       [0] = "value"
      --    },
      --    dstypes = {
      --       [0] = "gauge"
      --    },
      --    host = "localhost",
      --    interval = 10,
      --    plugin = "memory",
      --    plugin_instance = "",
      --    time = 1610019177.9849,
      --    type = "memory",
      --    type_instance = "free",
      --    values = { 954068992 }
      -- }
      --
      -- See also:
      -- * https://collectd.org/wiki/index.php/Value_list
      -- * https://collectd.org/wiki/index.php/Data_source
      -- * https://collectd.org/wiki/index.php/Naming_schema

      if metric.plugin == "memory" and metric.type_instance == "free" then
         if metric.values[1] <= 10 * 1000 * 1000 * 1000 then
            -- To execute a commend, return service & command name defined in
            -- config.json
            return { service = "hello", command = "exec" }
         end
      end

      -- return nil if no need to execute a command
      return nil
   end,

   memory_free_is_over_10GB = function(metric)
      if metric.plugin == "memory" and metric.type_instance == "free" then
         if metric.values[1] > 10 * 1000 * 1000 * 1000 then
            return { service = "hello", command = "exec" }
         end
      end
   end,
}

local notification_handlers = {
   fail_example = function(notification)
      -- Example of notification:
      -- {
      --    host = "localhost",
      --    message = "hello",
      --    plugin = "plugin1",
      --    plugin_instance = "0",
      --    severity = 4,
      --    time = 1610019901.000,
      --    type = "type1",
      --    type_instance = "0"
      -- }
      --
      -- severity:
      --   * 1: NOTIF_FAILURE
      --   * 2: NOTIF_WARING
      --   * 4: NOTIF_OKAY
      --
      -- See also:
      -- * https://collectd.org/wiki/index.php/Notification_t

      if notification.severity == NOTIF_FAILURE then
         -- To execute a commend, return service & command name defined in
         -- config.json
         return { service = "hello", command = "exec" }
      end

      -- return nil if no need to execute a command
      return nil
   end
}

-- Each config files can return 2 types of handlers
--
-- * 1st return value: metric_handlers (or a metric_handler)
--   * A function or a table of functions which are called when a collectd
--     plugin sends a metric
--   * Can be nil if you don't want to receive metrics
--
-- * 2nd return value: notification_handlers (or a notification_handler)
--   * A function or a table of functions which are called when a collectd
--     plugin sends a notification
--   * Can be nil if you don't want to receive notifications
return metric_handlers, notification_handlers

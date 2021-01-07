local write_callbacks = {
   free_is_under_10GB = function(metrics)
      if metrics.plugin == "memory" and metrics.type_instance == "free" then
         if metrics.values[1] <= 10 * 1000 * 1000 * 1000 then
            return { service = "hello", command = "exec" }
         end
      end
   end,

   free_is_over_10GB = function(metrics)
      if metrics.plugin == "memory" and metrics.type_instance == "free" then
         if metrics.values[1] > 10 * 1000 * 1000 * 1000 then
            return { service = "hello", command = "exec" }
         end
      end
   end,
}

local notification_callbacks = {
   fail_example = function(notification)
      if notification.severity == NOTIF_FAILURE then
         return { service = "hello", command = "exec" }
      end
   end
}

return write_callbacks, notification_callbacks

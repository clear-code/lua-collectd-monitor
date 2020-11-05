package = "collectd-monitor"
version = "0.0.1-1"
source = {
    url = "git://github.com/clear-code/lua-collectd-monitor.git"
}
description = {
    summary = "A collectd plugin to provide monitoring feature",
    detailed = [[A collectd plugin to provide monitoring feature]],
    homepage = "https://github.com/clear-code/collectd-monitor.lua",
    license = "MIT/X11",
    maintainer = "ashie@clear-code.com"
}
dependencies = {
    "lua >= 5.1",
    "inspect >= 3.1.1",
    "luamqtt >= 3.4.1",
    "cqueues >= 20200726.51",
}
build = {
    type = "builtin",
    modules = {
        ["collectd-monitor.remote"] = "monitor-remote.lua",
        ["collectd-monitor.local"] = "monitor-local.lua",
    },
}

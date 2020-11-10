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
    "luasec >= 0.9",
    "cqueues >= 20200726.51",
    "lunajson >= 1.2.3",
    "argparse >= 0.7.1",
    "luasyslog >= 1.0.0"
}
build = {
    type = "builtin",
    modules = {
        ["collectd-monitor.monitor-remote"] = "monitor-remote.lua",
        ["collectd-monitor.monitor-local"] = "monitor-local.lua",
        ["collectd-monitor.send-command"] = "send-command.lua",
    },
}

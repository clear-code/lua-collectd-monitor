package = "collectd-monitor"
version = "0.2.0-1"
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
    "luasyslog >= 1.0.0",
    "lunix >= 20170920",
    "penlight >= 1.8.0",
}
build = {
    type = "builtin",
    modules = {
        ["collectd.monitor.remote"] = "collectd/monitor/remote.lua",
        ["collectd.monitor.local"] = "collectd/monitor/local.lua",
        ["collectd.monitor.mqtt-thread"] = "collectd/monitor/mqtt-thread.lua",
        ["collectd.monitor.utils"] = "collectd/monitor/utils.lua",
        ["collectd.monitor.send-command"] = "collectd/monitor/send-command.lua",
        ["collectd.monitor.config-replacer"] = "collectd/monitor/config-replacer.lua",
        ["collectd.monitor.replace-config"] = "collectd/monitor/replace-config.lua",
        ["collectd.monitor.send-config"] = "collectd/monitor/send-config.lua",
    },
}

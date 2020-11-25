# lua-collectd-monitor

collectd plugins which provides fault recovery feature written in Lua.
We are planning to provide following 2 plugins:

* monitor-remote.lua
  * Receive pre-defined recovery commands from a remote host via MQTT and execute them.
  * This plugin itself doesn't have the feature to detect system faults.
  * It aims to detect system faults by another host which receives metrics data via collectd's network plugin, and send recovery commands from the host to this plugin.
* monitor-local.lua
  * Not implemented yet
  * It will provide features that detecting system faults according to metrics data collected by local collectd daemon, and executing recovery commands.

## Prerequisites

* Lua or LuaJIT
  * LuaJIT 2.1.0-beta3 is verified
* LuaRocks
* collectd
  * You need to install customized version of collectd:
    https://github.com/clear-code/collectd/tree/cc-5.12.0-20201124
  * Required additional callback functions are supported in this branch.
* MQTT Broker
  * [VerneMQ](https://vernemq.com/) is verified
  * At least 2 topics should be accessible
    * For sending commands from a server
    * For replying command results from collectd

## Install

* Download and install lua-collectd-monitor:
```shell
$ git clone https://github.com/clear-code/lua-collectd-monitor
$ sudo luarocks make
```
* Add settings like the following example to your collectd.conf (see conf/collectd-lua-debug.conf for more details)
```xml
<LoadPlugin lua>
  Globals true
</LoadPlugin>
<Plugin lua>
  BasePath "/usr/local/share/lua/5.1/collectd/monitor"
  Script "remote.lua"
  <Module "remote">
    MonitorConfigPath "/opt/collectd/etc/monitor-config.json"
  </Module>
</Plugin>
```
* Copy conf/monitor-config.json to /opt/collectd/etc/ and edit it to set connection settings to MQTT broker and define available recovery commands

## Testing remote command

* Start collectd daemon
* Execute send-command.lua like the following example:
  `$ luajit ./collectd/monitor/send-command.lua --user test-user --password test-user --topic test-topic --result-topic test-result-topic hello exec`
  * See `luajit ./collectd/monitor/send-command.lua --help` and its source code for more details

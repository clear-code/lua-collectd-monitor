# lua-collectd-monitor

A collectd plugin which provides monitoring feature.
We are planning to provide following 2 plugins:

* monitor-remote.lua
  * Receive a pre-defined command from a remote host via MQTT and execute it.
* monitor-local.lua
  * Not implemented yet

## Prerequisites

* You need to install customized version of collectd
  * https://github.com/clear-code/collectd/tree/cc-luajit
    * Required additional callback functions are supported in `cc-luajit` branch.
* Lua or LuaJIT
  * LuaJIT 2.1.0-beta3 is verified
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
  BasePath "/usr/local/share/lua/5.1/collectd/"
  Script "monitor-remote.lua"
  <Module "monitor-remote">
    Host "localhost"
    User "test-user"
    Password "test-user"
    CommandTopic "command-topic"
    CommandResultTopic "result-topic"
    MonitorConfigPath "/opt/collectd/etc/monitor-config.json"
  </Module>
</Plugin>
```
* Copy conf/monitor-config.json to /opt/collectd/etc/ and edit it to define available commands

## Testing remote command

* Start collectd daemon
* Execute send-command.lua like the following example:
  `$ luajit ./send-command.lua --user test-user --password test-user --topic command-topic hello`

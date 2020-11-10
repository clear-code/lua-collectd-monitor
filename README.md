# lua-collectd-monitor

A collectd plugin written in Lua, it provides monitoring feature.

## Install

* At first, you need to install customized version of collectd
  * https://github.com/clear-code/collectd/tree/cc-luajit
* Download and install lua-collectd-monitor:
```shell
$ git clone https://github.com/clear-code/lua-collectd-monitor
$ sudo luarocks make
```
* Add the following config to your collectd.conf
```xml
<LoadPlugin lua>
  Globals true
</LoadPlugin>
<Plugin lua>
  BasePath "/usr/local/share/lua/5.1/collectd-monitor/"
  Script "monitor-remote.lua"
    <Module "monitor-remote">
      Host "localhost"
      User "test-user"
      Password "test-user"
      Secure false
      CleanSession true
      QoS 0
      CommandTopic "test-topic"
      LogLevel "debug"
  </Module>
</Plugin>
```

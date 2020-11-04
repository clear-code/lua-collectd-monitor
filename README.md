# lua-collectd-monitor

A collectd plugin written in Lua, it provides monitoring feature.

## Install

* At first, you need to install customized version of collectd
  * https://github.com/clear-code/collectd/tree/cc-luajit
* Download and install lua-collectd-monitor:
```
$ git clone https://github.com/clear-code/lua-collectd-monitor
$ sudo luarocks make
```
* Add the following config to your collectd.conf
```
<LoadPlugin lua>
  Globals true
</LoadPlugin>
<Plugin lua>
  BasePath "/usr/local/share/lua/5.1/collectd-monitor/"
  Script "remote.lua"
  Script "local.lua"
</Plugin>
```

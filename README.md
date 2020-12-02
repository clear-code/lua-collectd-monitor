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
```console
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
* Execute send-command.lua like the following example. It will sends command and receive a command result:
```console
$ luajit /usr/local/share/lua/5.1/collectd/monitor/send-command.lua \
  hello \
  exec \
  --host 192.168.55.1 \
  --user test-user \
  --password test-user \
  --topic test-topic \
  --result-topic test-result-topic
Send command: {"timestamp":"2020-11-26T00:41:19Z","service":"hello","task_id":3126260400,"command":"exec"}
{ -- PUBREC{type=5, packet_id=2}
  packet_id = 2,
  type = 5,
  <metatable> = {
    __tostring = <function 1>
  }
}
Received a result: { -- PUBLISH{qos=2, packet_id=1, dup=false, type=3, payload="{\\"timestamp\\":\\"2020-11-26T00:41:19Z\\",\\"message\\":\\"Hello World!\\",\\"task_id\\":3126260400,\\"code\\":0}", topic="test-result-topic", retain=false}
  dup = false,
  packet_id = 1,
  payload = '{"timestamp":"2020-11-26T00:41:19Z","message":"Hello World!","task_id":3126260400,"code":0}',
  qos = 2,
  retain = false,
  topic = "test-result-topic",
  type = 3,
  <metatable> = {
    __tostring = <function 1>
  }
}
```
* See `luajit ./collectd/monitor/send-command.lua --help` and its source code for more details

## Message format of remote command

Remote command & command result messages are formated in JSON.
Here is the example and member definitions of these messages:

### Command message:

An example:

```json
{
  "task_id": 3126260400,
  "timestamp": "2020-11-26T00:41:19Z",
  "service": "hello",
  "command": "exec"
}
```

Members:

|   Field    |  Type  | Content |
|------------|--------|---------|
| task_id    | number | An unique task ID assigned by a command sender |
| timestamp  | string | Timestamp of a command (ISO8601 UTC) |
| service    | string | A service name defined in monitor-config.json |
| command    | string | A command name defined in monitor-config.json |

### Command result message:

An example:

```json
{
  "task_id":3126260400,
  "timestamp": "2020-11-26T00:41:19Z",
  "message": "Hello World!",
  "code": 0
}
```

Members:

|   Field    |  Type  | Content |
|------------|--------|---------|
| task_id    | number | An unique task ID assigned by a command sender |
| timestamp  | string | Timestamp of a command result (ISO8601 UTC) |
| message    | string | Message of a command (STDOUT) |
| code       | number | Exit status of a command |

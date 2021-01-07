# lua-collectd-monitor

collectd plugins which provides fault recovery feature written in Lua.
Following 2 plugins are included:

* collectd/monitor/remote.lua
  * Receives pre-defined recovery commands from a remote host via MQTT and execute them. In addition it can replace collectd's config file with a new config received via MQTT.
  * This plugin itself doesn't have the feature to detect system faults.
  * It aims to detect system faults by another host which receives metrics data via collectd's network plugin, and send recovery commands from the host to this plugin.
* collectd/monitor/local.lua
  * Detects system faults according to metrics data collected by local collectd daemon and executes recovery commands. Trigger conditions are written in Lua code.

## Prerequisites

* Lua or LuaJIT
  * LuaJIT 2.1.0-beta3 is verified
* LuaRocks
* collectd
  * You need to install customized version of collectd:
    https://github.com/clear-code/collectd/tree/cc-5.12.0-20210107
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
* Add settings like the following example to your collectd.conf (see [conf/collectd/collectd.conf.monitor-remote-example](conf/collectd/collectd.conf.monitor-remote-example) for more options of remote monitoring feature):
```xml
<LoadPlugin lua>
  Globals true
</LoadPlugin>

<Plugin lua>
  BasePath "/usr/local/share/lua/5.1"

  # Use remote monitoring feature.
  Script "collectd/monitor/remote.lua"
  <Module "collectd/monitor/remote">
    MonitorConfigPath "/etc/collectd/monitor/config.json"
  </Module>

  # Use local monitoring feature.
  Script "collectd/monitor/local.lua"
  <Module "collectd/monitor/local">
    MonitorConfigPath "/etc/collectd/monitor/config.json"
    LocalMonitorConfigDir "/etc/collectd/monitor/local/"
  </Module>
</Plugin>
```
* Copy [conf/collectd/monitor/config.json](conf/collectd/monitor/config.json) to /etc/collectd/monitor/config.json and edit it to set connection settings to MQTT broker (if you use remote monitoring feature) and define available recovery commands.
* If you use local monitoring feature, put additional config files written in Lua to /etc/collectd/monitor/local/ with the extension ".lua". See [conf/collectd/monitor/local/example.lua](conf/collectd/monitor/local/example.lua) for examples.

## Remote command feature

### Steps to test remote command feature

* Enable collectd/monitor/remote.lua in your collectd.conf
* Start collectd daemon
* Execute send-command.lua like the following example. It will send a command and receive a result:
```console
$ luajit /usr/local/share/lua/5.1/collectd/monitor/send-command.lua \
  hello \
  exec \
  --host 192.168.xxx.xxx \
  --user test-sender \
  --password test-sender \
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

### The message format of a remote command

Remote command & command result messages are formated in JSON.
Here is an example and member definitions of these messages:

#### Command message:

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
| service    | string | A service name defined in the config file specified by `MonitorConfigPath` |
| command    | string | A command name defined in the config file specified by `MonitorConfigPath` |

#### Command result message:

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


## Sending collectd.conf feature

### Steps to test sending collectd.conf feature

* Enable collectd/monitor/remote.lua in your collectd.conf
* Start collectd daemon
* Execute send-config.lua like the following example. It will send a config and receive a result:
```console
$ ./test-send-config.sh \
  path/to/new/collectd.conf \
  --host 192.168.xxx.xxx \
  --user test-sender \
  --password test-sender \
  --topic test-topic \
  --result-topic test-result-topic
Send config: {"timestamp":"2021-01-03T04:45:09Z","task_id":3689797623,"config":"LoadPlugin cpu\n<LoadPlugin lua>\n\tGlobals true\n</LoadPlugin>\n..."}
{ -- PUBREC{type=5, packet_id=2}
  packet_id = 2,
  type = 5,
  <metatable> = {
    __tostring = <function 1>
  }
}
Received a result: { -- PUBLISH{qos=2, packet_id=1, dup=false, type=3, payload="{\\"timestamp\\":\\"2021-01-03T04:45:09Z\\",\\"message\\":\\"Succeeded to replace config.\\",\\"task_id\\":3689797623,\\"code\\":0}", topic="test-result-topic", retain=false}
  dup = false,
  packet_id = 1,
  payload = '{"timestamp":"2021-01-03T04:45:09Z","message":"Succeeded to replace config.","task_id":3689797623,"code":0}',
  qos = 2,
  retain = false,
  topic = "test-result-topic",
  type = 3,
  <metatable> = {
    __tostring = <function 1>
  }
}
```
* See `luajit ./collectd/monitor/send-config.lua --help` and its source code for more details

### The message format of sending collectd.conf

Message to sending collectd.conf & results are formated in JSON.
Here is an example and member definitions of these messages:

#### A message to send collectd.conf

An example:

```json
{
  "task_id": 3126260401,
  "timestamp": "2020-12-26T00:41:19Z",
  "config": "<Plugin>\ncpu</Plugin>..."
}
```

Members:

|   Field    |  Type  | Content |
|------------|--------|---------|
| task_id    | number | An unique task ID assigned by a sender |
| timestamp  | string | Timestamp of a message (ISO8601 UTC) |
| config     | string | Content of new collectd.conf |

#### Result message of sending collectd.conf:

An example:

```json
{
  "task_id":3126260401,
  "timestamp": "2020-12-26T00:41:19Z",
  "message": "Succeeded to replace config.",
  "code": 0
}
```

Members:

|   Field    |  Type  | Content |
|------------|--------|---------|
| task_id    | number | An unique task ID assigned by a sender |
| timestamp  | string | Timestamp of a result (ISO8601 UTC) |
| message    | string | A result message |
| code       | number | A result code (See below) |

Here is the defined result codes:

|     Code      | Content |
|---------------|---------|
| 0             | Succeeded |
| 8192 (0x2000) | Another task is already running |
| 8193 (0x2001) | Failed to write new config |
| 8194 (0x2002) | New config is broken |
| 8195 (0x2003) | Cannot stop collectd |
| 8196 (0x2004) | pid file of collectd isn't removed |
| 8197 (0x2005) | Failed to backup old collectd.conf |
| 8198 (0x2006) | Failed to replace collectd.conf |
| 8199 (0x2007) | Recovered by the old collectd.conf due to failing restart |
| 8200 (0x2008) | Failed to restart and failed to recover by the old collect.conf |
| 8201 (0x2009) | Cannot get new pid |

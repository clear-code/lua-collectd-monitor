# lua-collectd-monitor

障害復旧機能を提供するcollectdプラグインです。Luaで実装されています。
以下の2つのプラグインが含まれています。

* collectd/monitor/remote.lua
  * 予め定義したリカバリコマンドをリモートホストからMQTT経由で受け取って実行するプラグインです。また、MQTTで新しいcollectd.confを受け取りcollectdに適用する機能も持ちます。
  * このプラグイン自体は障害を検知する機能を持ちません。
  * collectdで収集した監視データをnetworkプラグインで別ホストに転送し、同ホスト側の別ソフトウェアで障害を検知の上、復旧コマンドを本プラグインに送信する使い方を想定しています。
* collectd/monitor/local.lua
  * ローカルのcollectdで収集したメトリクスデータを用いて復旧条件を判定し、リカバリコマンドを実行するプラグインです。復旧条件はLuaのコードで記述します。


## 必要なもの

* Lua or LuaJIT
  * LuaJIT 2.1.0-beta3で動作確認しています。
* LuaRocks
* collectd
  * 以下のカスタマイズ版のcollectdを使用する必要があります:
    https://github.com/clear-code/collectd/tree/cc-5.12.0-20210107
  * 上記ブランチでは本プラグインで必要な追加のコールバック関数が実装されています。
* MQTTブローカー
  * [VerneMQ](https://vernemq.com/)で動作確認されています。
  * 少なくとも以下の2つのトピックにアクセス可能である必要があります。
    * 別ホスト側からコマンドを送信するためのトピック
    * 別ホスト側にコマンド実行結果を送信するためのトピック


## インストール

* lua-collectd-monitorをダウンロードしてインストールする:
```console
$ git clone https://github.com/clear-code/lua-collectd-monitor
$ sudo luarocks make
```
* collectd.confに以下のような設定を追加する（リモート監視機能のより詳細な設定項目については[conf/collectd/collectd.conf.monitor-remote-example](conf/collectd/collectd.conf.monitor-remote-example)を参照）:
```xml
<LoadPlugin lua>
  Globals true
</LoadPlugin>

<Plugin lua>
  BasePath "/usr/local/share/lua/5.1"

  # リモート監視機能を使用する場合
  Script "collectd/monitor/remote.lua"
  <Module "collectd/monitor/remote.lua">
    MonitorConfigPath "/etc/collectd/monitor/config.json"
  </Module>

  # ローカル監視機能を使用する場合
  Script "collectd/monitor/local.lua"
  <Module "collectd/monitor/local">
    MonitorConfigPath "/etc/collectd/monitor/config.json"
    LocalMonitorConfigDir "/etc/collectd/monitor/local/"
  </Module>
</Plugin>
```
* /etc/collectd/monitor/config.jsonで必要なリカバリコマンドとMQTTブローカーへの接続情報（リモート監視機能を使用する場合）を設定する
  * [conf/collectd/monitor/config.json](conf/collectd/monitor/config.json)を/etc/collectd/monitor/config.jsonにコピーする
  * 認証情報を含む場合があるため、アクセス権を所有者のみにする
    `chmod 600 /etc/collectd/monitor/config.json`
  * 内容を編集して必要なリカバリコマンドや接続情報を設定する
* ローカル監視機能を使用する場合は、Luaで書かれた設定ファイルを任意のファイル名 + 拡張子「.lua」で/etc/collectd/monitor/local/以下に配置する。設定例については[conf/collectd/monitor/local/example.lua](conf/collectd/monitor/local/example.lua)を参照。


## リモートコマンド機能

### リモートコマンドのテスト手順

* collectd.confでcollectd/monitor/remote.luaを有効化する
* collectdデーモンを起動する
* 以下の例の様にsend-command.luaを実行するとコマンドが送付され、その実行結果を得ることができる。
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
* 詳細については`luajit ./collectd/monitor/send-command.lua --help`やソースコードを参照のこと

### config.jsonの設定項目

設定例は[conf/collectd/monitor/config.json](conf/collectd/monitor/config.json)を参照して下さい。

|        キー        | タイプ | 内容 |
|--------------------|--------|------|
| Host               | 文字列 | MQTTブローカーのホスト名およびポート (例: `host` あるいは `host:1883`) |
| User               | 文字列 | MQTTブローカーでの認証用ユーザー名 |
| Password           | 文字列 | MQTTブローカーでの認証用パスワード |
| Secure             | 真偽値 | MQTTブローカーへの接続でTLSを使用するか否か |
| CleanSession       | 真偽値 | MQTTの[Clean Sessionフラグ](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/errata01/os/mqtt-v3.1.1-errata01-os-complete.html#_Ref362965194) |
| QoS                | 数値   | MQTTの[QoSレベル](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/errata01/os/mqtt-v3.1.1-errata01-os-complete.html#_Toc442180912) |
| CommandTopic       | 文字列 | コマンド送受信用のMQTTトピック名 |
| CommandResultTopic | 文字列 | コマンド結果送受信用のMQTTトピック名 |
| Services           | オブジェクト | 障害復旧コマンドを設定するサービスのリスト（後述） |
| LogDevice          | 文字列 | ログ出力先 (`stdout`あるいは`syslog`) |
| LogLevel           | 文字列 | ログレベル (`fatal`, `error`, `warn`, `info`, `debug`) |

`Services`の各キーは任意のサービス名、値は以下のオブジェクトです:

|   キー   |    タイプ    | 内容 |
|----------|--------------|------|
| Commands | オブジェクト | 復旧コマンドのリスト: 各キーは任意のコマンド名、値は復旧用のコマンド |

### リモートコマンドのメッセージ形式

リモートコマンドおよび実行結果のメッセージ形式はJSONです。
それぞれのメッセージ例とメンバー定義を以下に示します。

#### コマンドメッセージ

メッセージ例:

```json
{
  "task_id": 3126260400,
  "timestamp": "2020-11-26T00:41:19Z",
  "service": "hello",
  "command": "exec"
}
```

メンバー:

| フィールド | タイプ | 内容 |
|------------|--------|------|
| task_id    | 数値   | コマンド送信者によって割り振られる一意のタスクID |
| timestamp  | 文字列 | コマンドのタイムスタンプ（ISO8601形式UTC）|
| service    | 文字列 | `MonitorConfigPath`で指定した設定ファイルで定義されているサービス名 |
| command    | 文字列 | `MonitorConfigPath`で指定した設定ファイルで定義されているコマンド名 |

#### コマンド結果メッセージ

メッセージ例:

```json
{
  "task_id":3126260400,
  "timestamp": "2020-11-26T00:41:19Z",
  "message": "Hello World!",
  "code": 0
}
```

メンバー:

| フィールド | タイプ | 内容 |
|------------|--------|------|
| task_id    | 数値   | コマンド送信者によって割り振られる一意のタスクID |
| timestamp  | 文字列 | コマンド結果のタイムスタンプ（ISO8601形式UTC）|
| message    | 文字列 | コマンドのメッセージ（標準出力） |
| code       | 数値   | コマンドの終了ステータス |


## collectd.confリモート更新機能

### collectd.confリモート更新機能のテスト手順

* collectd.confでcollectd/monitor/remote.luaを有効化する
* collectdデーモンを起動する
* 以下の例の様にsend-config.luaを実行すると設定が送付され、その実行結果を得ることができる。
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
* 詳細については`luajit ./collectd/monitor/send-config.lua --help`やソースコードを参照のこと

### collectd.confリモート更新機能のメッセージ形式

collectd.conf送信および実行結果のメッセージ形式はJSONです。
それぞれのメッセージ例とメンバー定義を以下に示します。

#### collectd.conf更新メッセージ

メッセージ例:

```json
{
  "task_id": 3126260401,
  "timestamp": "2020-12-26T00:41:19Z",
  "config": "<Plugin>\ncpu</Plugin>"
}
```

メンバー:

| フィールド | タイプ | 内容 |
|------------|--------|------|
| task_id    | 数値   | 送信者によって割り振られる一意のタスクID |
| timestamp  | 文字列 | タイムスタンプ（ISO8601形式UTC）|
| config     | 文字列 | 新しいcollectd.confの内容 |

#### collectd.conf更新実行結果メッセージ

メッセージ例:

```json
{
  "task_id":3126260401,
  "timestamp": "2020-12-26T00:41:19Z",
  "message": "Succeeded to replace config.",
  "code": 0
}
```

メンバー:

| フィールド | タイプ | 内容 |
|------------|--------|------|
| task_id    | 数値   | 送信者によって割り振られる一意のタスクID |
| timestamp  | 文字列 | 実行結果のタイムスタンプ（ISO8601形式UTC）|
| message    | 文字列 | 実行結果のメッセージ |
| code       | 数値   | 実行結果の終了コード（後述） |

実行結果の終了コードは以下の通りです。

|    コード     | 内容 |
|---------------|------|
| 0             | 成功 |
| 8192 (0x2000) | 別の更新処理が実行中 |
| 8193 (0x2001) | 新しい設定の書き込みに失敗 |
| 8194 (0x2002) | 設定が壊れている |
| 8195 (0x2003) | collectdを終了できない |
| 8196 (0x2004) | collectdのpidファイルが削除されない |
| 8197 (0x2005) | 設定ファイルのバックアップに失敗 |
| 8198 (0x2006) | 設定ファイルの置き換えに失敗 |
| 8199 (0x2007) | 再起動に失敗したため古いcollectd.confでリカバリされた |
| 8200 (0x2008) | 再起動に失敗し古いcollectd.confでのリカバリにも失敗した |
| 8201 (0x2009) | 新しいプロセスIDの取得に失敗した |


## ローカル監視機能

### ローカル監視機能のテスト手順

* collecd.confとして[conf/collectd/collectd.conf.monitor-local-example](conf/collectd/collectd.conf.monitor-local-example)を使用する
* [conf/collectd/monitor/config.json](conf/collectd/monitor/config.json)を/etc/collectd/monitor/config.jsonにコピーする
  * 上記ファイルに定義された復旧コマンドを確認し、必要に応じて編集する。
* [conf/collectd/monitor/local/example.lua](conf/collectd/monitor/local/example.lua)を/etc/collectd/monitor/local/にコピーする
  * 上記ファイルのコマンド実行条件を確認し、必要に応じて編集する。
* collectdデーモンを起動する
* syslogを確認し、以下のようなNotificationが発行されていることを確認する
```
Notification: severity = OKAY, host = local, plugin = lua-collectd-monitor-local, type = /etc/collectd/monitor/local/example.lua::write::memory_free_is_under_10GB, message = {"message":"Hello World!","task_id":244078840,"code":0}
```

### 復旧コマンドおよび復旧条件の設定

* 復旧コマンドはリモートコマンド機能と同様にconfig.jsonで予め定義します。記述例は[conf/collectd/monitor/config.json](conf/collectd/monitor/config.json)を参照して下さい。
* 復旧条件はLuaのコードで記述します。記述例は[conf/collectd/monitor/local/example.lua](conf/collectd/monitor/local/example.lua)を参照して下さい。

### コマンド実行結果の通知

コマンドの実行結果は上記実行例の通りcollectdの[Notification](https://collectd.org/wiki/index.php/Notification_t)機能で通知されます。collectdのnetworkプラグインを使用することで、リモートホストでも実行結果を受け取ることができます。

Notificationの各フィールドの値は次の通りです。

|   フィールド    | 内容 |
|-----------------|------|
| severity        | 4 (NOTIF_OKAY): 成功, 1 (NOTIF_FAILURE): 失敗 |
| host            | ホスト名 |
| plugin          | lua-collectd-moitor-local （固定） |
| plugin_instance | 無し（空文字列） |
| type            | 復旧コマンドを実行したコールバック名 |
| type_instance   | 無し（空文字列） |
| time            | タイムスタンプ（UNIX時間） |
| message         | 実行結果の詳細（JSON形式） |

`message`の内容は以下の通りです。

| フィールド | タイプ | 内容 |
|------------|--------|------|
| task_id    | 数値   | 一意のタスクID |
| message    | 文字列 | コマンドのメッセージ（標準出力） |
| code       | 数値   | コマンドの終了ステータス |

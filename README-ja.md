# lua-collectd-monitor

障害復旧機能を提供するcollectdプラグインです。Luaで実装されています。
以下の2つのプラグインを提供します。

* collectd/monitor/remote.lua
  * 予め定義したリカバリコマンドをリモートホストからMQTT経由で受け取って実行するプラグインです。また、MQTTで新しいcollectd.confを受け取りcollectdに適用する機能も持ちます。
  * このプラグイン自体は障害を検知する機能を持ちません。
  * collectdで収集した監視データをnetworkプラグインで別ホストに転送し、同ホスト側の別ソフトウェアで障害を検知の上、復旧コマンドを本プラグインに送信する使い方を想定しています。
* collectd/monitor/local.lua
  * まだ実装されていません。
  * ローカルのcollectdで収集したメトリクスデータを用いて復旧条件を判定しリカバリコマンドを実行する機能を提供予定です。

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
* collectd.confに以下のような設定を追加する（より詳細な設定項目については[conf/collectd-monitor-remote-example.conf](conf/collectd-monitor-remote-example.conf)を参照）:
```xml
<LoadPlugin lua>
  Globals true
</LoadPlugin>
<Plugin lua>
  BasePath "/usr/local/share/lua/5.1"
  Script "collectd/monitor/remote.lua"
  <Module "collectd/monitor/remote">
    MonitorConfigPath "/etc/collectd-monitor-config.json"
  </Module>
</Plugin>
```
* [conf/monitor-config.json](conf/monitor-config.json)を/etc/collectd-monitor-config.jsonにコピーし、内容を編集してMQTTブローカーへの接続情報と必要なリカバリコマンドを設定する

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
| service    | 文字列 | monitor-config.jsonで定義されているサービス名 |
| command    | 文字列 | monitor-config.jsonで定義されているコマンド名 |

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


## collectd設定更新機能

### collectd設定更新機能のテスト手順

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

### collectd設定送信機能のメッセージ形式

collectd設定送信および実行結果のメッセージ形式はJSONです。
それぞれのメッセージ例とメンバー定義を以下に示します。

#### collectd設定更新メッセージ

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

#### 設定更新実行結果メッセージ

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

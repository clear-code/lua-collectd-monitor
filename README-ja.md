# lua-collectd-monitor

障害復旧機能を提供するcollectdプラグインです。Luaで実装されています。
以下の2つのプラグインを提供予定です。

* monitor-remote.lua
  * 予め定義したリカバリコマンドをリモートホストからMQTT経由で受け取って実行するプラグインです。
  * このプラグイン自体は障害を検知する機能は持ちません。
  * collectdで収集したメトリクスデータをnetworkプラグインで別ホストに転送し、同ホスト側の別ソフトウェアで障害を検知の上、復旧コマンドを本プラグインに送信する使い方を想定しています。
* monitor-local.lua
  * まだ実装されていません。
  * ローカルのcollectdで収集したメトリクスデータを用いて復旧条件を判定しリカバリコマンドを実行する機能を提供予定です。

## 必要なもの

* Lua or LuaJIT
  * LuaJIT 2.1.0-beta3で動作確認しています。
* LuaRocks
* collectd
  * 以下のカスタマイズ版のcollectdを使用する必要があります:
    https://github.com/clear-code/collectd/tree/cc-luajit
  * 上記の`cc-luajit`ブランチでは本プラグインで必要な追加のコールバック関数が実装されています。
* MQTTブローカー
  * [VerneMQ](https://vernemq.com/)で動作確認されています。
  * 少なくとも以下の2つのトピックにアクセス可能である必要があります。
    * 別ホスト側からコマンドを送信するためのトピック
    * 別ホスト側にコマンド実行結果を送信するためのトピック

## インストール

* lua-collectd-monitorをダウンロードしてインストールする:
```shell
$ git clone https://github.com/clear-code/lua-collectd-monitor
$ sudo luarocks make
```
* collectd.confに以下のような設定を追加する（より詳細な設定項目についてはconf/collectd-lua-debug.confを参照）:
```xml
<LoadPlugin lua>
  Globals true
</LoadPlugin>
<Plugin lua>
  BasePath "/usr/local/share/lua/5.1/collectd/"
  Script "monitor-remote.lua"
  <Module "monitor-remote">
    MonitorConfigPath "/opt/collectd/etc/monitor-config.json"
  </Module>
</Plugin>
```
* conf/monitor-config.jsonを/opt/collectd/etc/にコピーし、内容を編集してMQTTブローカーへの接続情報と必要なリカバリコマンドを設定する

## リモートコマンドのテスト

* collectdデーモンを起動する
* 以下の例の様にsend-command.luaを実行する:
  `$ luajit ./send-command.lua --user test-user --password test-user --topic command-topic hello exec`
  * 詳細については`luajit ./send-command.lua --help`やソースコードを参照

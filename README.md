# DCS Dynamic Training Syria

DCS World / Syria / MOOSE を使用する動的訓練ミッションです。
設計方針と開発ルールは [AGENTS.md](AGENTS.md) を参照してください。

## 機能別仕様書

- [BVR 訓練ミッション仕様](docs/BVR.md): 開始条件、生成・経路計算、状態、制約、将来仕様、動作確認項目。

## BVR の自動検証

リポジトリのルートから Lua 5.1 で実行します。DCS の `bin/luae.exe` も使用できます。
DCS / MOOSE の呼び出し先を模擬し、生成のタイミング・予約・配置・経路を検証します。
ゲーム内での動作確認は別途必要です。

```text
lua scripts/Test-BVR.lua
```

## Lua のミッションへの反映

`src/DynamicTraining.lua` と `vendor/MOOSE/Moose.lua` が編集元です。
次のコマンドで、`mission/Syria.miz` 内の対応する埋め込み Lua を同期します。
Windows PowerShell 5.1 の標準機能のみで動作します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1
```

自分で Lua を編集する間は、次の監視コマンドを起動しておくと、保存後に自動同期します。
最初に一度同期し、その後は約2秒間隔で Lua と `.miz` の変更を検出します。
終了は Ctrl+C です。VS Code の「ターミナル → タスクの実行」から
`DCS: Watch mission Lua` を選んでも起動できます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -Watch
```

同期確認だけを行う場合は `-Check` を指定します。不一致時は失敗として終了します。
別のミッションコピーを同期する場合は `-MissionPath <path>` を指定します。

更新前に全 ZIP エントリの内容を記録し、更新後に対象 Lua の一致とその他の内容の保持を検証します。
検証後にファイルを置き換え、直前の `.miz` を `mission/Syria.miz.bak` に保存します。
内容が一致していれば書き込みません。バックアップと作業用ファイルは Git 管理対象外です。

ME で既に開いているミッションには古い埋め込み Lua が残るため、同期後は `.miz` を開き直してから実行してください。
開いたまま ME で上書き保存した場合も、監視中なら再同期します。
既に実行中の DCS ミッションには反映されないため、更新した `.miz` でミッションを再開始してください。

同期できるのは ME に登録済みの2つの Lua です。新しい Lua モジュールの読み込みを追加する際は、
ME で `DO SCRIPT FILE` と読み込み順を設定し、`scripts/Sync-Mission.ps1` の対応表を更新してください。
ミッション設定・トリガー・テンプレート名・リソース対応表は同期処理で変更しません。

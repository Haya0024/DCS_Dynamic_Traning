# DCS Dynamic Training Syria

DCS World / Syria / MOOSE を使用する動的訓練ミッションです。
設計方針と開発ルールは [AGENTS.md](AGENTS.md) を参照してください。

## 機能別仕様書

- [Intercept 訓練ミッション仕様](docs/Intercept.md): 開始条件、生成・経路計算、状態、制約、将来仕様、動作確認項目。
- [SEAD 訓練ミッション仕様](docs/SEAD.md): SA-6 / SA-8、4 Zone、配置条件、レーダー状態遷移、帰還採点・サイト管理。
- [プレイヤー採点・帰還評価仕様](docs/SCORING.md): UCID、帰還成功100%・クリア後の墜落/死亡/脱出60%、重複防止、保存方針。メモリ内の試用実装済み。
- [ウィング共有任務仕様](docs/WING.md): MP2 の共有目標、個別帰還・採点、全員離陸待ち、二重受注ブロック、中止操作。
- [テスト仕様書](docs/TESTING.md): 自動テスト全ケースの条件・期待結果、実行方法、DCS内の確認手順、結果記録。

## マルチプレイで採点を試す

同期済みの `mission/Syria.miz` をマルチプレイでホストし、BLUE Hornet の Client スロットに入ります。
F10 の `Dynamic Training` は各プレイヤーグループに表示され、`Generate Intercept`、`Mission Status`、
`Abort Mission`、`Player Statistics` を使用できます。任務はウィングごとに同時に1件で、別ウィングは並行して受注できます。

MP2 は2人とも搭乗してから、どちらかが `Generate Intercept` を選びます。受注時の搭乗者を参加者として固定し、
全員が空中なら即開始、地上にいる参加者がいれば全員の離陸検出から20秒後に敵を生成します。
目標達成は編隊で共有し、報酬は各自150ポイント。帰還失敗した人だけ90ポイントになります。
先に1人が精算してもウィングの受注ロックは維持し、全員の精算または中止まで次の任務を受注できません。
`Abort Sortie: <名前> [<機体>]` は個人中止、`Abort Mission` は編隊全体の中止です。
各ウィングの敵・離陸待ち・帰還評価・中止は独立し、別ウィングの任務を終了させません。

敵編成は MiG-29A ×2、Su-27 ×1、MiG-29A ×1 の3種類から、生成ごとに各1/3の確率で選びます。
候補は `src/config.lua` の `intercept.templates` に設定します。開始表示と全滅判定は実際の機種・機数に合わせます。

敵全滅後、BLUE 飛行場または空母に着陸し、5 knots以下を連続10秒維持すると150ポイントを加算します。
空母では艦との相対速度を使います。クリア後の墜落・死亡・脱出は90ポイント、未クリアの事故・任意 Abort は0ポイントです。
満額・距離・高度・判定時間などの設定は `src/config.lua` にあります。

UCID はサーバーの接続情報と Client スロットを照合して取得します。取得できない場合は採点なしと表示し、訓練は継続します。
同じグループの複数の人間に対応します。途中参加者は次の任務から登録します。動的 Client スロットは今回の試用対象外です。
ポイントはメモリ内だけに保持し、ミッション再開始・サーバー再起動でリセットします。
DCS 本体・Saved Games の設定変更や Hook の配置は今回必要ありません。
名称変更前の任務は、ユーザーからゲーム内で動作しているとの報告があります。名称変更後の表示は再確認してください。

## SEAD を試す

SEAD は受注時に TOO / PB を各50%で抽選します。TOOは実配置予定点から3～5 NMずらした捜索座標を知らせ、SAM機種・正確な座標・PBコードを隠します。
PBはSAM種類、実配置予定点から1～3 NMずらした推定座標、HARM PBコード（SA-6:108、SA-8:117）を表示します。
受注時の長機位置からZone中心まで40～130 NMの候補から1つ選び、LAND・半径200 mの標高差20 m以内・各車両と建物の離隔200 mを確認します。
選択Zone内を最大50回、1秒ごとに最大2候補ずつ検査し、条件を満たさなければ任務を解除します。失敗時は拒否理由ごとの件数を画面とログへ表示します。
計画と生成を分離し、地上受注なら全登録者の離陸後20秒で生成します。全員が空中で受注した場合は計画確定後に生成します。
計画確定後の地点・機種・方式・コードは変えません。生成直前に予定点が塞がった場合も別地点へ変更せず失敗解除します。
`Mission Status` でも方式に応じた受注情報を表示します。
SA-6 は主要レーダー `Kub 1S91 str`、SA-8 はレーダー一体の `Osa 9A33 ln` を対象とします。
破壊は即達成、生存中は生成時のLifeより減少し、Radar OFFが連続60秒続くとSuppressedとして達成します。再発信すると計測をリセットします。
`Mission Status` でエミッターの4状態を確認できます。完了後は再判定を止め、残存SAMを全参加者の終了まで保持します。
削除は独立したサイト管理が担い、失敗時は再試行します。DEADへの継続任務は未実装です。
発射機を残しても達成できます。帰還成功で各自150ポイント、達成後の墜落・死亡・脱出で90ポイントを加算します。
満額は `src/config.lua` の `sead.fullReward` で設定し、成績の `SEAD Score` に別途記録します。
同じウィングでは Intercept と SEAD を同時に受注できず、全参加者の精算・中止までロックを維持します。
レーダー状態遷移・完了後のサイト管理と採点の DCS 内での確認は未実施です。

## 自動検証

スイートと各ケースの検証範囲・期待結果、DCS内での手動確認は [テスト仕様書](docs/TESTING.md) にまとめています。

リポジトリのルートから Lua 5.1 で実行します。DCS の `bin/luae.exe` も使用できます。
DCS / MOOSE の呼び出し先を模擬し、生成のタイミング・予約・配置・経路・UCID・採点・着陸確認を検証します。
ゲーム内での動作確認は別途必要です。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-Mission.ps1
```

```text
lua scripts/Test-Intercept.lua
lua scripts/Test-Scoring.lua
lua scripts/Test-Wing.lua
lua scripts/Test-ParallelWings.lua
lua scripts/Test-SEAD.lua
```

同期ツールは `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-MissionSync.ps1` で検証します。
モジュール結合・設定ファイル変更の自動同期は `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-MissionBuild.ps1` で検証します。

## Lua のミッションへの反映

`src/*.lua` と `vendor/MOOSE/Moose.lua` が編集元です。
同期時に `scripts/Build-Mission.ps1` がモジュールと実行部分を `build/DynamicTraining.lua` に結合し、
既存の埋め込み `DynamicTraining.lua` を置き換えます。生成物は直接編集しません。
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

同期できるのは ME に登録済みの2つの Lua です。現在のモジュール分割は結合方式なので ME の追加設定は不要です。
新しいモジュールを結合する場合は `scripts/Build-Mission.ps1` の結合順を更新します。
別の埋め込み Lua として登録する場合は ME で `DO SCRIPT FILE` と読み込み順を設定し、同期ツールの対応表を更新します。
ミッション設定・トリガー・テンプレート名・リソース対応表は同期処理で変更しません。

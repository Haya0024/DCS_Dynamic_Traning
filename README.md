# Persistent and Dynamic F/A-18C Training

DCS World の Syria マップで、F/A-18C の迎撃・戦闘空中哨戒・防空制圧・防空サイト破壊を繰り返し練習するための動的訓練ミッションです。
F10から任務を受注し、任務ごとの条件で敵を配置します。目標達成後は味方基地や空母への帰還まで評価します。

ソロ、AI僚機との編隊、2人のマルチプレイに対応しています。出撃場所と兵装を選び、短い迎撃訓練から、SEAD後に再武装してDEADへ向かう連続出撃まで、自分たちのペースで訓練できます。

## 訓練できること

| 任務 | 内容 | 目標達成条件 |
|---|---|---|
| **Intercept — 迎撃** | ランダムな敵編成・方位・高度・フォーメーションに対する空対空戦闘 | 生成された敵航空機をすべて撃墜 |
| **CAP — 戦闘空中哨戒** | 指定空域を哨戒し、途中で出現する敵戦闘機と交戦 | 空域内の累計120秒と生成された敵航空機の全滅の両方 |
| **SEAD — 防空制圧** | TOO / PBでSA-6またはSA-8のレーダーを捜索・攻撃 | 主要レーダーを破壊、または損傷させて連続60秒間レーダー停止 |
| **DEAD — 防空サイト破壊** | SEADで制圧したサイトに残る車両への継続攻撃 | DEAD開始時に生存していた対象車両をすべて破壊 |

InterceptではMiG-29A ×2、Su-27 ×1、MiG-29A ×1のいずれかが、編隊リーダー機から60～80 NM、機首方向の左右60°以内に生成されます。高度や編隊も毎回変わります。

CAPではMEの4候補空域から1つを選び、空域内の哨戒時間と敵機全滅を評価します。敵はInterceptと同じ3編成から選ばれます。進め方は後述の「CAPの進め方」を参照してください。

SEADでは受注時にTOO / PBを等確率で選びます。TOOは機種不明の捜索座標、PBはSAM機種・推定座標・HARM PBコードを知らせます。
座標はDDM（度＋分の小数3桁）で表示し、実際の配置位置からTOOは3～5 NM、PBは1～3 NMの誤差を持たせます。HARM以外の武器で主要レーダーを破壊しても達成です。

## 始め方

必要な環境は **DCS World / Syriaマップ / F/A-18C** です。MOOSEと訓練スクリプトはミッションに組み込まれています。

1. [Persistent_and_Dynamic_FA-18C_Training.miz](mission/Persistent_and_Dynamic_FA-18C_Training.miz) をマルチプレイでホストします。
2. BLUEのHornetスロットに搭乗します。Incirlik、Akrotiri、Beirut、Ramat David、空母から出撃できます。
3. 再武装を要請し、訓練に合わせた兵装を搭載します。初期兵装は空です。
4. F10の `Dynamic Training` から任務を選びます。
5. 目標を達成したら、BLUEの基地または空母に帰還して精算します。

スロットには、単独の `SOLO`、AI僚機付きの `AI2`、プレイヤー2人用の `MP2` があります。
MP2では参加する全員が搭乗してから受注してください。

Intercept / SEADを地上で受注した場合は、登録参加者全員の離陸を待ち、離陸検出から20秒後に敵を生成します。
全員が空中で受注した場合、Interceptは即開始、SEADは配置計画の確定後に開始します。
CAPは地上でも受注でき、指定空域をすぐに案内します。登録参加者の誰かが空中で空域内に入ると哨戒時間を数え始めます。全員離陸後の20秒待ちはありません。

## F10メニュー

```text
Dynamic Training
├─ Task: Intercept
├─ Task: CAP
├─ Task: SEAD
├─ Task: DEAD
├─ Mission Status
├─ Abort Mission
└─ Player Statistics
```

`Mission Status` で任務の進行状況、`Player Statistics` で自分の成績を確認できます。
`Abort Mission` はウィング全体の中止です。参加者ごとの `Abort Sortie` が表示されている場合は、その人だけ離脱できます。

BLUE所属の陸上AirbaseはF10上に青色Drawingで表示します。表示対象はruntimeでcoalitionから自動取得し、半径2,500 mの薄い青色Circleと `BLUE AIRBASE`・基地名をBLUE側だけに表示します。文字は基地中心から南へ1,000 mずらしています。Carrier・Ship・FARP・Helipadは対象外です。Allies OnlyとFog of Warの設定は維持します。詳細は [BLUE Airbase表示仕様](docs/MAP_OVERLAY.md) を参照してください。オフセット表示の見やすさはユーザーから改善報告がありますが、DCS内の全確認ケースは未実施です。

## CAPの進め方

`Task: CAP` はMEの4候補空域から1つを等確率で選び、受注時に `CAP AREA: <中心DDM>` を案内します。受注時に登録された未精算・操作中の参加者の誰かが空中で空域内にいる間だけ120秒を積算し、全員退出中は停止、再進入で再開します。進捗は20%ごとに通知します。AI・途中参加者・個人中止者は時間の加算対象に含めません。

敵は同じ累計時間の30〜120秒で1編隊出現します。累計120秒と敵機全滅の両方で達成し、100%でも敵が残っていれば戦闘を続けます。達成後の帰還成功150／事故90ポイントをCAP Scoreに記録します。仕様は [CAP](docs/CAP.md) を参照してください。

コードと模擬テストは実装済みです。2026-10-06のDCSログでGolanの進捗・敵生成/交戦・達成後90点/未達成0点・CAP Score保存と次セッションへの90点引継ぎを確認しました。退出停止/再開、帰還150、MP2はゲーム内確認待ちです。
CAP Scoreの保存形式version2は従来のversion1をCAP=0で読み込めます。CAP導入版では保存Hookも更新し、DCSを再起動してください。

## SEADの後は、帰還も継続攻撃も選べる

SEAD達成後に車両が残っていると、F10に `Continue as DEAD` と `Preserve Site for DEAD` が追加されます。
SA-6のレーダーを破壊しても、発射機が残っていればDEADへ進めます。

| 選択 | その後の流れ |
|---|---|
| **そのまま帰還** | SEADを精算し、全参加者の終了後にサイトを自動削除 |
| **Continue as DEAD** | 同じ出撃のまま残存車両を攻撃。両目標達成後の帰還でSEAD＋DEADを精算。倒しきれず帰還した場合はSEAD分だけ精算 |
| **Preserve Site for DEAD** | サイトを保持してSEADを精算。帰還・再武装後、次の出撃で `Task: DEAD` を受注 |

DEADは、元のSEADで生成された同じSAMグループを使います。損傷や残存車両を引き継ぎ、攻撃するたびに敵が元に戻ることはありません。
保持したSAMは再武装中も世界に存在します。

`Preserve Site for DEAD` で保持したサイトは、RTB・精算後も同じウィング専用に予約されます。再武装後に `Task: DEAD` でそのサイトを取得してください。複数保持している場合は編隊リーダー機に最も近いものを選び、別ウィングのサイトは取得しません。
候補がなければ `No preserved SAM sites available for DEAD.` と表示します。
予約を手放す場合は `Release Site Reservation` を選んでください。同じサイトを他ウィングも受注できる共有候補へ開放します。元SEADの全員精算後、誰も予約していない状態が30分続くと自動削除します。専用保持中やDEAD受注中は、この時間で削除しません。
地上受注時は全員の離陸を待ちますが、SAMの再生成や20秒の生成待ちはありません。

サイトの保持は明示的に選んだ場合だけです。Preserve時の編隊リーダー機の搭乗者を保持者とし、その人がログアウトすると未使用の保持サイトを削除します。
予約を明示解除して共有候補にしたサイトは、元保持者のログアウトでは削除しません。
観戦席への移動や機体変更では削除しません。すでにDEADで使用中のサイトは、その任務の終了まで維持します。

## ウィングで協力する

同じスロットグループを1つのウィングとして扱い、**1ウィングにつき同時に1任務**を受注できます。
目標達成は共有しますが、帰還評価とポイントはプレイヤーごとです。別ウィングは独立した任務を並行して進められます。

参加者は受注時に固定します。空席・AI僚機は採点対象に含めず、途中で搭乗したプレイヤーは次の任務から参加します。
1人が帰還しても、全参加者の精算または中止が終わるまで次の任務は受注できません。

## 帰還とポイント

目標達成だけで即加算せず、帰還結果まで評価します。BLUEの飛行場または空母に着陸し、5 knots以下を連続10秒維持すると帰還成功です。
空母では艦との相対速度を使います。

| 結果 | Intercept / CAP / SEAD / Follow-on DEADの各報酬 |
|---|---:|
| 目標達成＋帰還成功 | 150 pt |
| 目標達成後、帰還成功確定前に墜落・死亡・脱出 | 90 pt（60%） |
| 目標達成前の事故、任意Abort | 0 pt |

報酬は人数で分割せず、参加者それぞれに付与します。
Immediate DEADで両目標を達成して帰還すると、SEAD 150＋DEAD 150で合計300 ptです。
DEADを倒しきれず帰還した場合も、SEAD 150 ptを精算できます。DEAD分は0 ptです。
両目標達成後の事故は合計180 pt、DEAD未達成の事故はSEADの90 ptのみ、任意Abortは0 ptになります。

成績はUCIDで管理し、Player Statisticsにはプレイヤー名・機体名、Total Score、Career Points、精算済み任務数・目標達成・帰還成功・帰還失敗・出撃喪失の件数を25秒間表示します。カテゴリ別スコアは集計・保存しますが、画面には表示しません。表示仕様は [Scoring](docs/SCORING.md#f10-の成績表示実装済み) を参照してください。サーバー用の保存Hookを導入すると、保存済みの成績をミッション再開始・サーバー再起動後も引き継ぎます。
Statisticsには保存済み／保存待ち／未接続を表示します。Hookなしの場合はセッション内のみの記録です。導入手順は [Persistence](docs/PERSISTENCE.md) を参照してください。
2026-10-06に実DCSでHook接続・CAPの90点精算保存・確認通知・正常終了を確認しました。DCS 2.9.30.28738への更新後も次セッションで90点を引き継いでいます。帰還150点の保存と、復元した成績のStatistics画面表示は確認待ちです。
ホストには保存HookとAPI通信の許可を導入します。installerの `-ConfigureHost` で既存autoexec.cfgを残して設定でき、ミッション側のio・lfsの制限解除は不要です。導入後はDCSを再起動してください。
UCIDを照合できない場合も訓練は続けられますが、採点は行いません。

## 開発状況と詳しい仕様

現在は、マルチプレイのME配置済みClientスロットを対象とした試用実装です。動的Clientスロットは対象外です。
任務がゲーム内で動作しているとの報告はありますが、全ケースのDCS内確認は完了していません。自動テストの検証範囲と手動確認項目はテスト仕様書にまとめています。

今後は難易度・Threat Budget、Strike / CAS / Anti-Shipなどの訓練を追加する予定です。

| ドキュメント | 内容 |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | モジュールの責務、状態・識別子・用語、設計上の不変条件と改善候補 |
| [Intercept](docs/Intercept.md) | 敵生成、開始条件、経路、目標判定 |
| [CAP](docs/CAP.md) | 空域抽選、滞在時間、敵生成、時間＋全滅の達成条件 |
| [SEAD](docs/SEAD.md) | TOO / PB、配置条件、レーダーの状態遷移 |
| [DEAD](docs/DEAD.md) | 継続攻撃、サイト保持・予約・削除 |
| [Wing](docs/WING.md) | 共有任務、参加者、受注ブロック、中止 |
| [Scoring](docs/SCORING.md) | UCID、帰還評価、採点と保存の制約 |
| [Persistence](docs/PERSISTENCE.md) | サーバーHookの導入、成績保存・復元、バックアップ |
| [Testing](docs/TESTING.md) | 自動テストの実行方法、DCS内の確認手順 |
| [History](docs/HISTORY.md) | 過去の検証・DCS実測・保存障害の診断経過 |
| [Messages](docs/MESSAGES.md) | 全任務の画面メッセージ・DCSログ、タイミング、表示時間 |
| [Briefing](docs/BRIEFING.md) | Mission Editorへ貼り付ける日本語・英語のミッション説明 |
| [AGENTS.md](AGENTS.md) | 設計方針と開発ルール |

## 開発・Luaの反映

編集元は `src/*.lua` と `vendor/MOOSE/Moose.lua`、設定は [src/config.lua](src/config.lua) にまとめています。
[Build-Mission.ps1](scripts/Build-Mission.ps1) が各モジュールを `build/DynamicTraining.lua` に結合します。生成物は直接編集しません。
ソースの実行入口は [src/main.lua](src/main.lua) です（旧`src/DynamicTraining.lua`）。初期化、F10、任務進行の調整を担当します。ミッションに登録済みの埋め込みファイル名は`DynamicTraining.lua`を使い、ビルド時にmain.luaを最後へ結合します。

Gitではソース、テスト、仕様書、共通のVS Codeタスクを管理します。`mission/*.miz` はMEで編集する基地・Zone・テンプレート・トリガーを含む実行用ミッション、`vendor/MOOSE/Moose.lua` は使用版を固定する依存ファイルとして管理します。
生成済みbundleと検証出力の `build/`、ログ、バックアップ、一時ファイル、DCS/Tacview録画、実プレイヤーの `scores.dat`、環境変数ファイル、VS Codeの個人設定はGitへ追加しません。除外ルールは [.gitignore](.gitignore) にまとめています。

Luaを変更したら、リポジトリのルートで次を実行して `.miz` 内のスクリプトを更新します。同期時に結合も行います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -MissionPath "mission/Persistent_and_Dynamic_FA-18C_Training.miz"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -MissionPath "mission/Persistent_and_Dynamic_FA-18C_Training.miz" -Check
```

保存時の自動同期は `-Watch`、またはVS Codeの `DCS: Watch mission Lua` タスクで起動できます。監視の終了はCtrl+Cです。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -MissionPath "mission/Persistent_and_Dynamic_FA-18C_Training.miz" -Watch
```

同期は登録済みの埋め込みLuaを置き換え、その他のミッション内容の保持を検証します。直前の `.miz` は同じ場所に `.miz.bak` として保存します。
同期後にMEから実行する場合は `.miz` を開き直してください。実行中のDCSミッションへの反映には、更新した `.miz` での再開始が必要です。

全体の検証は次のコマンドで実行できます。両bundleを結合し、Lua全9スイートとBuild/Sync/Installテストを専用fixtureで確認します。実ミッションへの反映は上記Sync/Checkで行います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-All.ps1
```

LuaがPATHにも標準のSteam版DCSの場所にもない場合は `-LuaPath "<Lua 5.1またはDCS luae.exeのパス>"` を指定してください。
詳細な実行方法と確認項目は [docs/TESTING.md](docs/TESTING.md)、コードを変更する際の責務・用語は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を参照してください。

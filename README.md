# Persistent and Dynamic F/A-18C Training

DCS World の Syria マップで、F/A-18C の迎撃・防空制圧・防空サイト破壊を繰り返し練習するための動的訓練ミッションです。
F10から任務を受注すると敵が配置され、目標達成後は味方基地や空母への帰還まで評価します。

ソロ、AI僚機との編隊、2人のマルチプレイに対応しています。出撃場所と兵装を選び、短い迎撃訓練から、SEAD後に再武装してDEADへ向かう連続出撃まで、自分たちのペースで訓練できます。

## 訓練できること

| 任務 | 内容 | 目標達成条件 |
|---|---|---|
| **Intercept — 迎撃** | ランダムな敵編成・方位・高度・フォーメーションに対する空対空戦闘 | 生成された敵航空機をすべて撃墜 |
| **SEAD — 防空制圧** | TOO / PBでSA-6またはSA-8のレーダーを捜索・攻撃 | 主要レーダーを破壊、または損傷させて連続60秒間レーダー停止 |
| **DEAD — 防空サイト破壊** | SEADで制圧したサイトに残る車両への継続攻撃 | DEAD開始時に生存していた対象車両をすべて破壊 |

InterceptではMiG-29A ×2、Su-27 ×1、MiG-29A ×1のいずれかが、長機から60～80 NM、機首方向の左右60°以内に生成されます。高度や編隊も毎回変わります。

SEADでは受注時にTOO / PBを等確率で選びます。TOOは機種不明の捜索座標、PBはSAM機種・推定座標・HARM PBコードを知らせます。
座標はDDM（度＋分の小数3桁）で表示し、実際の配置位置からTOOは3～5 NM、PBは1～3 NMの誤差を持たせます。HARM以外の武器で主要レーダーを破壊しても達成です。

## 始め方

必要な環境は **DCS World / Syriaマップ / F/A-18C** です。MOOSEと訓練スクリプトはミッションに組み込まれています。

1. [mission/Syria.miz](mission/Syria.miz) をマルチプレイでホストします。
2. BLUEのHornetスロットに搭乗します。Incirlik、Akrotiri、Beirut、Ramat David、空母から出撃できます。
3. 再武装を要請し、訓練に合わせた兵装を搭載します。初期兵装は空です。
4. F10の `Dynamic Training` から任務を選びます。
5. 目標を達成したら、BLUEの基地または空母に帰還して精算します。

スロットには、単独の `SOLO`、AI僚機付きの `AI2`、プレイヤー2人用の `MP2` があります。
MP2では参加する全員が搭乗してから受注してください。

Intercept / SEADを地上で受注した場合は、登録参加者全員の離陸を待ち、離陸検出から20秒後に敵を生成します。
全員が空中で受注した場合、Interceptは即開始、SEADは配置計画の確定後に開始します。

## F10メニュー

```text
Dynamic Training
├─ Generate Intercept
├─ Generate CAP
├─ Generate SEAD
├─ Generate DEAD
├─ Mission Status
├─ Abort Mission
└─ Player Statistics
```

`Mission Status` で任務の進行状況、`Player Statistics` で自分の成績を確認できます。
`Abort Mission` はウィング全体の中止です。参加者ごとの `Abort Sortie` が表示されている場合は、その人だけ離脱できます。

BLUE所属の陸上AirbaseはF10上に青色Drawingで表示します。表示対象はruntimeでcoalitionから自動取得し、半径2,500 mの薄い青色Circleと `BLUE AIRBASE`・基地名をBLUE側だけに表示します。文字は基地中心から南へ1,000 mずらしています。Carrier・Ship・FARP・Helipadは対象外です。Allies OnlyとFog of Warの設定は維持します。詳細は [BLUE Airbase表示仕様](docs/MAP_OVERLAY.md) を参照してください。オフセット表示の見やすさはユーザーから改善報告がありますが、DCS内の全確認ケースは未実施です。

`Generate CAP` はMEの4候補空域から1つを等確率で選び、受注時に `CAP AREA: <中心DDM>` を案内します。登録参加者の誰かが空中で空域内にいる間だけ120秒を積算し、全員退出中は停止、20%ごとに通知します。敵は同じ累計時間の30〜120秒で1編隊出現します。累計120秒と敵機全滅の両方で達成し、その後の帰還成功150／達成後事故90ポイントをCAP Scoreに記録します。仕様は [CAP](docs/CAP.md)。コードと模擬テストは実装済み。2026-10-06のDCSログでGolanの進捗・敵生成/交戦・達成後90点/未達成0点・CAP Score保存を確認しました。退出停止/再開、帰還150、MP2、再開始後の得点復元は確認待ちです。
CAP Scoreの保存形式version2は従来のversion1をCAP=0で読み込めます。CAP導入版では保存Hookも更新し、DCSを再起動してください。

## SEADの後は、帰還も継続攻撃も選べる

SEAD達成後に車両が残っていると、F10に `Continue as DEAD` と `Preserve Site for DEAD` が追加されます。
SA-6のレーダーを破壊しても、発射機が残っていればDEADへ進めます。

| 選択 | その後の流れ |
|---|---|
| **そのまま帰還** | SEADを精算し、全参加者の終了後にサイトを自動削除 |
| **Continue as DEAD** | 同じ出撃のまま残存車両を攻撃。両目標達成後の帰還でSEAD＋DEADを精算。倒しきれず帰還した場合はSEAD分だけ精算 |
| **Preserve Site for DEAD** | サイトを保持してSEADを精算。帰還・再武装後、次の出撃で `Generate DEAD` を受注 |

DEADは、元のSEADで生成された同じSAMグループを使います。損傷や残存車両を引き継ぎ、攻撃するたびに敵が元に戻ることはありません。
保持したSAMは再武装中も世界に存在します。

`Preserve Site for DEAD` で保持したサイトは、RTB・精算後も同じウィング専用に予約されます。再武装後に `Generate DEAD` でそのサイトを取得してください。複数保持している場合は長機に最も近いものを選び、別ウィングのサイトは取得しません。
候補がなければ `No preserved SAM sites available for DEAD.` と表示します。
予約を手放す場合は `Release Site Reservation` を選んでください。同じサイトを他ウィングも受注できる共有候補へ開放します。元SEADの全員精算後、誰も予約していない状態が30分続くと自動削除します。専用保持中やDEAD受注中は、この時間で削除しません。
地上受注時は全員の離陸を待ちますが、SAMの再生成や20秒の生成待ちはありません。

サイトの保持は明示的に選んだ場合だけです。Preserve時の長機を保持者とし、その人がログアウトすると未使用の保持サイトを削除します。
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

| 結果 | Intercept / SEAD / Follow-on DEADの各報酬 |
|---|---:|
| 目標達成＋帰還成功 | 150 pt |
| 目標達成後、帰還成功確定前に墜落・死亡・脱出 | 90 pt（60%） |
| 目標達成前の事故、任意Abort | 0 pt |

報酬は人数で分割せず、参加者それぞれに付与します。
Immediate DEADで両目標を達成して帰還すると、SEAD 150＋DEAD 150で合計300 ptです。
DEADを倒しきれず帰還した場合も、SEAD 150 ptを精算できます。DEAD分は0 ptです。
両目標達成後の事故は合計180 pt、DEAD未達成の事故はSEADの90 ptのみ、任意Abortは0 ptになります。

成績はUCIDで管理し、カテゴリ別スコアと累計・任務・帰還・出撃喪失の統計を表示します。サーバー用の保存Hookを導入すると、保存済みの成績をミッション再開始・サーバー再起動後も引き継ぎます。
Statisticsには保存済み／保存待ち／未接続を表示します。Hookなしの場合はセッション内のみの記録です。導入手順は [Persistence](docs/PERSISTENCE.md) を参照してください。
2026-10-06に実DCSでHook接続・初回保存・確認通知・正常終了を確認しました。実プレイヤーのポイント精算保存とDCS再起動後の成績復元は確認待ちです。
ホストには保存HookとAPI通信の許可を導入します。installerの `-ConfigureHost` で既存autoexec.cfgを残して設定でき、ミッション側のio・lfsの制限解除は不要です。導入後はDCSを再起動してください。
UCIDを照合できない場合も訓練は続けられますが、採点は行いません。

## 開発状況と詳しい仕様

現在は、マルチプレイのME配置済みClientスロットを対象とした試用実装です。動的Clientスロットは対象外です。
任務がゲーム内で動作しているとの報告はありますが、全ケースのDCS内確認は完了していません。自動テストの検証範囲と手動確認項目はテスト仕様書にまとめています。

今後は難易度・Threat Budget、Strike / CAS / Anti-Shipなどの訓練を追加する予定です。

| ドキュメント | 内容 |
|---|---|
| [Intercept](docs/Intercept.md) | 敵生成、開始条件、経路、目標判定 |
| [CAP](docs/CAP.md) | 空域抽選、滞在時間、敵生成、時間＋全滅の達成条件 |
| [SEAD](docs/SEAD.md) | TOO / PB、配置条件、レーダーの状態遷移 |
| [DEAD](docs/DEAD.md) | 継続攻撃、サイト保持・予約・削除 |
| [Wing](docs/WING.md) | 共有任務、参加者、受注ブロック、中止 |
| [Scoring](docs/SCORING.md) | UCID、帰還評価、採点と保存の制約 |
| [Persistence](docs/PERSISTENCE.md) | サーバーHookの導入、成績保存・復元、バックアップ |
| [Testing](docs/TESTING.md) | 自動テストの実行方法、DCS内の確認手順 |
| [Messages](docs/MESSAGES.md) | 全任務の画面メッセージ・DCSログ、タイミング、表示時間 |
| [Briefing](docs/BRIEFING.md) | Mission Editorへ貼り付ける日本語・英語のミッション説明 |
| [AGENTS.md](AGENTS.md) | 設計方針と開発ルール |

## 開発・Luaの反映

編集元は `src/*.lua` と `vendor/MOOSE/Moose.lua`、設定は [src/config.lua](src/config.lua) にまとめています。
[Build-Mission.ps1](scripts/Build-Mission.ps1) が各モジュールを `build/DynamicTraining.lua` に結合します。生成物は直接編集しません。

Luaを変更したら、リポジトリのルートで次を実行して `.miz` 内のスクリプトを更新します。同期時に結合も行います。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -Check
```

保存時の自動同期は `-Watch`、またはVS Codeの `DCS: Watch mission Lua` タスクで起動できます。監視の終了はCtrl+Cです。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -Watch
```

同期は登録済みの埋め込みLuaを置き換え、その他のミッション内容の保持を検証します。直前の `.miz` は `mission/Syria.miz.bak` に保存します。
同期後にMEから実行する場合は `.miz` を開き直してください。実行中のDCSミッションへの反映には、更新した `.miz` での再開始が必要です。

テストの実行コマンドと確認項目は [docs/TESTING.md](docs/TESTING.md) を参照してください。

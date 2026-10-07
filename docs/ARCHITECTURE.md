# 実装構成と設計上の約束

更新日: 2026-10-07

## 対象

Intercept / CAP / SEAD / DEADの現在の実装を説明する。訓練の条件は各機能仕様書、出力は [MESSAGES.md](MESSAGES.md)、検証は [TESTING.md](TESTING.md) を正とする。将来案は実装済みの機能と分ける。

この構成は`training-5`で実装済み。DCS内での確認範囲は [HISTORY.md](HISTORY.md) の実測記録とTESTINGの手動ケースを参照する。修正版のDCS確認は未実施。

## 責務と依存

| 層 | モジュール | 責務 |
|---|---|---|
| 設定 | `config.lua` | 訓練値・時間・候補・報酬。各任務の設定は`intercept` / `cap` / `sead` / `dead`に置く |
| 搭乗者 | `player.lua` | BLUE Hornetの動的列挙、UCID・機体・イベント照合 |
| 任務台帳 | `missions.lua` | Wing/UCIDロック、受注順、活動中任務とSiteの参照 |
| 空中目標 | `air_targets.lua` | Intercept/CAPの生成済み機体のID固定、喪失イベント、生存観測 |
| 任務 | `intercept.lua` / `cap.lua` | 敵航空機の生成・経路と削除待ち。CAPは計画・滞在時間・進捗も管理 |
| 地上目標 | `sead.lua` / `sead_objective.lua` | SAM計画・安全配置と主要レーダーFSMを分離 |
| Site寿命 | `sead_sites.lua` | 保持・専用予約・開放・使用予約・削除・削除再試行 |
| 継続攻撃 | `dead.lua` | 既存Site選定、残存対象の固定、DEAD判定・ブリーフィング |
| 帰還・精算 | `recovery.lua` / `scoring.lua` | 各参加者の帰還確認と、採点ID＋UCIDごとの一度だけの精算 |
| 成績保存 | `score_data.lua` / `persistence.lua` | 共通schema/codec、ミッション側snapshot・復元・保存確認 |
| 表示 | `mission_report.lua` / `notifications.lua` | Status/Statistics本文と表示時間、画面・MESSAGEログ・DEBUG・例外通知 |
| 地図 | `map_overlay.lua` | BLUE陸上基地Drawing。任務・採点とは独立 |
| 実行入口・調整 | `main.lua` | 初期化、F10 callback、受注・開始・達成・中止・精算の調整、共有タイマーとイベント配信 |

`Build-Mission.ps1`の順序付き対応表がモジュールの読み込み順とLua変数名を一箇所で管理する。依存先を先に結合し、実行調整を最後に置く。生成済みbundleは直接編集しない。DCS内では`require`や外部ファイル読み込みを使わない。

MissionReportは本文と表示時間を返し、main.luaが対象グループへ送る。Statusは既存の目標観測・Site Refreshを呼ぶため完全な純粋関数ではないが、任務の生成・精算・帰還確定は行わない。Notificationsは受注や任務状態を判断せず、通知する時点はmain.luaが決める。

サーバー側は`DynamicTrainingPersistenceHook.lua`がcallback寿命、`persistence_service.lua`が保存手順、`mission_bridge.lua`が固定endpoint通信、`persistence_fs.lua`がnative I/O差異、`score_store.lua`が検証・backupを担当する。ミッションはSaved Gamesへ直接書き込まない。保存境界の詳細は [PERSISTENCE.md](PERSISTENCE.md) を参照する。

## 任務・出撃・採点・Siteを区別する

| 用語 | 実装と識別子 | 寿命 |
|---|---|---|
| Wing assignment（ウィング任務） | `Missions.wings[groupName]`の`record`、実行内連番`assignmentID` | Acquireから全登録参加者の終了まで。カテゴリを問わず1 Wingに1件 |
| Participant / sortie（参加者の出撃） | `record.participants`の`p`、受注時に固定した`p.owner` | 各人の帰還・事故・Abortまで。目標は共有、結果は個別 |
| Scoring record（採点記録） | `p.id`＋開始時UCID。`Scoring.settlements[id][key]` | 一度だけ精算。IDは全カテゴリ共通の連番、接続後はrun番号を含む |
| Immediate DEADの追加採点 | `record.deadScoringID` / `p.deadScoring`、`scoreOnly=true` | 元SEADと同じ出撃。追加点だけ、任務・死亡等の統計を二重加算しない |
| SAM site | `Missions.sites[site.id]`、元SEADの採点ID | 元の任務と独立。明示保持ならRTB後も残る。任務再開始で復元しない |

任務の`state`は全体phase、参加者の`state`は各人のphase、Siteの`state`は車両の観測状態、`disposition`は保持・使用・削除方針。これらを同じ値として扱わない。特にSEADの`primaryResult`は主要レーダーの達成履歴であり、Site全滅の証拠ではない。

通常はARMED → ACTIVE → RTB_PENDING、地上Intercept/SEADはTAKEOFF_DELAY、SEADの地点選定はPLANNINGを挟む。CAPは受注後すぐACTIVE。Immediate DEADは元SEADのRTB_PENDING → DEAD_ACTIVE → RTB_PENDING。参加者だけLANDING_CHECKを持つ。すべての精算・中止後に台帳から解放し、終端状態のrecordを新任務に再利用しない。

## 命名とデータ契約

- ファイルは既存のsnake_case、公開Luaモジュール関数はPascalCaseに合わせる。ソースの実行入口は`src/main.lua`。`runtime`は実行時の処理を指す用語で、旧入口`src/DynamicTraining.lua`を指していた。ビルドがmain.luaを最後に加え、登録済み埋め込みとbundleの名前は`DynamicTraining.lua`を維持する。ソース改名によるME変更は不要。
- `record.owner`は現在の長機基準、`p.owner`は受注時の個人識別情報。`owner`という既存名の意味は所属するrecordによって異なる。成績のキーはどちらも表示名ではなくUCID。
- `groupName`はDCSグループ名、`unitName`は機体名、`objectID`は実体の識別子。ネットワークslotのtemplate unitIdとruntime object IDを取り違えない。
- 設定の単位は名前で表す（NM / Ft / Knots / Meters / Seconds / Mps）。内部座標はDCSのm、ユーザー表示はNM / ft / knots。Vec2の`y`は水平軸、Vec3の水平軸は`z`。
- Interceptの報酬設定は旧`Config.fullReward`から`Config.intercept.fullReward`へ移動した。CAP/SEAD/DEADと同じ配置で、初期値150は維持する。独自設定を移植する場合は新しいキーを使う。
- MEのテンプレート・Zone名は外部契約。コード整理で改名しない。保存schema・bridge endpoint名も独立した互換性の契約として扱う。

## 判定と終了処理の不変条件

1. Wing/UCIDロックを取得してから計画・予約・生成する。準備失敗時は取得分をrollbackする。
2. 受注時の人間参加者と元の機体を固定する。空席・AI・途中参加を追加しない。
3. 対象は生成時またはDEAD受注時に固定する。明示lossイベントを優先し、nil・例外・不正値・別IDを全滅の証拠にしない。明示falseでIDが消えた死亡wrapperは、固定済み空中目標の死亡として扱える。
4. 全員終了時は任務ロックを解放してからDestroyする。Destroyに伴うイベントで成功や再採点を発生させない。
5. Siteの専用予約とassignment使用予約は別。Preserve/Releaseで元の採点・帰還・Wing/UCIDロックを変えない。
6. 目標達成時には累計へ加算しない。参加者ごとの精算時にだけ更新し、Hookの有効なACK前には保存済みと表示しない。
7. 1つのタイマーと安定した任務snapshotから各任務を監視する。例外は該当処理でログに残し、他Wingの監視を継続する。
8. MOOSEのイベント受信者は`DynamicTrainingRuntime.eventHandler`でミッション終了まで強参照を保持する。同梱MOOSEのEVENT:Initは受信者を弱キーで保存するため、ローカル変数での登録だけではGC後に受信しなくなる。重複読み込みでは元の受信者を保持し、再登録しない。

## 整理した箇所と残る課題

training-2では出力と手動レポートをruntimeから分離し、空中目標の観測を共通化した。Interceptの不明観測による誤達成を防ぎ、SEAD StatusのSpawnカウントダウンを既存のDEBUG限定方針に揃えた。任務なしStatus/AbortのIdle一覧も共通化した。

さらに分離する候補は、main.lua内の任務別受注・Immediate DEAD切替・精算調整とF10再構築。ただしrecordの変更順序、イベント順序、rollbackが採点に直結するため、各境界の結合テストを維持しながら機能単位で行う。現時点で汎用FSMや全カテゴリ共通の継承構造は導入しない。

training-3では実行入口をmain.luaへ改名し、Interceptの敵削除再試行も実装した。終了後と生成後設定失敗時の敵参照をInterceptが保持し、5秒ごとに共通タイマーから再試行する。false・例外・実体残存・確認不能を成功にせず、消失確認後に参照を解放する。任務ロックは先に解放し、遅れたDestroyイベントを旧任務の達成・再精算に使わない。

プレイヤー切断・再接続、DCS/MOOSEのwrapper寿命、実際のAI・地形・着地判定は模擬テストだけでは確定しない。手動確認の未実施項目を実装不足と混同せず、TESTINGの対象版・条件・実測結果を更新する。

## 開発と検証

全体の確認は`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-All.ps1`。両bundleを結合し、Lua 9スイートとBUILD/SYNC/INSTALLを使い捨てfixtureで検証する。Luaの場所は`-LuaPath`で指定できる。

実ミッションへの反映はその後に`Sync-Mission.ps1`、続けて`Sync-Mission.ps1 -Check`。既定先は`mission/Persistent_and_Dynamic_FA-18C_Training.miz`。別ファイルは`-MissionPath`で明示する。既存埋め込みLuaだけを置換し、ZIP内のその他の内容を保持する。詳細はREADMEとTESTINGを参照する。

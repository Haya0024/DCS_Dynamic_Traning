# 成績の永続保存

更新日: 2026-10-06

## 保存対象と境界

UCIDごとのTotal Score、Career Points、Intercept / CAP / SEAD / DEAD Score、任務数、Primary成功数、帰還成功数、帰還失敗数、未達成失敗数、中止数、Death Countを保存する。
Death Countは登録機の墜落・死亡・脱出・UnitLostによる出撃喪失数。最初の精算時に1回だけ数え、同じ喪失の後続イベントやImmediate DEADの追加採点では増やさない。
未精算任務、Wingロック、SAM Site、機体や兵装は保存しない。ミッション終了時に未精算だった任務へ推定報酬を与えない。
既存の150 / 90 / 0、Immediate DEADのSEAD＋DEAD報酬、UCID未照合時の非採点は維持する。

## 構成

ミッション側は累計と精算台帳を更新し、保存用snapshotを公開する。サーバー側HookだけがSaved Gamesへ読み書きする。MissionScripting.luaの制限解除は不要。
Hookはサーバー実行時のみ動作する。Simulation callbacksとHook環境のlfs / io / osを使用し、`net.dostring_in("mission", code)` とmanager側 `a_do_script` で実SSEへ接続する。Hook・manager・実SSEは別のglobal環境であり、serverやmanagerで任務globalを直接参照しない。Hook自身でa_do_scriptを直接呼ばない。実環境でnil/nilしか返らなかったscripting接続は使用しない。
通信結果は型付き文字列として返し、nil・boolean・number・保存データのstringを区別する。API例外、拒否、空・不正な返信、ミッション側例外は保存成功にしない。保存データや返信文字列をLuaとして実行しない。未接続時は保存ファイルを新規作成せず、ミッション側の採点は継続する。
実行中のstorageエラーと開始前/終了後のbridgeエラーを分離して診断する。実DCSで型付き通信・native file操作・保存確認まで検証した経過は [HISTORY.md](HISTORY.md#成績保存の診断履歴) に残す。
ホストのAPI許可は `Config/autoexec.cfg` で、呼出元 `userhooks` と接続先 `mission` を追加する。従来のserver許可と既存の設定・他の許可項目は維持する。allow_unsafe_apiへscriptingは追加しない。ミッション側へnet・io・lfsを追加公開しない。DCSのAPI制限の説明は [ED公式告知](https://forum.dcs.world/topic/376636-changes-to-the-behaviour-of-netdostring_in/) を参照する。同梱API文書のscriptingに関する説明だけでは実SSE接続の保証にならず、実ログを優先する。

実SSE内で返信を `DTBR1:` の型付き文字列にし、`return encodedReply, 0` で末尾scalarを添える。[DCS 2.9.18以降の不具合報告](https://forum.dcs.world/topic/376809-a_do_script-return-value-pass-thru-mangled-since-dcs-291812722/) は先頭nilへの位置ずれと末尾値欠落を示す。managerは最初の2位置を照合して型付き文字列だけを返す。正常dispatcherでは第1位置、報告された不具合では第2位置から取得できる。全返信が失われる実装は保存成功にしない。これは不具合を模擬して検証した回避策であり、現DCS版で位置ずれ自体を直接観測したものではない。
native境界へtable/userdataを返さない。コードとsnapshot文字列は各境界でLuaの `%q` により引用し、返信をコードとして実行しない。不正返信時は型・文字列長・API statusと、固定形式のdispatcher第1/第2位置の型だけをエラーへ付記し、返信本文や成績を記録しない。

| ファイル | 責務 |
|---|---|
| `src/score_data.lua` | schema検証・データの文字列化／復元。保存内容をLuaコードとして実行しない |
| `src/persistence.lua` | snapshot、読み込み済み累計との統合、保存確認・表示状態 |
| `src/scoring.lua` | 従来の重複防止・採点・統計とsnapshot revision |
| `server/score_store.lua` | 検証付き書き込み、backup、復旧 |
| `server/persistence_fs.lua` | native I/Oの正規化、未作成/読み取り不能の区別、file handleを閉じる |
| `server/mission_bridge.lua` | 固定endpointの通信、型付き返信・戻り値位置ずれの処理 |
| `server/persistence_service.lua` | durable run、累計復元、snapshot保存、確認通知の順序と失敗段階 |
| `server/DynamicTrainingPersistenceHook.lua` | callback寿命、ホスト判定、poll/retry、段階付きログ |

## 設計判断

採点台帳・累計snapshot・run/revisionによる再送方式を維持する。これらは任務進行と保存を分離でき、通信の再試行で得点を二重加算しない。通信先の自動切替は行わず、実ログでprotocol取得が通過したmission manager経路を使用する。ミッション側io/lfsの解除、汎用socket/consoleの導入、成績のログ出力を保存経路に使う方式は採用しない。
Hookの寿命管理、通信、native I/O、transaction coordinatorを独立させる。fixtureでDCS APIを理想化せず、正常/位置ずれ/欠落、errnoあり/なし、実行前/停止後、保存成功/返信喪失を別々に入力する。模擬検証と実DCSでの保存確認を区別する。

公開実装との比較（2026-10-06にREADME/仕様と同梱MOOSEを確認。全コードの監査や信頼性比較試験ではない）:

| 比較対象 | 保存の構成 | 本プロジェクトへの判断 |
|---|---|---|
| [Pretenseの公開実装](https://github.com/GoldJohnKing/pretense) | world stateとplayer statsを別fileへ保存。missionのio/lfs制限解除を要求 | worldと成績を分離する方針は共通。本件は成績だけなのでworld復元は追加しない |
| [Persistent World Script](https://github.com/Queton1-1/DCS-Persistent-World-Script) | missionからfilesystemへ保存。units/warehouses/flags等を対象に定期保存 | 直接保存は境界が少ない。本件はmissionのfilesystemを公開しない要件があるためHost Hookを使用 |
| [DCSServerBot CreditSystem](https://github.com/Special-K-s-Flightsim-Bots/DCSServerBot/blob/master/plugins/creditsystem/README.md) | player UCIDとcampaign IDに紐づくcreditsをdatabaseで管理 | 個人成績のUCID管理とhost側保存は本件にも適する。小規模な単一ホストではDB/別常駐processは必須ではない |

本設計は単一のDCS hostが1つのSaved Gamesのscore fileを所有する範囲を想定する。複数hostが同じfileへ同時書き込みする排他制御や共有DBは現在の実装範囲外。設計方針の妥当性とDCS実機での保存成功は別に評価する。

## 起動・精算・保存

1. HookはMissionLoadEndまで待ち、ホストの実行中frameでendpointを確認する。スロット選択・Statistics操作は不要。保存ファイルを読み、一意なrun番号を採番して保存する。
2. ミッションへ累計を渡す。Hook接続より先に精算があった場合、そのセッション内の加算分を既存累計へ1回だけ足す。復元を繰り返して二重加算しない。
3. 各精算でメモリ内の台帳を確定し、revisionを進める。追加DEADも別精算だが任務・死亡統計は増やさない。
4. Hookが約1秒間隔で未保存snapshotを取り、検証・保存後にrun番号とrevisionを確認通知する。
5. ミッション側は有効な確認を受けた該当revisionだけを保存済みとする。Initialize直後はrevision=0でも確認待ち。未初期化の確認やbootstrapのcounter/session不一致は拒否する。古い確認が新しい精算を保存済みにしない。

serviceの段階はPROTOCOL → DIRECTORY → LOAD → BOOTSTRAP → ATTACH → SNAPSHOT → VALIDATE/SAVE → ACK → CONNECTED。失敗にはphaseを付け、次のpollで同じ確定済みrun・bootstrap・snapshotを再利用する。Initializeの返信だけが失われても再採番や再統合を行わない。snapshotのrevision後退を拒否する。

snapshotは累計を置き換える方式。同じrun / revisionの再送は再加算せず、別runのsnapshotは拒否する。run番号と保存revisionも累計と同じファイルへ保存する。
Hook接続後に発行する任務IDはrun番号で名前空間を分離する。接続前のIDは現ミッションの台帳内だけで使用する。
保存未接続時も訓練・採点を継続するが「セッション内のみ」と表示する。接続後も書き込み確認前は「保存待ち」であり、永続保存済みと表示しない。
起動通知はHookの非同期接続前なので `Persistence initialization pending.` と表示する。Statisticsの未接続表示と区別し、初期表示だけを保存失敗の根拠にしない。保存無効時の表示は従来通りdisabled。
Stopではpollを無効にし、ホストの接続済みsessionだけ最終snapshotの保存を試行する。18:30 JSTの実ログではSSE破棄後にStop処理が走り、返信が失われた。この場合はSTOP_FLUSH_UNAVAILABLEと最後の保存済みrevisionを記録する。Stop後のframeで再通信・採番しない。最後のpollから終了までの未確認精算は停止順や強制終了により失われ得るため、終了前の保存確認を基準にする。

## ファイル形式と復旧

保存先はサーバーの `Saved Games/DCS/DynamicTraining/scores.dat`（実際はlfs.writedir配下）。
version 2の固定schema。version1の従来12数値列を保持し、末尾へcapScoreを追加する。version1も旧列数・checksum・canonical形式を検証して読み込み、CAP=0へ移行する。保存時はversion2。文字列はhex、数値は非負整数、行構成・重複UCID・上限を検証する。個人ごとのファイル名にUCIDを使わない。CAP導入時はmission/Hookを同時更新し、Hook再導入後にDCSを再起動する。移行は通常のHook接続で行い、開発作業で実成績fileを直接書き換えない。
未知のschemaは通常の破損と区別してLOAD/SAVEを停止する。正常な古いbackupがあっても未知primaryを巻き戻して上書きしない。
一時ファイルへ書き込み・flush・close・再読検証後に置換し、直前の正常ファイルを `scores.dat.bak` に保持する。置換失敗時は元ファイルを復元し、snapshotを未保存のまま再試行する。
primaryが欠落・破損なら正常backupから復旧する。primaryが読み取り不能ならbackupが正常でも復旧を進めず、現在の累計の巻き戻りを防ぐ。primaryとbackupがともに不正なら、ゼロの累計で上書きせず保存を停止してログへ記録する。破損データは自動実行しない。
保存ファイルが両方存在しない初回だけ空の累計を作成する。保持Site等をファイルへ含めない。
native I/Oの数値errnoが欠落しても文字列の文言・言語から不存在を推測しない。数値ENOENTがないときは、親directoryを最後まで列挙し対象名がないことを確認する。既存file・権限エラー・属性取得例外・列挙エラー/中断はunreadableとして保存を停止する。失敗ログにはprimary/backupそれぞれの状態とI/O詳細を残し、成績本文を記録しない。読み書き途中の例外でもfileを閉じる。
fileのwrite/flush/closeは例外・false・エラー返信を拒否するが、成功時に返り値がない実装も扱う。flush methodが提供される場合は呼び出す。提供されない場合はclose後の再読検証を必須とする。writeの呼び出し結果だけで保存成功にはせず、同じbytesの再読とschema検証を通してから昇格する。renameはsource消失とdestinationの同一bytes、removeは不存在を確認する。IO_COMPATIBILITYで戻り値の型とflushの有無を1回記録する。OSの物理fsyncや電源断までの耐久性を保証する方式ではない。

## 導入

次を実行する。専用モジュールを結合した1つのHookを配置し、既存の別Hookには触れない。同名の旧ファイルは更新前にbackupする。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-PersistenceHook.ps1 -SavedGamesPath "$env:USERPROFILE\Saved Games\DCS" -ConfigureHost
```
DCSを再起動し、更新した `.miz` を使用する。参加者側のHook配置は不要。
`-ConfigureHost` は既存autoexec.cfgをbackupし、管理用ブロックを追加する。再実行では内容が同じなら書き換えない。不完全・重複した管理ブロックや不正な文字コードでは変更を拒否する。DLSS等の既存設定、別Hook、MissionScripting.lua、保存済み成績は変更しない。
Hookだけを更新する場合は `-ConfigureHost` を省略できる。API未公開・接続拒否時はDCSログの `DynamicTrainingPersistence` とautoexec.cfgの許可を確認する。
`src/config.lua` の `persistence.enabled` でミッション側の接続を無効にできる。保存ファイルは削除しない。

## 確認

自動テストでrestart復元、遅延接続、重複精算／snapshot、古い確認、破損backup復旧、書き込み失敗、複数run、非サーバー無動作、停止時保存、UCID未照合、Immediate DEAD、死亡統計を確認する。
DCSでは150 / 90 / 0の精算後に保存済み表示を確認し、ミッション再開始とDCS再起動で同じUCIDの累計が戻ること、別UCIDの成績が混ざらないこと、Hookなしでは未保存表示になることを確認する。
保存と確認通知まで通過したとき、`Connected via mission/a_do_script+scalar-sentinel; storage and acknowledgement confirmed.` をログへ1回記録する。BOOTSTRAP_COMMITTEDはrun採番保存、SNAPSHOT_COMMITTEDは各revisionの保存を示す。初期接続ログだけでは実プレイヤーの精算保存・再起動復元を確認済みとしない。

## 未接続時の診断

`DynamicTrainingPersistenceDiagnostic` のINFOログでHook登録、ミッション読み込み開始、最初のSimulation frame、非サーバー状態、実SSEのendpoint待ち、接続を区別する。通常の画面通知・採点・保存方針は変更しない。
endpointが見つからない場合はprotocol値と実SSE環境の `DynamicTrainingPersistence` / `trigger` / `timer` / `coalition` / `a_do_script` の型だけを記録する。任務データ・UCID・成績・任意コードを診断ログへ出さず、Hook自身の環境から `a_do_script` は直接呼ばない。
frameとendpoint待ちのログは最初の1回／状態遷移時だけ出し、1秒ごとに同じログを繰り返さない。接続まで未生成のscores.datを診断目的で作らない。

実DCSの診断経過と証跡は [HISTORY.md](HISTORY.md#成績保存の診断履歴) を参照する。初期接続・CAP90点精算保存・次セッションへの引継ぎは確認済み。帰還150点保存と復元成績の画面確認等は [TESTING.md](TESTING.md) の手動ケースで確認する。

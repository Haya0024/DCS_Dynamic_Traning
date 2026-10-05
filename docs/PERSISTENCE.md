# 成績の永続保存

更新日: 2026-10-05

## 保存対象と境界

UCIDごとのTotal Score、Career Points、Intercept / SEAD / DEAD Score、任務数、Primary成功数、帰還成功数、帰還失敗数、未達成失敗数、中止数、Death Countを保存する。
Death Countは登録機の墜落・死亡・脱出・UnitLostによる出撃喪失数。最初の精算時に1回だけ数え、同じ喪失の後続イベントやImmediate DEADの追加採点では増やさない。
未精算任務、Wingロック、SAM Site、機体や兵装は保存しない。ミッション終了時に未精算だった任務へ推定報酬を与えない。
既存の150 / 90 / 0、Immediate DEADのSEAD＋DEAD報酬、UCID未照合時の非採点は維持する。

## 構成

ミッション側は累計と精算台帳を更新し、保存用snapshotを公開する。サーバー側HookだけがSaved Gamesへ読み書きする。MissionScripting.luaの制限解除は不要。
Hookはサーバー実行時のみ動作する。Simulation callbacksとHook環境のlfs / io / osを使用し、`net.dostring_in("server", code)` でミッションのLua環境へ接続する。Hook環境に存在しない `a_do_script` を直接呼ばない。
通信結果は型付き文字列として返し、nil・boolean・number・保存データのstringを区別する。API例外、拒否、空・不正な返信、ミッション側例外は保存成功にしない。保存データや返信文字列をLuaとして実行しない。未接続時は保存ファイルを新規作成せず、ミッション側の採点は継続する。
ホストのAPI許可は `Config/autoexec.cfg` で、呼出元 `userhooks` と接続先 `server` だけを追加する。既存の設定・許可項目は維持する。ミッション側へnet・io・lfsを追加公開しない。DCSのAPI制限の説明は [ED公式告知](https://forum.dcs.world/topic/376636-changes-to-the-behaviour-of-netdostring_in/) と同梱API文書を参照する。制限が撤回された版でも同じHookを使う。

| ファイル | 責務 |
|---|---|
| `src/score_data.lua` | schema検証・データの文字列化／復元。保存内容をLuaコードとして実行しない |
| `src/persistence.lua` | snapshot、読み込み済み累計との統合、保存確認・表示状態 |
| `src/scoring.lua` | 従来の重複防止・採点・統計とsnapshot revision |
| `server/score_store.lua` | 検証付き書き込み、backup、復旧 |
| `server/DynamicTrainingPersistenceHook.lua` | 起動／フレーム／終了時の橋渡し |

## 起動・精算・保存

1. Hookが保存ファイルを読み、サーバー内で一意なrun番号を採番して保存する。
2. ミッションへ累計を渡す。Hook接続より先に精算があった場合、そのセッション内の加算分を既存累計へ1回だけ足す。復元を繰り返して二重加算しない。
3. 各精算でメモリ内の台帳を確定し、revisionを進める。追加DEADも別精算だが任務・死亡統計は増やさない。
4. Hookが約1秒間隔で未保存snapshotを取り、検証・保存後にrun番号とrevisionを確認通知する。
5. ミッション側は該当revisionだけを保存済みとする。古い確認が新しい精算を保存済みにしない。

snapshotは累計を置き換える方式。同じrun / revisionの再送は再加算せず、別runのsnapshotは拒否する。run番号と保存revisionも累計と同じファイルへ保存する。
Hook接続後に発行する任務IDはrun番号で名前空間を分離する。接続前のIDは現ミッションの台帳内だけで使用する。
保存未接続時も訓練・採点を継続するが「セッション内のみ」と表示する。接続後も書き込み確認前は「保存待ち」であり、永続保存済みと表示しない。
正常なミッション停止callbackでも最後のsnapshotの保存を試行する。実機でのcallback順は確認待ち。強制終了・停電では未保存分が失われる可能性があり、表示の保存状態を基準にする。

## ファイル形式と復旧

保存先はサーバーの `Saved Games/DCS/DynamicTraining/scores.dat`（実際はlfs.writedir配下）。
version 1の固定schema。文字列はhex、数値は非負整数、行構成・重複UCID・上限を検証する。個人ごとのファイル名にUCIDを使わない。
一時ファイルへ書き込み・flush・close・再読検証後に置換し、直前の正常ファイルを `scores.dat.bak` に保持する。置換失敗時は元ファイルを復元し、snapshotを未保存のまま再試行する。
primaryが欠落・破損なら正常backupから復旧する。primaryとbackupがともに不正なら、ゼロの累計で上書きせず保存を停止してログへ記録する。破損データは自動実行しない。
保存ファイルが両方存在しない初回だけ空の累計を作成する。保持Site等をファイルへ含めない。

## 導入

次を実行する。専用モジュールを結合した1つのHookを配置し、既存の別Hookには触れない。同名の旧ファイルは更新前にbackupする。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Install-PersistenceHook.ps1 -SavedGamesPath "C:\Users\hayat\Saved Games\DCS" -ConfigureHost
```
DCSを再起動し、更新した `.miz` を使用する。参加者側のHook配置は不要。
`-ConfigureHost` は既存autoexec.cfgをbackupし、管理用ブロックを追加する。再実行では内容が同じなら書き換えない。不完全・重複した管理ブロックや不正な文字コードでは変更を拒否する。DLSS等の既存設定、別Hook、MissionScripting.lua、保存済み成績は変更しない。
Hookだけを更新する場合は `-ConfigureHost` を省略できる。API未公開・接続拒否時はDCSログの `DynamicTrainingPersistence` とautoexec.cfgの許可を確認する。
`src/config.lua` の `persistence.enabled` でミッション側の接続を無効にできる。保存ファイルは削除しない。

## 確認

自動テストでrestart復元、遅延接続、重複精算／snapshot、古い確認、破損backup復旧、書き込み失敗、複数run、非サーバー無動作、停止時保存、UCID未照合、Immediate DEAD、死亡統計を確認する。
DCSでは150 / 90 / 0の精算後に保存済み表示を確認し、ミッション再開始とDCS再起動で同じUCIDの累計が戻ること、別UCIDの成績が混ざらないこと、Hookなしでは未保存表示になることを確認する。
接続時には `Connected via net.dostring_in(server)` をログへ1回記録する。Hookとホスト設定の更新は実装・模擬確認とし、この接続ログ・保存済み表示・再起動復元を確認するまでDCS動作確認済みとは記録しない。

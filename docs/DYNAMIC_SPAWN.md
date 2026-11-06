# Dynamic SpawnとMission Team

2026-11-06 / training-16。実装・模擬検証・保存済み.mizの設定検証を実施。実DCSでのDynamic Spawn画面、ネットワーク参加、動的生成機の実飛行・帰還採点は確認待ち。

## 出撃

MultiplayerでBLUEへ参加し、Dynamic Slotsから基地と機種を選ぶ。Incirlik / Akrotiri / Beirut / Ramat DavidはHornetとApache、空母はHornetに対応。1回に1機を生成する。Cold Startを維持し、機体在庫は対象機種ごとに無制限。同時機数の独自上限は設けず、DCSの駐機場・サーバー人数等の制約は受ける。

ユーザー指定で機体設定はDCS標準を使う。旧SOLO/MP2の18グループ・27 Client機を削除し、全9件のlinkDynTemplを0（テンプレートなし）へ変更した。旧原本の無線プリセット・データリンク・塗装・機体固有設定・搭載物は引き継がない。武装・燃料等は出撃画面や地上再武装で選ぶ。DCSが駐機位置を自動割り当てする。対象機種だけ個別unlimited=true、Cold Start、燃料・武器在庫を維持する。

Apacheの2人目は、新しく機体を生成せず、Spawn Slotsから生成済み機体の空席へ参加する。乗員全員が搭乗し、サーバーHookの識別情報が届いてからウィング作成・受注する。[ED公式のDynamic Spawnと乗員参加手順](https://forum.dcs.world/topic/352814-dynamic-spawn-guide/)

## F10で協力する

1. 全員が各自の機体へ搭乗する。ApacheのPLT/CPGも先に揃える。
2. 長機がDynamic Training → Create Mission Teamを選ぶ。
3. 僚機はJoin Mission Team <番号>: <長機名>を選ぶ。同じ機種の機体だけ参加できる。
4. Mission Team Statusで参加者を確認し、長機がTaskを受注する。
5. 公開ブリーフィング・座標・達成結果は登録した全グループへ配信する。Mission Statusは各自から確認できる。
6. 目標は共有し、帰還・喪失・Abort Sortie・150/90/0は各UCIDで精算する。Apache同乗者も個別参加者。

ソロはウィング作成不要。Apache同一機の人間乗員は、作成なしでも同じ任務を共有する。従来の同一DCSグループの共有も残す。

メンバーは受注時に固定。受注後の加入・脱退は拒否し、途中参加者へ目標達成や報酬を遡及しない。全員の精算/中止まで、参加する全DCSグループとUCIDをロックする。別ウィングは並行可能。長機グループのAbort Missionは共有任務全体、僚機は自分の名前を選ぶAbort Sortieを使う。長機を失っても未精算の僚機は継続できる。

任務終了後、同じ機体・乗員ならウィングを維持して次の受注ができる。Leaveで脱退し、長機がLeaveすると解散。受注前または任務終了後に機体・乗員が変わったウィングは解散する。再スポーン時は元任務の参加者を新機体へ差し替えず、前の出撃を精算/中止してから組み直す。既存SEAD保持サイトは長機の元DCSグループへ予約されるので、Follow-on DEADは同じ長機機体・ウィングでRTB/再武装して受ける。再スポーンを跨ぐサイト予約の移譲は行わない。

## 識別と採点

動的生成機にはME unitIdがない場合があるため、runtime object IDをslot IDへ推測変換しない。サーバーHookがSim/DCS.getUnitPropertyでネットワークslotの実ユニット名・グループ名・機種・runtime IDを解決し、UCID・player ID・席と組にして既存のmission/a_do_script経由で固定endpointへ送る。

ミッションは最大3秒の識別情報を使い、現在のネットワークUCID・陣営・席、実機の名前・グループ・機種・runtime IDを再照合する。Apache同一機内の席交換を許可する。不明・古い・曖昧な情報では他人のUCIDや表示名へ置換せず、ソロは明示的な無採点、Mission Teamの作成/加入は拒否する。静的スロットの従来照合は互換用に残す。

Hookは1秒間隔で識別情報を更新する。識別配信は成績ファイルI/Oから分離し、保存不能で他人の成績を使わない。席・接続情報は揮発データで、scores.datへは保存しない。Dynamic Spawn自体の導入時はschema4を維持した。現在はCAS追加によるschema5を使い、旧成績と採点率を維持する。Hookの配信には既存のuserhooks→mission API許可を使い、MissionScripting.luaは変更しない。

## サーバー更新

今回の.mizと更新したbuild/DynamicTrainingPersistenceHook.luaを組にして使う。新Hookはサーバーの使用中Saved Games/DCS.../Scripts/Hooksへ配置し、DCSを再起動する。標準機体設定への切り替え時はHook変更なしだったが、現在のtraining-17はCAS/schema5のためHook再導入とサーバーDCS再起動が必要。新PCではInstall-PersistenceHook.ps1 -SavedGamesPath <使用中フォルダー> -ConfigureHostを使う。[導入手順](PERSISTENCE.md#導入)

旧Hookでは動的生成機の識別配信ができないため、配置先が不明なサーバーへ自動導入済みとは扱わない。クライアントへのHook配置は不要。

## 移行と検証

ユーザーが2026-11-06に許可した限定例外として、scripts/configure_dynamic_spawn.pyでmission/warehousesの必要フィールドだけを変更した。既定は読み取り専用プレビュー、--applyで適用。変更前は.miz.dynamic-spawn.bakに保存し、既存バックアップの上書き・途中での外部変更・想定外レイアウトは拒否する。トリガー・敵・経路・天候・辞書・リソース対応表・ニーボードは保持する。標準設定への切り替えはユーザーの追加指定により--standard-aircraft --applyを使い、旧18グループ削除と9参照の解除だけを行った。直前バックアップは.miz.standard-spawn.bak。通常のLua更新は引き続きBuild→Sync→Check。

Test-DynamicPlayers.luaは実bundleで動的機体・人間乗員・別グループ共有・全任務・個人精算・異常系を模擬検証する。Test-DynamicSpawnMission.ps1は実.mizの5拠点・9機種選択・テンプレート参照なし・固定Clientなし・機種別無制限を検証する。test_dynamic_spawn_config.pyは標準設定移行の7ケース。DCS実機テストはTESTING.mdのMAN-69/70で別管理する。

距離の回帰検証には、削除直前の27駐機位置をscripts/Departure-TestFixtures.luaへテスト専用の参考点として保存した。実.mizのZone・車列経路・現在の空母位置と組み合わせて検査し、実際のDynamic Spawn駐機位置を保証するものではない。受注時の距離は引き続き操作中の機体の現在位置で判定する。

## training-17のCASとME再保存

ApacheだけにCASを追加し、動的機体の識別・Mission Team・乗員別採点を再利用する。CAS専用成績がschema5のため、training-16 Hookを使い続けず新しいHookをサーバーへ再導入してDCSを再起動する。既存の成績は通常の接続で継承する。

ME再保存後のwarehousesには標準カタログの有限在庫行が再生成されている。検証は9件の対応機種・基地の無制限在庫、テンプレート参照なし、Cold Startと、他行が無制限でないことを確認する。「出撃画面に9選択肢しか出ない」という保証はしない。CAS実装で倉庫は編集しない。

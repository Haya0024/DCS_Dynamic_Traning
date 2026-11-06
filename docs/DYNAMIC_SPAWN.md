# Dynamic SpawnとMission Team

2026-11-06 / training-16。実装・模擬検証・保存済み.mizの設定検証を実施。実DCSでのDynamic Spawn画面、ネットワーク参加、動的生成機の実飛行・帰還採点は確認待ち。

## 出撃

MultiplayerでBLUEへ参加し、Dynamic Slotsから基地と機種を選ぶ。Incirlik / Akrotiri / Beirut / Ramat DavidはHornetとApache、空母はHornetに対応。1回に1機を生成する。Cold Startを維持し、機体在庫は対象機種ごとに無制限。同時機数の独自上限は設けず、DCSの駐機場・サーバー人数等の制約は受ける。

従来の18グループ・27 Client機はME設定原本として残し、dynSpawnTemplateとテンプレート専用passwordを設定する。通常の固定枠として搭乗させず、9つのSOLOグループを各基地・機種のlinkDynTemplに割り当てる。MP2原本も保持するが、動的生成に2機グループとして使わない。配置座標・経路・初期の空パイロン・無線・機体固有設定を消さない。倉庫の全機種一括無制限を解除し、対象機種だけ個別unlimited=trueとする。燃料・武器在庫は既存設定を維持する。

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

Hookは1秒間隔で識別情報を更新する。識別配信は成績ファイルI/Oから分離し、保存不能で他人の成績を使わない。席・接続情報は揮発データで、scores.datへは保存しない。成績schema4、保存データ、採点率は変更しない。Hookの配信には既存のuserhooks→mission API許可を使い、MissionScripting.luaは変更しない。

## サーバー更新

今回の.mizと更新したbuild/DynamicTrainingPersistenceHook.luaを組にして使う。新Hookはサーバーの使用中Saved Games/DCS.../Scripts/Hooksへ配置し、DCSを再起動する。新PCではInstall-PersistenceHook.ps1 -SavedGamesPath <使用中フォルダー> -ConfigureHostを使う。[導入手順](PERSISTENCE.md#導入)

旧Hookでは動的生成機の識別配信ができないため、配置先が不明なサーバーへ自動導入済みとは扱わない。クライアントへのHook配置は不要。

## 移行と検証

ユーザーが2026-11-06に許可した限定例外として、scripts/configure_dynamic_spawn.pyでmission/warehousesの必要フィールドだけを変更した。既定は読み取り専用プレビュー、--applyで適用。変更前は.miz.dynamic-spawn.bakに保存し、既存バックアップの上書き・途中での外部変更・想定外レイアウトは拒否する。トリガー・敵・経路・天候・辞書・リソース対応表・ニーボードは保持する。通常のLua更新は引き続きBuild→Sync→Check。

Test-DynamicPlayers.luaは実bundleで動的機体・人間乗員・別グループ共有・全任務・個人精算・異常系を模擬検証する。Test-DynamicSpawnMission.ps1は実.mizの5拠点・9リンク・18原本・機種別無制限を検証する。test_dynamic_spawn_config.pyは移行の6ケース。DCS実機テストはTESTING.mdのMAN-69/70で別管理する。

# Air Interdiction（移動車列破壊）

仕様: 2026-10-17 / training-11。実装後のDCS実走行・実射は確認待ち。

## 受注・選定

F10 `Task: Air Interdiction`。既存Wing/UCIDロックと受注時の操縦中人間参加者を使い、最小機体番号の長機位置を基準とする。MEのTPL_AI_01～06の周回WP全点の南北・東西の最小/最大の中点（外接矩形中心）を各地域の案内点とする。WP密度に偏らない中心とし、Luaへ座標を複製しない。

中心までの水平距離で近い2地域を先に固定し、その中の使用可能な地域を等確率抽選する。片方使用中ならもう一方、両方使用不可なら生成・採点なしで解除する。3番目へ回さず、距離制限・空港所有権による選別はしない。受注後の長機交代・移動では再抽選しない。

地上でも即ACTIVE・生成。MEのLate Activation地上テンプレートをSPAWN:NewWithAliasで複製し、元の位置・車種・経路・速度・WPタスクを使う。原本は有効化しない。任務別aliasで並行Wingを分離し、1地域につき1Wing。3両・RED・地上・On Road・有効な周回指示を検証し、不正な地域は使用しない。欠落地域は他カテゴリを停止しない。分散無効化・停止・レーダー等の戦闘状態再設定は行わない。MEの車間距離・速度を維持する。各グループのユニット名は実データから取得し、末尾や連番に依存しない。

## 目的と終了

今回生成した3両すべての破壊でRTB_PENDING。損傷・停止・道路離脱・地域外移動・周回回数では達成/失敗にしない。受注時の3実体とIDを固定し、明示死亡または同一実体の死亡/Life0で数える。nil・例外・ID不一致・一覧欠落は破壊根拠にしない。第三者による撃破も数える。MP2は共有達成・個人精算とし、未達成帰還は任務継続。

帰還150、達成後事故90、達成前事故・Abort0。Air Interdiction Scoreを独立集計する。全員終了後に車列を削除し、実体削除の確認までは地域予約を維持して5秒ごとに再試行する。精算や他Wingは止めない。途中生成失敗は作成済み実体を回収してロックを解除する。進行・地域予約・車列は永続化しない。

## 画面表示

受注成功10秒、その直後に5行のブリーフィングをcoordinateBriefingSeconds（初期60秒）で1回。

```text
Air Interdiction mission accepted.
```

```text
AIR INTERDICTION MISSION
TARGET AREA: <周回WPの外接矩形中心、DDM・分の小数3桁>
OBJECTIVE: Destroy all 3 convoy vehicles; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

座標はCOORDINATE:ToStringLLDDMへLL_Accuracy=3を明示する。車列の現在位置・移動方向・個別座標・残数・隠れた予約情報を追加表示しない。Mission Statusは攻撃中に同じ公開済みブリーフィング、達成後は座標なしの次の本文だけ20秒。

```text
Air Interdiction Objective Complete
All 3 convoy vehicles destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

候補なしは `No available Air Interdiction routes among the two nearest sites. Try again later.` を20秒。準備失敗は `ERROR: Air Interdiction setup failed. See DCS log; select 'Task: Air Interdiction' to retry.` を20秒。個人精算・Abort・受注ブロックは既存共通文面でカテゴリ名Air Interdictionを使用する。移動開始・部分撃破・周回・散開・Cleanupの自動通知とスモーク機能は追加しない。

## 保存・導入

保存schema4にairInterdictionScoreを追加。schema1/2/3を各旧列数・checksumで厳密に読み、未収録項目を0で補う。未知schemaは拒否しprimaryを保護する。共有codecを結合したサーバーHookの更新とDCS再起動が必要。既存の保存データを開発作業で直接変更しない。

## 検証

Test-AirInterdiction.luaで模擬検証、Test-AirInterdictionMission.ps1で保存済み6経路の構成・全候補の生成/中心/周回指示保持/破壊/削除を検証する。実DCSでは2周以上の道路追従、橋・戻り区間、攻撃後の散開と復帰、GMT/FLIR捜索、3両破壊、MP2・並行Wing・帰還・Hook保存を確認する。

## 共通処理との境界（training-13）

既存の固定ID観測・native Group回収・Destroy後確認をObservations/ObjectLifecycleへ共通化した。地域予約、生成済みGroupの所有、5秒再試行はAirInterdictionに残し、ME経路と3両破壊の条件は維持する。REL-19はMP2で他5カテゴリと繰り返して予約・削除待ちが残らないことを確認する。

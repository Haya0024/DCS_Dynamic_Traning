# Air Interdiction（移動車列破壊）

仕様: 2026-10-17 / training-11。実装後のDCS実走行・実射は確認待ち。

2026-11-01 / training-15でApacheに対応。保存済みMEはTPL_AI_01〜10の10経路。Hornetは01〜06の6経路から長機より中心まで20〜100 NMの候補を使い、Apacheは全10経路のうち受注長機から中心まで3〜13 NMに絞って近い2候補を固定する。人間PLT/CPGも参加者固定・個別採点の対象。5〜12 NMから3〜13 NMへ変更し、4青空港すべての駐機位置で候補を確保した。距離と候補数は[APACHE.md](APACHE.md)を参照する。

## 受注・選定

F10 `Task: Air Interdiction`。既存Wing/UCIDロックと受注時の操縦中人間参加者を使い、最小機体番号の長機位置を基準とする。MEの選択対象TPL_AI_01～10の周回WP全点の南北・東西の最小/最大の中点（外接矩形中心）を各地域の案内点とする。WP密度に偏らない中心とし、Luaへ座標を複製しない。

中心までの水平距離で近い2地域を先に固定し、その中の使用可能な地域を等確率抽選する。片方使用中ならもう一方、両方使用不可なら生成・採点なしで解除する。距離でHornetは20〜100 NM、Apacheは3〜13 NMに絞ってから近い2地域を固定し、3番目へ回さず、空港所有権では選別しない。受注後の長機交代・移動では再抽選しない。

地上でも即ACTIVE・生成。編成未設定時はMEのLate Activation地上テンプレートをSPAWN:NewWithAliasで複製し、元の位置・車種・経路・速度・WPタスクを使う。原本は有効化しない。任務別aliasで並行Wingを分離し、1地域につき1Wing。3両・RED・地上・On Road・有効な周回指示を検証し、不正な地域は使用しない。欠落地域は他カテゴリを停止しない。分散無効化・停止・レーダー等の戦闘状態再設定は行わない。MEの車間距離・速度を維持する。各グループのユニット名は実データから取得し、末尾や連番に依存しない。

## 経路と編成の分離（2026-11-05）

経路候補は従来の`templates`、編成候補は`convoyTemplates`で別々に管理する。既定の`airInterdiction.convoyTemplates = {}`では追加抽選をせず、選んだ経路TPLの元の3両を生成する。現在の実.mizには編成専用TPLを追加していない。

編成を追加する場合は、MEでRED / Russia・地上・Late Activation・3両のグループを用意し、そのグループ名を候補に登録する。編成TPLの仮置き位置や経路は生成に使わないため、周回ルートの複製は不要。Apacheだけで使用する例：

```lua
-- config.airInterdiction.helicopter に追加。名前はME側と一致させる。
convoyTemplates = {
    "TPL_AI_TRANSPORT_3",
    "TPL_AI_MECHANIZED_3",
    "TPL_AI_ARMOR_3"
},
```

例示TPLは未配置。共通の`airInterdiction.convoyTemplates`に登録するとHornetとApacheの両方が使う。`helicopter.convoyTemplates`を省略すると共通候補を継承し、指定するとその候補だけを使う。明示的な空リスト`{}`はApacheだけ元の車列へ戻す。

受注時に従来どおり近い2地域から1地域を選び、その後に有効な編成を等確率で1つ固定する。候補の重複名は1候補として数える。欠落・非RED・地上以外・Late Activation無効・3両以外・車種未指定の編成はログへ記録して除外する。空でない設定で全候補が不正なら、元編成に切り替えず生成前に安全解除し、他カテゴリは継続する。

生成はMOOSEの`SPAWN:NewFromTemplate`を使う。経路TPLの国・陣営・グループ設定・全WPタスク・速度と、各車両の初期座標・向き・並びを維持し、同じ番号の編成TPL車両から車種・Skill等のユニット設定をコピーする。編成TPL側のグループ設定やWP上のオプションは使わない。車間距離・散開・周回指示を変える場合は経路TPL側を編集する。コピーは独立させ、両原本を変更しない。

編成と生成用データは計画時に固定し、生成・Mission Statusで再抽選しない。地域予約は引き続き経路名単位とし、異なる編成でも同じ道路へ重ねて生成しない。3両全滅・150/90/0・座標形式・公開メッセージ・Cleanupは従来どおり。編成名はDEBUGだけへ出し、捜索前の画面に敵車種を追加しない。

将来の4両以上・異なる撃破条件は今回の拡張に含めない。異なる車種を生成した際の道路追従・車体間隔・反撃・散開後復帰はDCS内確認が必要。

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
TARGET AREA: <周回WPの外接矩形中心。Hornet: DDM・分の小数3桁、Apache: MGRSの東4桁＋北4桁>
OBJECTIVE: Destroy all 3 convoy vehicles; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

HornetはCOORDINATE:ToStringLLDDMへLL_Accuracy=3、ApacheはToStringMGRSへMGRS_Accuracy=4を明示する。Apacheの表示は`MGRS 37S BV 1234 5678`のようにゾーン・グリッド識別子と東4桁＋北4桁を含み、先頭ゼロを保持して切り捨てる。受注時に機種の表示形式で確定し、Statusで再計算しない。車列の現在位置・移動方向・個別座標・残数・隠れた予約情報を追加表示しない。Mission Statusは攻撃中に同じ公開済みブリーフィング、達成後は座標なしの次の本文だけ20秒。

```text
Air Interdiction Objective Complete
All 3 convoy vehicles destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

Hornetの候補なしは `No available Air Interdiction routes among the two nearest sites within 20-100 NM. Try again later.` を20秒。準備失敗は `ERROR: Air Interdiction setup failed. See DCS log; select 'Task: Air Interdiction' to retry.` を20秒。個人精算・Abort・受注ブロックは既存共通文面でカテゴリ名Air Interdictionを使用する。移動開始・部分撃破・周回・散開・Cleanupの自動通知とスモーク機能は追加しない。

## 保存・導入

Air Interdiction導入時のschema4にairInterdictionScoreを追加した。現在はCAS追加によるschema5で継承し、schema1/2/3/4を各旧列数・checksumで厳密に読み、未収録項目を0で補う。未知schemaは拒否しprimaryを保護する。共有codecを結合したサーバーHookの更新とDCS再起動が必要。既存の保存データを開発作業で直接変更しない。

## 検証

Test-AirInterdiction.luaで模擬検証、Test-AirInterdictionMission.ps1で保存済み10経路と12 Apache駐機位置の構成・全候補の生成/中心/周回指示保持/破壊/削除を検証する。実DCSでは2周以上の道路追従、橋・戻り区間、攻撃後の散開と復帰、GMT/FLIR捜索、3両破壊、MP2・並行Wing・帰還・Hook保存を確認する。

## 共通処理との境界（training-13）

既存の固定ID観測・native Group回収・Destroy後確認をObservations/ObjectLifecycleへ共通化した。地域予約、生成済みGroupの所有、5秒再試行はAirInterdictionに残し、ME経路と3両破壊の条件は維持する。REL-19はMP2で他5カテゴリと繰り返して予約・削除待ちが残らないことを確認する。

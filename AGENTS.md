# DCS Dynamic Training

## 目的

DCS World の Syria マップ上で動作する、
永続型のダイナミック訓練サンドボックスを作成する。

このプロジェクトは陣取り型キャンペーンではなく、
Intercept、SEAD、DEAD、Strike、CAS、Anti-Ship などの訓練ミッションを
動的に生成することを主目的とする。

---

## 使用環境

- DCS World
- Syria マップ
- MOOSE Framework
- プレイヤー機体: F/A-18C Lot 20
- BLUE Coalition: USA
- RED Coalition: Russia

---

## BLUE プレイヤースロット

以下の Client スロットを使用する。

- `BLUE_HORNET_INCIRLIK_01`
- `BLUE_HORNET_AKROTIRI_01`
- `BLUE_HORNET_BEIRUT_01`
- `BLUE_HORNET_RAMAT_01`

プレイヤーは任意の BLUE 空港から出撃できる。

空母スロットと MP2（Client ×2）も使用する。MP2 は INCIRLIK / AKROTIRI / BEIRUT / RAMAT / SC に配置済み。
列挙した名前を検出ロジックの条件にせず、搭乗中の BLUE F/A-18C をグループ単位で取得する。

プレイヤー機の初期パイロン設定は意図的に空とする。
プレイヤーが地上で再武装を要請し、好きな兵装を搭載する運用とする。
スクリプトで兵装を固定せず、空の初期設定を不備として扱わない。

スクリプト側では特定の空港を固定せず、
現在操作中のプレイヤー機を動的に取得すること。

---

## 現在の Intercept テンプレート

グループ名と構成:

| グループ名 | 構成 |
|---|---|
| `TPL_INT_MIG29A_2` | MiG-29A ×2 |
| `TPL_INT_SU27_1` | Su-27 ×1 |
| `TPL_INT_MIG29A_1` | MiG-29A ×1 |

共通設定:

- RED / Russia
- Late Activation 有効
- Airborne Start
- CAP Task

これらのグループは実際の初期配置用ではなく、
動的スポーン用のテンプレートとして使用する。
候補は `src/config.lua` の `intercept.templates` で管理し、任務生成ごとに等確率で1つ選ぶ。
任務名は Intercept。生成候補は ME に登録済みの `TPL_INT_...` のグループ名に一致させる。
ME で名前を変更した場合は設定と仕様書も合わせる。機種・機数は生成した実機から取得し、表示・完了判定に使う。

---

## Intercept ミッションの基本動作

プレイヤーが F10 メニューから
`Generate Intercept` を選択したとき、以下の動作を行う。

### プレイヤーがすでに空中にいる場合

即座に Intercept ミッションを開始する。

### プレイヤーが地上にいる場合

Intercept ミッションを待機状態にする。

受注時の搭乗者を参加者として固定し、全参加者の離陸を検出したら、
20秒待ってから、その時点の長機位置・機首方向を基準に Intercept ミッションを開始する。
全員が受注時から空中なら即生成する。長機は搭乗中の参加者の機体番号が最も小さい機体。
離陸は2秒間隔で判定するため、全員の実際の離陸から生成までは約20～22秒となる。
予約したプレイヤー機を保持し、AI 僚機や未参加者の離陸では開始しない。
生成前に参加者が着地した場合は離陸待ちに戻し、死亡・離脱・機体変更時は予約全体を解除する。

### 敵機生成条件

初期仕様では以下とする。

- プレイヤー現在位置から 60～80 NM
- プレイヤー機首方向から左右60°以内の方位をランダム化
- 敵は HOT aspect（実際の生成位置からプレイヤーへ向く）
- 敵の編隊形状は WEDGE / LINE_ABREAST / TRAIL / ECHELON_LEFT / ECHELON_RIGHT を生成ごとに等確率で選ぶ
- 編隊候補と間隔は `src/config.lua` に置く。MOOSE の固定翼 Open を初期値とし、`GROUP:SetFormation` と初期ウェイポイントへ適用する
- 高度は一定範囲からランダム
- 生成には `intercept.templates` の3候補から各1/3の確率で選んだテンプレートを使用する

Interceptの地上受注通知は人数と全員離陸待ちに絞る。20秒の生成待ちは全員の離陸検出時に1回、詳細な開始表示は生成成功時に1回だけ出し、通常の監視やメニュー更新で再掲しない。

将来的には以下を追加する。

- 方位範囲を側方・後方へ拡張
- 高度差
- 機種・機数の候補拡張、難易度に応じた編成
- 複数編隊
- FLANK / BEAM / COLD aspect
- ECM
- 敵 AWACS
- 複数方向からの攻撃

---

## Intercept ミッション終了条件

生成した敵航空機をすべて撃墜した場合、
Primary Objective Complete とする。

撃墜完了後も即座に完全終了とはせず、
BLUE 空港への RTB を追加評価対象とする。

例:

- 敵全滅: Mission Success
- BLUE 空港へ帰還: RTB Bonus
- 生還: Bonus
- ノーダメージ: Bonus

---

## SEAD 訓練ミッション（実装済み・ゲーム内確認待ち）

- `TPL_SEAD_SA6`（レーダー＋発射機3両）と `TPL_SEAD_SA8`（1両）を等確率で選ぶ。
- Zone は `SEAD_ZONE_PALMYRA` / `SEAD_ZONE_SALAMIYAH` / `SEAD_ZONE_DUMAYR` / `SEAD_ZONE_TABQA`。
- `Generate SEAD` の受注時に TOO / PB を等確率で抽選し、SAM・Zone・任務IDを固定する。距離は受注時の長機位置からZone中心まで40～130 NMで判定する。
- 地点選定は `PLANNING` として段階的に行う。安全な実配置予定点を先に固定し、TOOではそこから3～5 NMずらした捜索座標、PBでは1～3 NMずらした推定点とコード（SA-6:108、SA-8:117）を渡す。
- TOOの `THREAT AREA` は捜索座標を表示し、機種はUNKNOWNとする。機種・正確な座標・PBコードを開始表示と状態表示の両方で隠す。PBも正確な実配置座標は表示しない。
- TOOの捜索座標とPBの推定座標はDDM（度＋小数分、分の小数3桁）で計画確定時とMission Statusに表示する。MOOSEのToStringLLDDMへ精度3を明示し、全体の表示設定から独立させる。
- SEADの座標付きブリーフィングは計画確定時に1回だけ自動表示する。受注直後は方式と計画中の通知、生成時は短い開始通知とし、離陸待ち・カウントダウン再開・監視で座標を再掲しない。Mission Statusでは同じ計画情報を任意に再確認できる。
- SEAD / DEADの座標付きブリーフィングと座標を含むMission Statusは共通設定 `coordinateBriefingSeconds`（初期60秒）で表示時間を決める。
- 計画と実体生成を分離する。受注時から全員が空中なら計画確定後に生成、地上受注なら全登録者の離陸後20秒で生成する。生成時に計画を再抽選しない。
- LAND、半径200 m内の標高差20 m以内、各車両が建物・障害物から200 m以上離れることを検査する。
- 選択した1 Zoneだけを最大50回試し、不合格なら任務を安全に解除する。別Zoneに変更しない。検査は1秒ごとに最大2候補。
- 試行上限での失敗時は拒否理由の件数と早期拒否までに観測した高低差を画面・ログへ出す。TOOの機種・正確な位置・PBコードを画面に出さない。
- 未生成の他ウィングの配置予定点とも離隔を取る。生成直前に同じ予定点を再検査し、塞がっていたら別地点に変更せず失敗解除する。
- `src/sead.lua` に配置ロジック、`src/config.lua` の `sead` に設定を置く。
- `SpawnFromVec2` で地上配置し、SAM を戦闘状態・停止状態にする。
- SEAD と Intercept は同じウィング・UCID の受注ロックを共有する。
- 主要レーダーの状態を `ACTIVE` / `SUPPRESSION_PENDING` / `SUPPRESSED` / `DESTROYED` の遷移表で管理する。SA-6 は `Kub 1S91 str`、SA-8 は `Osa 9A33 ln`。破壊は即達成、生存中は開始時Lifeより減少＋Radar OFF連続60秒で達成。無傷OFFやLife残量だけでは達成しない。再発信・観測失敗でタイマーをリセットする。
- `src/sead_objective.lua` に判定を分離し、成功後は再判定を停止する。`sead.suppressionHoldSeconds` に60秒を集約する。
- `sead.templates` の `name` / `type` / `pbCode` / `primaryUnitType` に対応をまとめる。TypeNameは `.miz` で確認済みの値を使い、複数の主要レーダーがある場合は全対象の破壊または損傷＋OFF継続時間達成を要求する。
- 満額は `sead.fullReward = 150`。目標達成後の帰還成功で各自150、墜落・死亡・脱出で90、達成前の事故・任意中止は0。UCID ごとの既存帰還評価と重複防止を使う。
- Total Score / Career Points / SEAD Score を更新し、Intercept Score と分ける。UCID累計はサーバーHookで保存・復元する。未接続時はセッション内のみ。
- 目標達成時にSAM Groupを削除しない。Siteのdispositionは初期CLEANUP。保持を選ばなければ全参加者終了後に独立した `src/sead_sites.lua` へ削除を依頼し、失敗時は参照を保持して再試行する。Siteは `Missions.sites` に置き、残存車両の追加撃破はSEAD報酬に影響しない。
- 仕様変更では先に `docs/SEAD.md` と `docs/DEAD.md` に状態遷移と終了方針を書く。
- 仕様は `docs/SEAD.md`、模擬検証は `scripts/Test-SEAD.lua` を参照する。

## SEAD → DEAD follow-on（実装済み・ゲーム内確認待ち）

- DEADは既存SEAD Siteの継続任務だけ。種類は同SortieのImmediate DEADと、明示保持・SEAD精算後の次Sortieで取得するFollow-on DEADの2つとする。
- `Generate DEAD` はpreserved Siteがある場合だけ成立する。候補なしでは `No preserved SAM sites available for DEAD.` を表示して終了し、新規ランダムSAM Siteは生成しない。
- 同じ生成済みSAM Groupと実際の残存・損傷・発信状態を使う。DEADのためにSpawn、抽選、Life復元、Radar再設定を行わない。
- SEAD達成後の残存Siteにだけ同階層の `Continue as DEAD` / `Preserve Site for DEAD` を一時表示する。古いcallbackは任務・Site・参加者を再照合する。
- `record.primaryResult` / `site.primaryResult` はレーダーだけのSUPPRESSED/DESTROYED結果。Site全滅とは分離する。完了通知は `site.seadCompleted`、残存数は `SEADSites.CountAliveSiteTargets` と `site.remainingTargetCount` で管理し、DEAD可否をPrimary結果の値から決めない。SA-6レーダー破壊後も生存Launcherが1両以上あれば継続可能、Suppressed時は生存レーダーも対象、全残存対象0でDEAD不可。
- Immediateは同じSEAD recordを `RTB_PENDING → DEAD_ACTIVE → RTB_PENDING` とし、新規Acquireは行わない。SEADの結果・任務IDを維持し、Continue時に満額と追加DEAD採点用IDを固定する。両目標達成＋帰還はSEAD150＋DEAD150、両目標達成後事故は各90、DEAD未達成事故はSEAD90／DEAD0、任意中止は両方0。精算済み・途中終了者への遡及採点をせず、追加DEADはscoreOnlyとして任務・帰還等の統計を二重に数えない。
- Preserveを明示選択した場合だけRETAINとし、最初の選択時の `retainedAt` を保存する。通常は元SEADの全員終了（精算・中止・喪失）までSiteを予約し、終了後は予約を解除してGroupを残す。ただし残存対象の全滅・保持者の切断が確認されたSiteはCleanupする。残存観測不能を全滅とはみなさない。予約解除後の保持Siteは別ウィングもGenerate DEADで取得できる。
- Continue時には以前の着陸確認を解除するが、Immediate DEAD未達成でもその後の着地からSEAD帰還評価を行う。帰還成功はBLUE基地・対応空母で5 knots以下を連続10秒維持して確定し、その時点でDEAD未達成ならSEAD150／DEAD0で個別終了する。未精算の僚機は継続可能。確認中のDEAD達成では着陸タイマーを維持し、帰還確定前の達成なら各150。復行時は現在のphase（未達成ならDEAD_ACTIVE、達成後ならRTB_PENDING）へ戻す。全員終了でIN_USE SiteをCleanupし、精算済み参加者へ遡及採点しない。
- Preserve時点で未精算かつ操縦中の登録参加者のうち、機体番号が最小の長機を保持者として固定する。UCIDで接続喪失が確認されたRETAIN SiteをCleanupする。UCID未照合なら取得済み接続player IDを使い、観戦・スロット変更を切断扱いしない。元SEAD精算前でもSite予約だけ解除し、採点・Wing/UCIDロックは維持する。DEADでIN_USEになったSiteは保持者切断Cleanupの対象外。接続APIの結果が不明なら切断を根拠とする削除を行わず、削除失敗は再試行する。
- RETAINは同じミッション実行中の次Sortie向け保持であり、Site・生成Group・進行中任務はミッション再開始／サーバー再起動後に復元しない。永続保存するのはUCIDごとの精算済み成績だけ。
- 通常の `Generate DEAD` は予約なしのRETAIN Siteから長機に最も近いものを取得。既存のWing/UCID排他とSite予約を併用し、準備失敗では予約とロックをrollbackする。
- Follow-on DEADは新しいDEAD recordをAcquireし、受注時の生存RED ground targetsを固定。地上ならARMED、全員離陸検出でACTIVEへ移行する。既存SAMを隠さず、20秒のSpawn待ちは設けない。
- DEAD全対象破壊でRTB_PENDING。両DEADの満額は `dead.fullReward = 150`、達成後事故90、達成前事故・Abort0。DEAD Scoreへ独立加算し、既存Recovery/Scoringを使う。
- Site/DEAD対象のIsAliveはtrue=生存、false=死亡、nil=観測不能とする。未確認対象のnil・例外・不正値・ID不一致を全滅根拠にせず、Site残数は不明・継続候補から除外、DEADは残存側に数える。観測不能ログは移行時だけ記録する。明示死亡のlostを優先し、Group一覧欠落だけでも既知対象を全滅扱いしない。
- Follow-on DEADのSITE LOCATIONは元Site実配置点をDDM・分の小数3桁で表示する。Estimated表現は使わず、SEAD TOO/PBの推定点と秘匿表示は維持する。
- 全員終了時にIN_USEならCLEANUPへ倒す。明示RETAIN以外はCleanupが標準。保持timeout・明示削除メニュー・Siteの永続化は未実装。プレイヤー成績の保存とは分ける。
- 責務は `src/dead.lua`（選定・対象・判定・briefing）、`src/sead_sites.lua`（Site寿命・予約・Cleanup）、`src/sead_objective.lua`（従来のSEAD FSM）で分離する。
- 仕様は `docs/DEAD.md`、模擬検証は `scripts/Test-DEAD.lua`。既存5 LuaスイートとBuild/Syncテストも通す。

---

## 難易度システム

難易度は 1～5 の5段階とする。

例:

- Difficulty 1: Training
- Difficulty 2: Easy
- Difficulty 3: Normal
- Difficulty 4: Hard
- Difficulty 5: Expert

単純に敵数だけを増やすのではなく、
Threat Budget を使用して難易度を構成する。

例:

- MiG-21 = Threat Cost 1
- MiG-29 = Threat Cost 2
- Su-27 = Threat Cost 3
- Su-30 = Threat Cost 4

Difficulty ごとに使用可能な Threat Budget を決め、
その範囲内で敵編成を生成する。

難易度には以下も影響させる。

- 敵数
- 機種
- AI Skill
- 初期距離
- 高度差
- 敵編隊数
- Aspect
- ECM
- AWACS 支援
- 情報量

---

## ポイントシステム

各ミッションに Score を設定する。

基本報酬は Threat Budget や Difficulty を基準に算出する。

評価対象の例:

- Primary Objective 完了
- RTB 成功
- 生還
- ノーダメージ
- Optional Objective 完了
- Friendly Loss
- Friendly Fire
- Mission Abort
- Player Death

単純な撃墜数だけではなく、
安全に帰還することも高く評価する。

### 確定した採点方針

- プレイヤー成績のキーは UCID とし、プレイヤー名・機体名を永続成績のキーにしない。
- 任務クリア後、味方飛行場または味方空母への帰還成功で満額の100%を付与する。
- クリア後、帰還成功の確定前に墜落・死亡・脱出した場合は満額の60%を付与する。着陸進入中に限定しない。
- 未クリアの墜落・死亡・脱出ではクリア報酬を付与しない。
- 精算は任務IDと開始時の UCID に対応付け、一度だけ実行する。
- UCID を取得できない場合、表示名や仮の UCID へ自動的に置き換えて採点しない。
- 採点・帰還評価は `docs/SCORING.md` を参照する。満額150ポイント、帰還失敗90ポイント。サーバーHook導入時は保存済み累計を復元し、未接続／保存待ち／保存済みを区別する。

### ウィング共有任務と受注ブロッカー

- 同じグループの受注時の人間全員で1任務を共有する。空席・AI・途中参加者は参加者に追加しない。
- 目標達成は共有し、帰還評価・事故・精算は参加者ごとに扱う。満額は各自150ポイントで分割しない。
- クリア前に死亡・個人中止した参加者は0ポイントを維持し、生存する僚機は任務を継続できる。
- 先に帰還した参加者へ先に加算する。全参加者の精算または中止まで任務と受注ロックを維持する。
- `src/missions.lua` の `Missions.Acquire` を予約・生成より前に使う。ウィング名と登録 UCID で二重受注を拒否する。
- 参加者が別スロットへ移動しても、元のウィングが終了するまでは新たな受注を拒否する。
- 任務はカテゴリを問わずウィングごとに同時に1件。別ウィングはそれぞれ別の任務を同時に進められる。BLUE 全体の1件制限は設けない。
- 状態は `Missions.wings[groupName]` に集約し、`category` で Intercept / SEAD / DEAD を区別する。Immediate DEADはSEAD内のphase。敵・イベント・タイマー・終了処理は対象ウィングの任務だけに適用する。
- 同じテンプレートから生成する敵は `SPAWN:NewWithAlias` と受注ごとの識別子で名前を分離し、テンプレート名は変更しない。
- F10 はグループ共有。`Abort Mission` は全体中止、名前・機体を指定する `Abort Sortie` は個人中止。
- 詳細は `docs/WING.md`。結合後に `scripts/Test-Wing.lua`、`scripts/Test-ParallelWings.lua` と既存の Intercept・採点テストで確認する。

---

## Career Points

各ミッションの Score とは別に、
永続的な Career Points を持つ。

Career Points はサーバー再起動後も保存する。

将来的には以下の情報を保存する。

- Total Score
- Career Points
- Mission Count
- Success Count
- Failed Count
- Abort Count
- Death Count
- RTB Count
- A/A Kill Count
- Ground Kill Count

---

## カテゴリ別レーティング

将来的にミッションカテゴリごとの成績を保存する。

例:

### Air-to-Air

- Intercept
- ACM

### Air-to-Ground

- SEAD
- DEAD
- Strike
- CAS

### Naval

- Anti-Ship
- Carrier Operations

例:

Intercept: 1820
SEAD: 1640
Strike: 1050
CAS: 720

---

## Persistence

永続化対象は、
戦線や陣地所有権ではなくプレイヤー進行状況を中心とする。

保存候補:

- Career Points
- Total Score
- 各カテゴリ Rating
- Mission Statistics
- Success / Failure
- Death
- RTB
- Kill Statistics
- 推奨 Difficulty

成績保存は `docs/PERSISTENCE.md` を参照する。実装済み・DCS内確認待ち。

- ミッション側のio / lfsをunsanitizeしない。サーバーのSaved Games Hookがnet.dostring_in("server", code)でデータのみを受け渡し、固定schemaの `DynamicTraining/scores.dat` と正常backupを管理する。Hook環境のa_do_scriptは使わない。型付き文字列返信を検証し、通信例外・API拒否・不正返信を保存成功にしない。
- `src/score_data.lua` はschemaとcodec、`src/persistence.lua` はsnapshotと復元・確認通知、`server/score_store.lua` は検証付き保存・復旧、`server/DynamicTrainingPersistenceHook.lua` はサーバーcallbackを担う。
- UCID累計・カテゴリ別Score・任務／帰還／失敗／中止／出撃喪失数を保存する。進行中任務・Wingロック・SAM Siteは保存しない。
- run番号を保存してから復元する。遅延接続前の精算差分は1回だけ統合する。snapshotの再送は累計置換で、保存revisionの確認前に保存済みと表示しない。
- dual corruptionではゼロで上書きしない。I/O失敗はゲームを止めず保存未確認として再試行する。Immediate DEADの追加Scoreでは任務・死亡統計を増やさない。
- Hookは `scripts/Build-PersistenceHook.ps1` で結合し、`scripts/Install-PersistenceHook.ps1 -SavedGamesPath <DCSユーザーディレクトリ>` で配置する。導入・更新後はDCS再起動が必要。MissionScripting.luaと他Hookを変更しない。
- ホスト導入時はinstallerに `-ConfigureHost` を付け、autoexec.cfgへuserhooksからserverへのAPI許可だけを追加する。既存設定・許可を維持し、変更前にbackup、再実行はidempotent。不完全・重複管理ブロックや不正文字コードでは変更を拒否する。
- Lua7スイート、Build/Sync、`scripts/Test-PersistenceInstall.ps1` を検証する。専用fixture以外の保存データをテストで変更しない。

---

## 将来追加するミッション

以下を順次追加する。

- Intercept
- ACM
- SEAD
- DEAD
- Strike
- CAS
- Anti-Ship
- Escort
- Navigation
- Carrier Case I
- Carrier Case III

---

## F10 メニュー構成

将来的には以下のような構造を目指す。

Dynamic Training
- Generate Mission
  - Air-to-Air
    - Intercept
    - ACM
  - Air-to-Ground
    - SEAD
    - DEAD
    - Strike
    - CAS
  - Naval
    - Anti-Ship
- Difficulty
  - 1 Training
  - 2 Easy
  - 3 Normal
  - 4 Hard
  - 5 Expert
- Mission Status
- Abort Mission
- Player Statistics

---

## コーディング方針

以下のルールを守ること。

- gameplay ロジックをモジュール分割する
- プレイヤー空港をハードコードしない
- 現在操作中のプレイヤーを動的に検出する
- プレイヤー向け表示は NM / ft / knots を基本とする
- 設定値とロジックを分離する
- Intercept、SEAD、Strike などを独立モジュール化する
- ミッション状態を一箇所で管理する
- 同一ミッションを二重生成しない
- Debug 用メッセージを明確にする
- エラー時にはゲームを止めず、可能な限りログと画面表示を残す
- `.miz` のミッション設定・トリガー・リソース対応表を直接編集しない。例外として、登録済みの埋め込み Lua は `scripts/Sync-Mission.ps1` による同期を許可する
- Mission Editor で設定したテンプレート名を勝手に変更しない
- MOOSE の API を優先して使用する
- DCS 標準 Lua API と MOOSE API を混在させる場合は理由をコメントする

---

## ファイル構成

初期構成:

DCS-Dynamic-Training/
- AGENTS.md
- README.md
- docs/
  - DESIGN.md
- src/
  - main.lua
  - intercept.lua
  - config.lua
- mission/
  - DynamicTraining_Syria.miz
- vendor/
  - MOOSE/
    - Moose.lua

将来的に以下を追加する。

- difficulty.lua
- scoring.lua
- persistence.lua
- player.lua
- sead.lua
- strike.lua
- cas.lua
- antiship.lua

---

## 開発ルール

機能追加は一度に大きく進めず、
小さい単位で実装・確認する。

### 機能別仕様書

- 機能単位の仕様書を `docs/<機能名>.md` に作成する。Intercept は `docs/Intercept.md`、SEAD は `docs/SEAD.md`、DEADは `docs/DEAD.md` を参照する。
- 仕様書では、現在の実装・既知の制約・将来仕様を区別する。
- 機能の動作や設定値を変更したら、対応する仕様書も同じ作業で更新する。
- コードに実装済みであることと、DCS 内で動作確認済みであることを区別して記録する。

### テスト仕様書

- テストの構成・条件・期待結果・実行方法・DCS内の確認手順は `docs/TESTING.md` にまとめる。
- 自動テストを追加・変更したら、対応表・件数・機能仕様書の検証範囲を同じ作業で更新する。
- 模擬テストの通過とDCS内での確認済みを区別する。手動結果には対象版・設定・テストID・実測結果を記録する。

### Lua と .miz の同期

- `src/*.lua` と `vendor/MOOSE/Moose.lua` を編集元とする。設定値は `src/config.lua` に集約する。
- `scripts/Build-Mission.ps1` が設定・保存データcodec・プレイヤー・採点・永続化bridge・任務ロック・Intercept・SEAD目標判定・SEAD配置・サイト管理・DEAD・帰還評価・実行部分を `build/DynamicTraining.lua` に結合する。生成物を直接編集しない。
- 保存codecまたはserver側Luaを変更したらHookも再結合し、導入用bundleと保存テストを確認する。導入済みHookの更新にはinstallerとDCS再起動を使う。
- Codex は上記 Lua を変更したら、作業完了前に必ず以下を順に実行し、`mission/Syria.miz` も更新する。
  1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1`
  2. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -Check`
- 同期・確認に失敗した場合は、反映済みと報告せず理由を伝える。
- 同期は既存の埋め込み Lua の置換に限定する。その他の ZIP エントリの内容が変わらないことを検証し、置換前の `.miz.bak` を残す。
- `src` 内のモジュールは既存の埋め込み `DynamicTraining.lua` に結合して同期する。この方式では ME の追加設定は不要。結合順は `scripts/Build-Mission.ps1` で管理する。
- 新しい独立した埋め込み Lua の登録や DO SCRIPT FILE の読み込み順変更は Mission Editor で行う。未登録の ZIP エントリを自動追加しない。
- ユーザー自身が編集する場合の自動同期は `-Watch` または VS Code の `DCS: Watch mission Lua` タスクを使用する。
- 同期後に ME から実行する場合は `.miz` を開き直す。実行中のミッションへの反映には再開始が必要。

現在の優先順位:

1. MOOSE 読み込み
2. F10 メニュー表示
3. プレイヤー取得
4. 地上 / 空中判定
5. 離陸検出
6. Intercept 敵機スポーン
7. 敵ルート設定
8. 敵全滅判定
9. Mission Complete
10. Difficulty
11. Score
12. Persistence
13. 他ミッション追加

各段階で動作確認してから次へ進むこと。

---

## 現在の状態

以下はすでに確認済み。

- MOOSE 読み込み成功
- `DynamicTraining.lua` 読み込み成功
- F10 `Dynamic Training` メニュー表示成功
- 名称変更前の任務は、ユーザーからゲーム内で動作しているとの報告あり（個別ケースの確認範囲は未記録）
- BLUE 側 F/A-18C Client slot を4空港に配置済み
- RED 側の Intercept template 3種類（MiG-29A ×2、Su-27 ×1、MiG-29A ×1）を `.miz` 内で確認済み

次の DCS 内での動作確認対象:

名称変更後の `Generate Intercept`、開始・完了・状態・採点表示。

`Generate Intercept` 選択時に、

- 全参加者が空中なら即 Intercept Spawn
- 地上の参加者がいれば全員の離陸待ち
- 全員の離陸検出から20秒後に Intercept Spawn（生成時点の長機位置・機首方向を使用）

上記処理は `src/DynamicTraining.lua` に実装済み。今回修正した前方位置・経路の計算も含め、ゲーム内で段階的に確認する。

追加の DCS 内での確認対象（コード・模擬テストは実装済み）:

- マルチプレイで対象 Client スロットの UCID を取得できること
- 各グループの F10 メニューが対象プレイヤーの任務を開始すること
- 敵全滅後は帰還待ちに移り、味方基地・空母で5 knots以下を連続10秒維持すると150ポイントを付与すること
- クリア後の墜落・死亡・脱出では90ポイントを一度だけ付与すること
- `Player Statistics` に累計・Death Count・保存状態を表示し、Hook導入時は保存済み成績が再起動後に戻ること（DCS内確認待ち）
- MP2 の2人で受注し、全員離陸待ち・個別帰還・長機喪失後の継続・個人中止・二重受注ブロックが動作すること
- 複数ウィングが同時に受注でき、各ウィングの目標・帰還・中止・ロック解除が他の任務に影響しないこと
- 敵の5種類の編隊指定を接敵前に確認すること（初期相対座標はテンプレートから継承し、AI が指定形状へ移行する）
- 敵テンプレート3種類の抽選、実際の機種・機数の表示、1機・2機編成それぞれの全滅判定を確認すること（模擬テスト済み）
- SEAD標準Cleanup、Continueで同SiteのImmediate DEAD、Preserve後の別SortieでFollow-on DEADを確認すること
- 元SEAD全員終了までのSite予約、最寄りRETAINの取得、別Wingの二重取得拒否、DEAD150/90/0とImmediateのSEAD＋DEAD採点・任務数1件を確認すること。詳細な手順は `docs/DEAD.md` と `docs/TESTING.md` を参照する

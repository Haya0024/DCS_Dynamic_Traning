# SEAD → DEAD follow-on仕様

更新日: 2026-10-07

画面メッセージ・DCSログの本文、タイミング、表示時間は [MESSAGES.md](MESSAGES.md) を参照する。
Follow-on DEADの通知はSEADと同じ流れにする。準備成功後に短い `DEAD mission accepted.`（10秒）、受注時の座標付きブリーフィング（60秒設定）を1回、ACTIVE移行時は座標を含まない `DEAD TRAINING START` と目標・RTB指示（25秒）を出す。地上受注後の離陸でもブリーフィングを自動再掲しない。予約待ち・開始時の残数などはDEBUGへ記録し、Statusでは座標・残数を任意確認できる。

## 目的と実装境界

DEADは必ず既存SEADで生成されたSAM Siteを引き継ぐ継続任務とする。種類は次の2つだけ。

- Immediate DEAD: SEAD Primary完了後、同じSortieで `Continue as DEAD` を選び、同じSiteを攻撃する。
- Follow-on DEAD: `Preserve Site for DEAD` → SEADのRTB・精算 → 次Sortieの `Task: DEAD` で、保持したSiteを取得して攻撃する。

`Task: DEAD` はpreserved Siteがある場合だけ成立する。候補がなければ `No preserved SAM sites available for DEAD.` と表示して終了する。
新しいランダムSAM Siteを生成するDEADは実装対象外。
元のGroup、損傷、発信状態、残存車両を継承する。Spawn・機種抽選・Zone抽選・Life復元・Radar再設定は行わない。
標準は `CLEANUP`。後で使うSiteだけプレイヤーが明示的に `RETAIN` を選ぶ。
Preserveは保持元ウィング専用のサイト予約とする。SEADのRTB・精算後も保持予約を維持し、同じウィングが再武装後にTask: DEADで取得する。`Release Site Reservation` を明示選択した場合だけ、同じSiteを他Wingにも開放する。
実装と模擬テストを確認してから結果を記録する。DCS内での確認は別途必要。

## 責務

| 構成 | 責務 |
|---|---|
| `Missions.wings` / `Missions.pilots` | 1Wing・登録UCIDにつき1任務の排他、参加者固定 |
| `Missions.sites` / `SEADSites` | Site参照、残存状態、保持・予約・Cleanup |
| `SEADObjective` | 従来のエミッター4状態とSEAD達成結果の確定 |
| `DEAD` | 最寄り保持Siteの選定、対象snapshot、全滅判定、briefing |
| `Recovery` / `Scoring` | 既存の個別帰還・事故評価と一度だけの精算 |
| Runtime / Menu | 受注・phase遷移・イベント配送・signatureによるF10再構成 |

## Site lifecycle

### SEAD Primary ResultとSite状態の分離

`record.primaryResult`（Siteへ保存する`site.primaryResult`も同様）は主要レーダーだけの確定結果で、`SUPPRESSED` / `DESTROYED`を保持する。SAM Site全体の全滅を意味しない。
SEAD完了済みかどうかは`site.seadCompleted`、実際の生存RED ground車両数は`site.remainingTargetCount`で別々に管理する。
`SEADSites.CountAliveSiteTargets(site)`はSpawn済みGroupの実ユニットから生存数と対象リストを取得する。MEテンプレートの車両数を使わない。
Primary結果の値から残存数・DEAD可否を推測しない。SEAD完了済み・Site未使用・Cleanupなしという既存条件を満たす場合、残存が1両以上なら`followOnAvailable=true`、0ならfalse。
観測できない場合は残存数を不明とし、全滅と誤認しない。既存の予約・削除・ログアウトCleanup条件は維持する。

| 実際の状態 | SEAD Primary結果 | Site状態 | 残存数 | DEAD対象 |
|---|---|---|---:|---|
| SA-6の1S91破壊、2P25が3両生存 | DESTROYED | SUPPRESSED | 3 | 生存Launcherのみ |
| SA-6の1S91破壊、2P25が1両生存 | DESTROYED | SUPPRESSED | 1 | 生存Launcherのみ |
| SA-6の1S91損傷＋OFF60秒、全4両生存 | SUPPRESSED | SUPPRESSED | 4 | 生存レーダー＋Launcher |
| SA-6の1S91と全2P25を破壊 | DESTROYED | DESTROYED | 0 | DEAD不可 |
| SA-8のOsaを破壊 | DESTROYED | DESTROYED | 0 | DEAD不可 |

残存ありならImmediate DEADとPreserveの両方を利用可能とし、DEAD開始時点の生存対象だけをsnapshotする。全snapshot対象の破壊でDEAD達成とする。

`SEADSites.Register(record)` は以下を `Missions.sites[site.id]` に登録する。

| フィールド | 初期値・用途 |
|---|---|
| `id` / `sourceMissionID` | 元SEADの任務ID。Follow-on DEADのIDへ書き換えない |
| `plan` / `spawn` | 元の確定計画と生成Group・ユニット記録への参照 |
| `state` | `ACTIVE`。SEAD達成後、残存ありなら `SUPPRESSED`、全滅なら `DESTROYED` |
| `primaryResult` | nil。SEADの `SUPPRESSED` / `DESTROYED` を確定後に保存 |
| `seadCompleted` | 初期false。元SEAD Primary完了通知でtrue。結果の値とは独立した受注前提 |
| `remainingTargetCount` | 実Groupの生存DEAD対象数。観測失敗時はnil（不明） |
| `disposition` | `CLEANUP` / `RETAIN` / `AVAILABLE` / `IN_USE`。初期は `CLEANUP`。AVAILABLEは明示予約解除済みの共有候補 |
| `followOnAvailable` | 初期false。SEAD達成済みかつ生存対象ありならtrue。IN_USEはfalse |
| `reservedByAssignmentID` | 使用中の任務のassignment ID。元SEAD終了で解除し、Follow-on DEAD受注時に新IDを設定。保持予約とは別 |
| `sourceGroupName` | 元SEADのウィング名。生成時に固定 |
| `retainedWingName` | Preserveで固定する保持予約先ウィング。同じMEグループ名。元SEADの終了・RTB・再武装で解除しない |
| `retainedAt` | 明示保持を初めて選んだミッション時刻 |
| `retainedBy` | Preserve時の長機のUCID・接続player ID。保持者を固定し、接続喪失時のCleanupに使用 |
| `releasedAt` / `releasedByWingName` | 明示予約解除の時刻と元保持Wing。履歴として保存 |
| `unreservedSince` | AVAILABLEかつ使用中assignmentなしになった時刻。RETAIN・IN_USE中は計測しない |
| `cleanupRequested` / `cleaned` | 初期false。削除依頼と削除完了を区別 |

Site stateの `SUPPRESSED` は「SEAD達成済みで車両が残る」という履歴上の状態。現在の発信を保証しない。
SEADのエミッター終端状態は再判定しないが、Site残存車両の生存確認は続ける。
残存は生成済みGroupの実ユニットを確認する。MEテンプレートの車両数から推測しない。
対象はRED ground unitだけ。生成時のDCS object/IDに紐付け、死亡通知はwrapper更新前でも失われた対象として扱う。
生存確認のAPI例外・不正値を全滅と誤認しない。取得時の不明は受注失敗、戦闘中の不明は未達成扱いとする。
Site／DEAD対象の `IsAlive()` はtrueを生存、falseを確認済み死亡、nilを観測不能として扱う。明示的な死亡イベントによるlostは観測不能より優先する。
Siteの未確認対象が観測不能なら `observationUnavailable = true`、`remainingTargetCount = nil`、`followOnAvailable = false` とし、以前のSite状態を保持する。取得一覧から既知の対象が消えた場合も、falseまたは死亡イベントを確認するまで全滅の根拠にしない。
DEAD進行中のnil・例外・不正値・オブジェクトID不一致は残存側に数え、lostを変更しない。観測不能への移行をログへ残し、継続中は同じログを毎秒繰り返さない。正常な観測に戻れば不明状態を解除する。

| 現在のdisposition | 操作・条件 | 次のdisposition・処理 |
|---|---|---|
| `CLEANUP` | 全員終了、保持選択なし | 削除依頼。失敗なら参照を保持してSweepで再試行 |
| `CLEANUP` | SEAD達成＋残存あり、Preserve | `RETAIN`。時刻を保存、元SEADの予約は全員精算まで維持 |
| `CLEANUP` / `RETAIN` / `AVAILABLE` | 元SEAD達成後、Continue | `IN_USE`。同じassignmentでDEAD phaseへ |
| `RETAIN` | 元SEAD終了、残存あり | 旧assignmentの使用予約だけ解除。保持元Wingの専用予約とGroupは維持 |
| `RETAIN` | Task: DEAD取得成功 | `IN_USE`。新assignmentで予約 |
| `RETAIN` | Release Site Reservation | `AVAILABLE`。Wing専用予約を解除。元SEADの使用予約は終了まで維持 |
| `AVAILABLE` | 使用中assignmentなし | 未予約時間の計測開始。他WingもTask: DEADで取得可能 |
| `AVAILABLE` | Task: DEAD取得成功 | `IN_USE`。計測停止、同じGroupを新assignmentで予約 |
| `AVAILABLE` | 未予約のまま連続30分 | `CLEANUP`。削除失敗はSweepで再試行 |
| `IN_USE` | DEAD全対象破壊 | `CLEANUP`。全員精算まで予約を維持 |
| `IN_USE` | 任務中止・全員喪失・離陸予約取消 | `CLEANUP`へ倒し削除。孤児Siteを作らない |
| `RETAIN` | 外部攻撃で全滅 | 候補から除外。所有任務がなければCleanup |
| `RETAIN` | 保持者がログアウト | `CLEANUP`へ移して削除依頼。元SEADの採点・Wing/UCIDロックは変更しない |

Preserveはidempotent。繰り返しても時刻や結果・予約を壊さない。
F10はグループ共有で押した本人を取得できないため、Preserve時に操縦中の登録参加者のうち機体番号が最小の長機を保持者とする。
保持者は最初の選択時に固定し、再選択や後の長機交代で変更しない。
接続中のUCIDを1秒の監視とDEAD候補確認時に照合する。観戦席・別スロット・別coalitionへの移動はログアウトではない。
UCID未照合の場合は取得済みの接続player IDを使う。API例外・取得不備・識別子なしでは切断を確定せず保持を続ける。
保持者がログアウトしたRETAIN Siteは元SEAD精算前でもSite予約を解除してCleanupする。任務記録・確定済みPrimary・個別採点は維持する。
すでにContinueまたはTask: DEADでIN_USEになったSiteはこのログアウトCleanupの対象外とし、使用中の任務の終了処理を使う。
削除失敗は既存Sweepで再試行する。一度Cleanupへ移したSiteを再接続で復元しない。
明示Preserve後にSEADを任意Abortした場合も保持方針は維持するが、SEADポイントは従来通り0。
Siteはセッション内のみ。専用保持中のtimeout・Delete retained siteメニュー・永続保存は追加しない。

### 明示予約解除と30分Cleanup

保持元WingのF10に `Release Site Reservation` を同階層で表示する。複数Siteを保持している場合は地域名と番号を付け、個別に解除する。解除は任務AbortやSite削除ではなく、RETAINからAVAILABLEへの変更である。古いcallbackでもSiteの同一性・保持Wing・現在の操縦者を照合する。

AVAILABLEは同じ残存Groupを全Wingに開放するが、元SEADの全員精算までは使用予約を維持する。その間は他Wingからの取得も30分の計測も開始しない。使用予約が解除された時点を `unreservedSince` に保存し、連続1800秒でCleanupする。設定は `dead.unreservedSiteCleanupSeconds = 1800`。DCSのミッション時刻を使用し、通常は期限到達後1秒以内の監視で削除を依頼する。

RETAINはWing予約が存在するため経過時間で削除しない。IN_USEは地上のARMED待機中も使用予約があるため削除しない。受注準備失敗のrollbackでは解除前の未予約開始時刻を復元し、30分を延長しない。候補確認と使用予約時にも期限を検査する。予約解除を再実行しても開始時刻は更新しない。

AVAILABLEにした後は元保持者のログアウトで削除しない。残存車両の全滅が確認された場合は従来通り早期Cleanupする。観測不能を全滅とはみなさないが、明示開放後の未予約timeoutは適用する。timeoutによる削除はSEAD/DEAD達成や採点の根拠にしない。

## Immediate DEAD

同Wingの未終了SEAD recordが `RTB_PENDING`、主要目標達成済み、Site残存ありの場合に `Continue as DEAD` を選べる。
登録参加者がいる元Wingからのみ操作可能。古いcallbackや途中参加者だけのWingからは移行しない。
新recordや `Missions.Acquire` は作らず、category・任務ID・登録参加者・SEADのPrimary結果と達成時刻を維持する。

```text
SEAD ACTIVE → Primary Complete → RTB_PENDING
                                   ↓ Continue
                              DEAD_ACTIVE
                                   ├─ 未達成で個別RTB → SEAD150／DEAD0
                                   ↓ 全対象破壊
                              RTB_PENDING → 個別精算 → Close/Cleanup
```

Continue時点の生存RED ground unitsを `record.deadTargets` に固定し、`deadStartedAt` を記録する。
SEAD中に破壊済みの車両を除外する。後からGroupに加わった車両や別Siteは対象にしない。
既に精算した参加者は再登録・再採点せず、未精算の参加者だけをDEAD phaseへ移す。
Continue時に進行中の着陸確認は解除する。その後はDEAD未達成でも、新しい着地から既存RecoveryでSEADの帰還評価を開始できる。
`DEAD_ACTIVE` の目標監視と参加者ごとの着陸確認を並行する。帰還成功が確定した時点でDEAD未達成ならSEAD150／DEAD0を精算し、その参加者は終了する。これは任意Abortではない。
MP2では未精算の僚機がDEADを継続でき、Wing/UCIDロックとSiteは全員終了まで維持する。後で僚機が達成しても精算済み参加者のDEAD0は変更しない。
復行・再離陸で着陸確認を解除した参加者はDEAD_ACTIVEへ戻り、再着陸できる。全員がDEAD未達成のまま帰還・終了した場合はCloseし、IN_USE SiteをCleanupする。
個人の状態遷移は `DEAD_ACTIVE → LANDING_CHECK → RTB_SUCCESS`、確認解除時は `LANDING_CHECK → DEAD_ACTIVE` とする。Wing全体を帰還待ちへ変える必要はない。

全対象破壊で `deadCompletedAt` を保存し、SiteをDESTROYED/CLEANUP、recordをRTB_PENDINGへ移す。
Immediate DEADにもDEAD報酬を付与する。Continue時に `dead.fullReward` と独立した採点用IDを固定し、未精算参加者に追加採点項目を持たせる。Mission record・Wing予約は増やさない。
DEAD全対象破壊時に、未精算参加者のDEAD達成時刻を保存する。着陸確認中ならタイマーを維持し、確認解除後の戻り先をRTB_PENDINGに変更する。帰還成功確定前にDEADが達成された場合は、その確認でSEADとDEADを各150精算する。
DEAD途中の事故でもSEAD Primary成功を失わず、SEAD90／DEAD0。両目標達成後の事故は各90、帰還成功は各150、任意Abortは両方0。
追加DEAD精算はTotal/Career/DEAD Scoreだけを更新し、Mission Count・Primary Success・Recovery等の統計は元SEAD精算の1件を維持する。
完了前に終了した参加者やContinue前に精算済みの参加者へDEAD達成を遡って付与しない。イベント時刻がDEAD達成前の事故もDEAD0とする。
全員終了時にIN_USEならCLEANUPへ倒す。
未達成のまま帰還した場合も、残Siteを自動保持はしない。

## PreserveとFollow-on DEAD

`Preserve Site for DEAD` はSEAD達成後の残存SiteをRETAINにし、通常のSEAD Recoveryを続ける。

```text
SEAD RTB_PENDING → Preserve(RETAIN) → SEAD個別精算 → 元record Close
                                                           ↓ Siteは残る
Task: DEAD → Site予約(IN_USE) → ARMED / ACTIVE → RTB_PENDING → DEAD精算 → Cleanup
```

Task: DEADの候補は保持予約先が受注ウィングと一致するRETAIN Site、または明示開放済みで期限内のAVAILABLE Site。followOnAvailable=true、削除未依頼・未完了、使用中assignmentなし、生存対象1両以上を要求する。
元SEADが未終了のRETAIN Siteは予約中なので候補にしない。
受注時の長機現在位置と `plan.actualSpawnPoint`（なければ `spawn.coordinate`）の水平距離で、取得可能な専用保持・共有候補の最寄りを選ぶ。より近くても別Wingが専用保持しているSiteは候補にしない。
SEAD終了時に `Missions.wings` / `Missions.pilots` の任務ロックは解除し、次Sortieの新任務を受注可能にする。`retainedWingName` はSite側に残すので、任務終了を理由に他Wingへ解放しない。
Site選定と使用予約の両方でWing所有を確認する。準備失敗のrollbackでも保持予約先を維持する。所有者が不明なSiteを共有候補へ自動降格しない。同じUCIDでも別グループのスロットは別Wingとして扱う。
長機は従来通り機体番号最小。同距離はSite IDで決定し、距離にSEADの40〜130 NM制限は適用しない。
候補なしでは `No preserved SAM sites available for DEAD.` と通知し、Wing/UCIDのロックを残さない。

Follow-on DEADは `category = "DEAD"` の新recordをAcquireし、受注時の生存対象を固定する。
取得・Acquire・準備の失敗はWing/UCIDロックを解除し、取得前のRETAINまたはAVAILABLE・followOnAvailable・予約状態・未予約開始時刻へrollbackする。
参加者の操作・離陸状態とbriefingも予約トランザクション内で確認する。準備したbriefingは受注時に画面へ1回出し、ACTIVE移行時はデバッグログに再利用する。
受注後に正常な任務として中止・喪失・離陸予約取消した場合はrollbackせずCleanupする。

全員空中なら即ACTIVE。地上参加者がいる場合は予約済みARMEDとし、全員離陸の検出でACTIVEへ移す。
SAMは常に世界に存在する。新Spawn待ちや20秒待ちは設けない。離陸確認間隔は既存の2秒を使う。
地上待機中に他の味方が対象を破壊してもsnapshotは変更しない。任務がACTIVEになるまでは目標達成を確定しない。
地上予約のAbort・事故も0ポイントで精算する。生成前のSEAD予約とは違い、DEADは受注時点で既存Siteと採点用IDを持つ。

## DEAD目標と採点

武器種・破壊者を問わず、固定した全対象の破壊で達成する。死亡/墜落/喪失イベントと1秒pollingで確認する。
参加者全員を失ってからpollingで成功を遡って付けない。参加者死亡と最後の対象破壊のイベント順序は既存ルールを維持する。

```text
DEAD Objective Complete
SAM site destroyed.
Return to base.
```

| 任務 | Primary後RTB | Primary後事故 | Primary前事故・任意Abort | 加算先 |
|---|---:|---:|---:|---|
| Immediate DEADの追加分 | 150 | 90 | 0 | DEAD Score（SEAD報酬は別精算） |
| Follow-on DEAD | 150 | 90 | 0 | DEAD Score |

満額は `dead.fullReward = 150`、失敗率は既存の `recoveryFailurePercent = 60`。
Immediate DEAD未達成での帰還成功は追加DEAD0とし、達成済みSEADだけを満額精算する。
Follow-on DEADは受注時、Immediate DEADはContinue時に満額を固定。既存のScoring.SettleでUCIDごと・採点用IDごとに一度だけTotal/Career/DEAD Scoreを更新する。
初期設定ではImmediate DEADの両目標達成＋帰還で合計300、両目標達成後事故で180、DEAD未達成事故で90。Continueを選ばないSEADでは追加DEAD採点を作らない。
未照合UCIDは採点なし。MP2の報酬は分割せず各自に付与し、全員終了までWing/UCID/Siteの予約を維持する。
切断・スロット変更だけでは自動失敗にせず、既存の個人中止・元機体への復帰ルールを使う。

## Briefing・Status・F10

Follow-on DEADは地域、SAM種類、主要レーダーの履歴（Primary radar destroyed / Previously suppressed）、残存車両全滅の指示と既存Site位置を表示する。
既存Siteの実配置点（actualSpawnPoint、ない場合はspawn.coordinate）を `SITE LOCATION:` としてDDM（度＋小数分、分の小数3桁）で表示する。MOOSEのToStringLLDDMへLL_Accuracy=3を明示する。SEAD TOO/PBの推定点・秘匿仕様には影響しない。
受注時の座標付きブリーフィングとMission Statusの表示時間は共通設定 `coordinateBriefingSeconds`（初期60秒）を使用する。開始通知は座標なし25秒で、ブリーフィングの自動再掲はしない。
SEADのTOO/PB秘匿はFollow-on DEADには適用しない。内部Group名・object IDは表示しない。
Immediate DEADはSEAD情報の秘匿を維持し、残数・follow-on phaseを追加表示する。

通常メニューにTask: DEADを追加。SEAD達成後に残存ありの場合だけ同じ階層へContinue/Preserveを追加する。
Preserve後はPreserveを消しContinueは残す。Continue後や残存全滅・任務終了で両方を消す。
signatureにfollow-on選択可否を含め、既存の再生成方式で反映する。古いcallbackもrecord/site/予約を再検証する。

SEAD Statusには `Site disposition: CLEANUP / RETAIN / AVAILABLE / IN USE` と `Follow-on DEAD available: YES / NO` を追加。
`SEAD Primary result` と `Site state` を別々に表示し、SEAD完了後は `Site remaining vehicles` で実残存数を表示する。観測失敗時の残数はUNKNOWN。
Immediateには `SEAD: COMPLETE` / `Follow-on: DEAD ACTIVE` / `Remaining targets: X`。
Follow-on DEADには `DEAD: ARMED / ACTIVE / RTB PENDING`、地域と残数を表示する。
DEAD Scoreを独立して集計・保存する。Player Statisticsにはカテゴリ別Scoreを表示せず、累計と任務・帰還・喪失統計を表示する（[SCORING.md](SCORING.md)）。

## ゲーム内確認チェックリスト

1. SA-6のレーダーだけ破壊またはSuppressし、残存あり時だけContinue/Preserveが現れる。
2. SA-8を完全破壊した場合はfollow-onなし。生存したままSuppressならfollow-on可能。
3. 何も選ばずRTBした場合はSEAD150、全員終了後に従来通りCleanup。
4. Continueで同じ損傷したGroupを攻撃し、全滅後RTBでSEAD150＋DEAD150、任務数1件。
5. Continue途中の事故はSEAD90＋DEAD0、両目標達成後事故は各90。重複通知で再加算せず、全員終了後に残Siteを削除。
6. Preserve→全員RTB→再武装→Task: DEADで同じ残存車両を攻撃し、DEAD150。
7. Follow-on DEADの達成後事故90、達成前事故・Abort0、全員終了後Cleanup。
8. MP2の一部精算・途中参加・長機喪失でも対象と採点を混同しない。
9. 別WingはSEAD精算後・再武装中にも保持Siteを取得できない。同Wingに複数保持Siteがある場合のみ最寄りを取得し、取得時の使用予約で二重取得も拒否する。
10. 保持後に味方の攻撃で全滅したSiteは受注候補から消える。
11. Mission Status・Statistics・一時メニューが遷移に一致し、再起動でSiteはリセット。Hook導入時は保存済み成績だけを復元し、進行中任務は復元しない。
12. Preserve後に保持者がログアウトするとSiteが削除される。観戦席への移動では残り、DEAD使用中のSiteは元保持者のログアウトで削除されない。
13. Continue後にDEADを倒しきれずRTBしても、10秒の安全帰還確認でSEAD150／DEAD0となる。MP2の未精算者は継続でき、先に帰還した人へ後からDEAD報酬を付けない。
14. Release Site Reservation後、元SEAD全員終了を待って別Wingが同じGroupを取得できる。複数Siteは指定した1つだけを開放する。
15. 開放して誰も予約しないまま30分でCleanupする。専用保持中・DEADの地上予約中は削除せず、共有候補は元保持者の切断では削除しない。

自動検証は [scripts/Test-DEAD.lua](../scripts/Test-DEAD.lua) と既存5スイート、Build/Syncテストを使用する。
nil観測・不明からの回復・明示死亡優先・Group一覧欠落はDEAD-77〜80で検証する。DEAD-16/29/52はDDM精度3、実配置点のSITE LOCATION表示、座標API失敗時のrollbackと保存済みbriefingの再利用を検証する。DCS内の座標確認はMAN-28で行う。
Immediate追加採点はDEAD-67〜76で、事故5種、配点固定、MP2個別精算、達成前喪失、イベント順序・時刻、UCID未照合、Abort、不正設定、精算再試行と統計維持を検証する。DCS内ではMAN-25/26/39を確認する。
自動検証の対応と手動結果は [TESTING.md](TESTING.md) に記録する。
専用予約解除・共有取得・30分境界・使用中の停止・rollback・観測不能時のtimeout・再試行・古いcallbackはDEAD-91〜103、実機確認はMAN-45/46を参照する。
Immediate未達成RTB・MP2継続・復行・確認中事故・確認中DEAD達成とFollow-on境界はDEAD-81〜86、実機確認はMAN-42/43を参照する。

# Persistent and Dynamic F/A-18C Training

Mission Editorへ貼り付ける日英の原稿。各項目は単独でも使える文章とする。
「ミッション概要」は全体の説明欄、それ以降はBLUE側の任務説明欄への掲載を想定する。
現在実装されている訓練と操作を説明する。設定や任務仕様を変更した場合は、この原稿も更新する。

## 日本語

### ミッション概要

Persistent and Dynamic F/A-18C Trainingは、F/A-18Cで迎撃、戦闘空中哨戒、防空制圧、防空サイト破壊を繰り返し練習する訓練ミッションです。BLUE側の基地または空母から出撃し、F10の「Dynamic Training」で任務を選択してください。目標達成だけでなく、味方基地や空母への安全な帰還まで評価します。ソロでも同じグループのプレイヤーと協力しても参加できます。

### 出撃準備と任務操作

プレイヤー機の初期兵装は空です。地上で再武装を要請し、訓練内容に合わせて兵装を選んでください。「Task: Intercept」「Task: CAP」「Task: SEAD」「Task: DEAD」で任務を受注し、「Mission Status」で受注中の情報や進捗を確認できます。「Abort Mission」はグループ全体の任務中止、「Abort Sortie」は名前と機体を指定した参加者だけの中止です。「Player Statistics」で自分の累計成績と保存状態を確認できます。

### Intercept — 迎撃

長機の位置と機首方向を基準に出現する敵戦闘機を迎撃し、今回の任務で生成された敵航空機をすべて撃墜してください。敵は前方の60〜80 NMに出現し、機種、機数、高度、方位、編隊は受注ごとに変化します。地上で受注した場合は、登録参加者全員の離陸検出から20秒後に敵を生成します。全員が空中で受注した場合は即座に開始します。敵全滅後はBLUE側の基地または空母へ帰還してください。

### CAP — 戦闘空中哨戒

候補空域からランダムに指定される空域へ向かい、空域内で累計120秒の哨戒を行ってください。受注時の「CAP AREA」に中心座標を表示し、進捗は20%ごとに通知します。受注時に登録された参加者のうち誰かが空中で空域内にいれば時間が進み、全員が空域外へ出ると一時停止します。再進入すると、それまでの累計時間を引き継いで再開します。空域内の累計30〜120秒の間に敵戦闘機が1編隊出現します。累計120秒の達成と敵機全滅の両方で任務目標達成です。100%になっても敵が残っていれば交戦を続け、両条件を満たしてから帰還してください。

### SEAD — 防空制圧

指定地域のSA-6またはSA-8を捜索し、主要レーダーを破壊するか、損傷させたうえでレーダー停止を連続60秒維持させてください。攻撃方式はTOOまたはPBからランダムに選ばれます。TOOでは機種不明の捜索座標、PBではSAM機種、推定座標、HARM PBコードを案内します。案内座標は実際の配置位置と一致するとは限らないため、索敵して目標を確認してください。HARM以外の武器でレーダーを破壊しても達成です。地上受注では登録参加者全員の離陸検出から20秒後、空中受注では配置計画の確定後にSAMを生成します。目標達成後は帰還するか、残存車両があればDEADへ継続できます。

### DEAD — 防空サイト破壊

SEADで制圧したサイトの残存車両をすべて破壊してください。「Continue as DEAD」は同じ出撃のまま継続攻撃する選択です。「Preserve Site for DEAD」はサイトを保持してSEADを精算し、帰還・再武装後に同じグループで「Task: DEAD」を受注する選択です。元の敵の損傷と残存車両を引き継ぎ、新しいSAMは生成しません。保持された候補がなければ「Task: DEAD」は受注できません。DEAD開始時の生存対象をすべて破壊すると達成です。保持したサイトは同じグループ専用に予約され、「Release Site Reservation」で他グループへ開放できます。

### 帰還とポイント

目標達成後は、BLUE側の飛行場または対応するBLUE側空母へ帰還してください。着陸後、5 knots以下を連続10秒維持すると帰還成功になります。空母では艦との相対速度を使います。各任務の帰還成功は1人150ポイント、目標達成後の帰還確定前に墜落・死亡・脱出した場合は90ポイントです。目標達成前の事故と任意中止は0ポイントです。同じ出撃でSEADとDEADの両方を達成して帰還すると合計300ポイントです。DEAD未達成で帰還した場合も、達成済みのSEAD分は150ポイントを受け取れます。BLUE所属の陸上基地はF10マップの青色Drawingでも確認できます。

### マルチプレイと参加者

同じグループは1つの任務を共有し、同時に受注できる任務はグループごとに1件です。参加するプレイヤー全員が搭乗してから受注してください。参加者は受注時に固定され、AI、空席、途中参加者は今回の採点対象に含みません。目標達成は共有しますが、帰還、事故、中止、ポイントは各自で評価します。報酬は人数で分割しません。1人が帰還しても、全参加者の精算または中止が完了するまで次の任務は受注できません。別グループは独立した任務を並行して進められます。

### 成績の保存

Total Score、Career Points、カテゴリ別スコア、任務・帰還などの累計成績を記録します。保存機能が接続され、保存確認が完了した成績は、ミッション再開始やサーバー再起動後も引き継ぎます。「Player Statistics」で保存済み、保存待ち、未接続の状態を確認してください。未接続時の成績は現在のセッション内だけの記録です。進行中の任務や保持したSAMサイトはミッション再開始時にリセットされます。

## English

### Mission overview

Persistent and Dynamic F/A-18C Training provides repeatable F/A-18C training in interception, combat air patrol, suppression of enemy air defenses, and destruction of enemy air defenses. Depart from a BLUE airfield or carrier and select a mission through the F10 "Dynamic Training" menu. Your performance is evaluated through both objective completion and safe recovery at a friendly airfield or carrier. Fly solo or cooperate with other players in the same flight group.

### Preparation and mission controls

Player aircraft start without weapons. Request rearming on the ground and choose a loadout suited to your training. Accept a task with "Task: Intercept", "Task: CAP", "Task: SEAD", or "Task: DEAD", and use "Mission Status" to review its information and progress. "Abort Mission" cancels the entire group's mission; "Abort Sortie" cancels only the named participant's sortie. "Player Statistics" displays your accumulated results and their save status.

### Intercept

Intercept the enemy fighters generated relative to the flight leader's position and heading, and destroy every enemy aircraft assigned to this mission. Hostiles appear 60–80 NM ahead, with aircraft type, numbers, altitude, bearing, and formation varying between missions. If accepted on the ground, enemies spawn 20 seconds after all registered participants are detected airborne. If everyone is already airborne at acceptance, the mission starts immediately. Once all hostiles are destroyed, recover at a BLUE airfield or carrier.

### CAP — Combat Air Patrol

Proceed to the randomly assigned patrol area and accumulate 120 seconds inside it. "CAP AREA" provides the center coordinates at acceptance, and progress is reported in 20% increments. The clock advances while at least one participant registered at acceptance is airborne inside the area. It pauses when everyone leaves and resumes from the accumulated time on reentry. One enemy fighter formation spawns at a randomly selected point between 30 and 120 seconds of accumulated patrol time. Both 120 seconds on station and the destruction of all assigned enemy aircraft are required. Reaching 100% alone does not complete the objective while hostiles remain. Finish both objectives before returning to base.

### SEAD — Suppression of Enemy Air Defenses

Locate the SA-6 or SA-8 site in the assigned region. Complete the objective by destroying its primary radar, or by damaging it and keeping its radar off for 60 consecutive seconds. The attack mode is randomly selected as TOO or PB. TOO provides search coordinates with the SAM type unknown; PB provides the SAM type, estimated coordinates, and a HARM PB code. These coordinates may differ from the site's actual location, so search and identify the target. Radar destruction with weapons other than HARM also counts. Ground acceptance spawns the SAM 20 seconds after all registered participants are detected airborne; airborne acceptance spawns it once the placement plan is ready. After completing SEAD, return to base or continue as DEAD if vehicles remain.

### DEAD — Destruction of Enemy Air Defenses

Destroy all remaining vehicles at a site previously suppressed during SEAD. "Continue as DEAD" continues the attack during the same sortie. "Preserve Site for DEAD" keeps the site for a later sortie: recover and settle SEAD, rearm, then select "Task: DEAD" with the same flight group. The original enemies retain their damage and surviving vehicles; no new SAM is spawned. "Task: DEAD" requires an available preserved site. Destroy every target that was alive when DEAD began to complete the objective. A preserved site is reserved for the same group; "Release Site Reservation" makes it available to other groups.

### Recovery and points

After objective completion, recover at a BLUE airfield or a supported BLUE carrier. Successful recovery requires remaining landed at 5 knots or less for 10 consecutive seconds. Carrier recovery uses speed relative to the ship. Each completed mission awards 150 points per pilot for successful recovery, or 90 points for a crash, death, or ejection after objective completion but before recovery is confirmed. Losses before objective completion and voluntary aborts award zero points. Completing both SEAD and DEAD during the same sortie and recovering successfully awards 300 points. If DEAD remains incomplete at recovery, the completed SEAD objective still awards 150 points. BLUE land airbases are also identified by blue drawings on the F10 map.

### Multiplayer and participants

Players in the same group share one mission, with a limit of one active mission per group. Have every participating player occupy a slot before accepting a task. Participants are fixed at acceptance; AI aircraft, empty slots, and players joining later are excluded from that mission's scoring. Objective completion is shared, while recovery, losses, aborts, and points are evaluated individually. Rewards are not divided between participants. Even after one pilot recovers, the group cannot accept another mission until every registered participant has settled or aborted. Other groups can run independent missions at the same time.

### Saved progress

Total Score, Career Points, category scores, and accumulated mission and recovery statistics are recorded. When persistence is connected and a save has been confirmed, these results carry over to later mission sessions and server restarts. Check "Player Statistics" for saved, pending, or disconnected status. Without a persistence connection, results are recorded only for the current session. Active missions and preserved SAM sites reset when the mission restarts.

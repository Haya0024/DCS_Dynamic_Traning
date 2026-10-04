# SEAD 訓練ミッション仕様

更新日: 2026-10-04

## 今回の実装範囲

F10 の `Dynamic Training → Generate SEAD` で、SA-6 または SA-8 を1グループ生成する。
受注時に TOO / PB を各50%で抽選し、方式・SAM・Zone・配置予定点を固定する。
計画の作成と SAM の実体生成を分離する。地上受注では計画だけを作成し、登録参加者全員の離陸後20秒で生成する。
受注時から全員が空中なら、計画確定と受注情報表示の直後に生成する。
配置・方式別の情報表示・主要レーダーの状態遷移による成功判定・個別帰還採点・中止を実装する。
SEAD完了後の残存Siteは、標準のCleanup、即時のDEAD継続、明示保持後の別SortieのDEADに対応する。
Follow-onの境界・採点・予約は [DEAD.md](DEAD.md) を参照する。SEADの受注計画・配置・目標条件は維持する。
コードと模擬テストは実装済み。DCS 内での地形・建物判定、SAM の交戦、TOO / PB の攻撃、レーダー破壊と採点の確認は未実施。

## 受注計画と攻撃方式

受注操作で任務IDを発行し、テンプレート・攻撃方式・Zoneを一度だけ抽選する。
距離判定の基準は受注時の長機位置と各 Zone の中心の水平距離。40～130 NMの存在する Zone から等確率で1つ選ぶ。
長機は受注した人ではなく、搭乗中の登録者のうち機体番号が最小の機体。受注後の移動・長機変更で距離判定をやり直さない。
候補がなければ受注ロックを解除し、生成失敗を通知する。

地点選定は `PLANNING` として段階的に処理する。抽選した方式を最初に表示し、安全な予定点が見つかったら完全なブリーフィングを表示する。
TOOの捜索座標、PBの推定座標は計画完成まで `Planning in progress` と表示する。
選定中も実体は生成しない。受注計画が完成するまで通常1秒、全候補不合格なら通常約25秒かかる。
確定後はテンプレート・方式・Zone・予定点・推定点・コード・IDを変更しない。

| 方式 | プレイヤーへ渡す情報 |
|---|---|
| TOO | `MODE: TOO`、`THREAT AREA`として捜索用座標（DDM：度＋小数分）、`TARGET TYPE: UNKNOWN`、座標付近でHARM TOOのエミッターを捜索・攻撃する指示 |
| PB | `MODE: PB`、SAM種類、推定位置の緯度経度（DDM：度＋小数分）、3桁のHARM PBコード、攻撃と帰還の指示 |

両方式とも分の小数部は3桁。MOOSEの `COORDINATE:ToStringLLDDM({ LL_Accuracy = 3 })` を使用し、受注・開始・Mission Statusで同じDDM形式を表示する。MOOSE全体の座標表示設定には依存しない。

TOOの `THREAT AREA` は地域名から捜索用座標へ変更した。実配置予定点からランダム方位へ3～5 NMずらした座標を渡す。
誤差の設定は `tooEstimateErrorMinNM` / `tooEstimateErrorMaxNM`。計画完成時に座標を固定し、受注・開始・`Mission Status` に同じ座標を表示する。
TOOでは正確な位置・SAM機種・PBコード・車両数を表示しない。開始時だけでなく `Mission Status` も同じ情報制限を適用する。
PBでも正確な実配置座標は表示しない。安全な実配置予定点を先に選び、その地点からランダム方位へ1～3 NMずらした推定点を渡す。
PBの実配置点と推定点の水平距離は `pbEstimateErrorMinNM` / `pbEstimateErrorMaxNM` の範囲内。
TOO / PBの表示座標は捜索・攻撃の参考情報であり、Zone外や配置に不適な地形上でもよい。
実体は計画した実配置点にそのまま生成する。推定点を基準に離陸後に別の配置点を抽選しない。

| テンプレート | SAM種類 | HARM PBコード | 主要車両のDCS TypeName |
|---|---|---:|---|
| `TPL_SEAD_SA6` | SA-6 | 108 | `Kub 1S91 str` |
| `TPL_SEAD_SA8` | SA-8 | 117 | `Osa 9A33 ln` |

TypeNameは現在の `.miz` の `mission` エントリで確認済み。PBコードは指定仕様の値を設定し、実際のHornetでの入力・攻撃確認は未実施。
各テンプレートの `name` / `type` / `pbCode` / `primaryUnitType` は `sead.templates` にまとめる。

### 任務状態への保存

共通の `Missions.wings[groupName]` に `category = "SEAD"`、任務ID、参加者、計画、生成後の実体を保持する。

| 保存先 | 内容 |
|---|---|
| `record.plan` | `missionType`、`id`、`attackMode`、`template`、`samType`、`pbCode`、`primaryUnitType`、`zoneName`、`areaLabel`、受注時の長機位置 |
| `record.plan.actualSpawnPoint` | 検査済み実配置予定点。計画完成時に固定 |
| `record.plan.estimatedPoint` | TOOの捜索位置（3～5 NM誤差）またはPBの推定位置（1～3 NM誤差） |
| `record.spawn.group` / `record.spawn.primaryUnits` | 生成したSAMグループと主要レーダーのオブジェクト・ID |
| `record.spawn.emitterState` / `primaryResult` | エミッター状態・確定結果。帰還評価中も保持 |
| `record.site` / `Missions.sites[missionID]` | 計画・生成Group・disposition・予約・SEAD結果を持つサイト参照。明示RETAINは元record終了後も保持 |
| `record.participants` | 受注時に固定した人間参加者と個別帰還・精算状態 |

表示は計画から作る。生成後の実体から機種や位置を取り直してブリーフィングを作らない。

## 主要目標と採点

| テンプレート | 破壊対象の主要レーダー（DCS 機種名） | 成功条件 |
|---|---|---|
| `TPL_SEAD_SA6` | `Kub 1S91 str` | 破壊、または損傷後の連続60秒のRadar OFF。発射機が残っていても達成 |
| `TPL_SEAD_SA8` | `Osa 9A33 ln` | 一体型車両の破壊、または損傷後の連続60秒のRadar OFF |

対象は選択した `sead.templates` の `primaryUnitType` で識別し、テンプレート内の並び順や車両名には依存しない。
武器種は問わず、HARM以外でも条件を満たせば達成とする。
主要レーダーを含まないテンプレートや、生成後に対象を追跡できない構成は生成失敗とする。
生成時の DCS オブジェクトと実際のLifeを記録し、死亡・墜落・喪失イベントと1秒間隔の観測で判定する。
別ウィングや前回任務のレーダー破壊は対象外。AI 僚機・他の味方が今回の対象を破壊した場合は達成に含める。

達成時は未精算の参加者全員を帰還待ちにする。この時点ではポイントを加算しない。

| 各参加者の結果 | 付与ポイント |
|---|---:|
| 達成後、BLUE 飛行場・対応 BLUE 空母へ帰還成功 | 150 |
| 達成後、帰還確定前に墜落・死亡・脱出 | 90（60%） |
| 達成前の墜落・死亡・脱出、任意中止 | 0 |
| UCID を取得・照合できない場合 | 採点なし |

満額は `sead.fullReward = 150` で設定し、生成成功時に固定する。Intercept の配点とは独立して変更できる。
2人編隊でも満額は各自150ポイント。受注時の参加者だけを対象とし、帰還・事故・精算は UCID ごとに独立する。
帰還成功は地上状態と5 knots以下を連続10秒確認する。空母では艦との相対速度を使う。
確定額を Total Score、Career Points、SEAD Score に加算し、Intercept Score は変更しない。
精算済み任務数・成功／帰還／失敗の件数は共通累計へ反映する。永続保存は未実装。
詳細は [SCORING.md](SCORING.md) を参照する。

主要目標を達成しても、残る発射機と受注ロックは全参加者の精算・中止まで保持する。
クリア前に死亡・中止した人へ後から報酬を与えない。

### Primary Emitterの状態機械

ウィングの任務状態（`ACTIVE` / `RTB_PENDING`等）と、エミッターの状態は分離する。
`record.spawn.emitterState` は以下の4状態を持ち、生成時は `ACTIVE` とする。

| 状態 | 意味 |
|---|---|
| `ACTIVE` | 未達成。通常は生存・Radar ON。無傷のRadar OFFや観測不明もこの状態に留め、成功にしない |
| `SUPPRESSION_PENDING` | 生存・開始時Lifeより減少・Radar OFFの3条件を満たし、OFF継続時間を計測中 |
| `SUPPRESSED` | 損傷した生存エミッターのRadar OFFが連続60秒以上。終端状態・目標達成 |
| `DESTROYED` | Primary Emitter破壊。終端状態・目標達成 |

| 現在状態 | 観測・イベント | 次状態と処理 |
|---|---|---|
| `ACTIVE` | 生存、`Life < initialLife`、Radar OFF | `SUPPRESSION_PENDING`。この観測時刻から計測 |
| `SUPPRESSION_PENDING` | Radar ONに復帰 | `ACTIVE`。OFF開始時刻を破棄（継続時間0） |
| `SUPPRESSION_PENDING` | Lifeが開始時以上に戻る、Life/Radarの観測失敗 | `ACTIVE`。タイマーを破棄し、観測失敗はログへ記録 |
| `SUPPRESSION_PENDING` | 3条件を維持して60秒以上経過 | `SUPPRESSED`。既存の帰還評価へ一度だけ移行 |
| `ACTIVE` / `SUPPRESSION_PENDING` | Primary Emitter破壊 | `DESTROYED`。タイマーに関係なく既存の帰還評価へ移行 |
| `SUPPRESSED` / `DESTROYED` | 任意の後続イベント | 状態・結果を維持。目標の観測・再判定を停止 |

Lifeの基準はSAM生成時（戦闘開始時）の `UNIT:GetLife()` 実測値。
工場出荷時の `GetLife0()` や固定のdamage percentageは使わない。基準値が取得できなければ生成失敗とする。
Radar ON/OFFにはMOOSE `UNIT:GetRadar()` の第1戻り値を使う。第2戻り値の追尾対象がnilでもOFFとは限らない。
Life・Radarの不正値やAPI例外をOFFと見なさない。破壊イベントまたは生存確認で破壊が確定した場合はLife/Radar取得を必要としない。
参照: [MOOSE UNIT API](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Wrapper.Unit.html)。

継続時間はミッション時刻で測る。無傷のOFF時間は加算せず、損傷を観測した時点から数える。
計測中の追加損傷はタイマーをリセットしない。`sead.suppressionHoldSeconds = 60` に集約し、生成時に値を固定する。
1秒間隔の観測なので、観測の間に起きた短いON/OFFの切替は検出できない。

現在の両テンプレートはPrimary Emitter各1両。複数を含む構成では全対象が破壊または損傷・OFF継続時間達成することを要求する。
タイマーは対象ごとに保持し、全対象の破壊なら `DESTROYED`、生存対象を含む達成なら `SUPPRESSED`。
全生存対象が3条件を満たす間だけサイト状態を `SUPPRESSION_PENDING` とする。
一部が60秒に達しても全対象が達成するまでは成功を確定せず、再発信した対象のタイマーをリセットする。

### 完了後のSAMサイトとCleanup

終端状態へ遷移すると `record.primaryResult` に結果を保存し、未精算の登録参加者を `RTB_PENDING` へ移す。
SAM Groupはその場に残し、完了時にDestroyしない。Radar再開・残存車両の撃破でも結果・報酬は変えない。
完了後の表示は次の通り。

```text
SEAD Objective Complete
Enemy radar destroyed.
```

```text
SEAD Objective Complete
Enemy radar suppressed.
```

生成Group、計画、エミッター状態・結果の参照を独立したサイト管理へ登録する。
`CLEANUP` が標準。何も選ばなければ全参加者の精算・中止・失敗終了後にCleanupを要求する。
`Preserve Site for DEAD` を明示選択した場合だけ `RETAIN` とし、全員精算後もSiteを保持する。
Preserve時の長機を保持者として固定し、そのプレイヤーのログアウトを確認した場合はRETAIN SiteをCleanupする。観戦席・別スロットへの移動は切断扱いにしない。
このCleanupは元SEAD精算前でも可能だが、SEADのPrimary結果・帰還評価・Wing/UCIDロックは変更しない。すでにDEAD使用中のIN_USE Siteは対象外。
元SEADが終了するまではSiteの予約を維持し、別Wingが先に取得できないようにする。
`Continue as DEAD` は同じrecordを `DEAD_ACTIVE` へ移す。既存Groupを再生成せず、生存車両だけを対象に固定する。
Immediate DEADではSEADの達成結果・任務ID・採点カテゴリを維持し、独立した追加DEAD報酬を設定する。DEAD全滅後にRTBへ戻り、帰還時に各150、両目標達成後事故は各90、DEAD未達成事故はSEAD90／DEAD0。任意Abortは両方0。任務数は1件を維持する。詳細は [DEAD.md](DEAD.md)。
IN_USEのまま全員終了した場合はCLEANUPへ倒す。保持timeoutは今回追加しない。
ウィングの終了処理はサイトの解放を通知するだけとし、SAMの削除・再試行は独立したサイト管理が担う。
削除に失敗したサイトも参照を失わず、監視tickで再試行する。参照は削除完了まで保持する。
生成途中の検証失敗による即時削除は、完成したサイトのCleanupとは別の失敗復旧とする。
保持SiteのGenerate DEADは新しい任務IDを使用し、DEAD Scoreへ独立精算する。
Site stateの残存判定はSEADエミッターの終端状態と別に監視する。DEADで残存車両を破壊してもSEAD結果は変えない。
`record.primaryResult = "DESTROYED"` は主要レーダー破壊だけを意味する。SA-6のLauncherが1両以上生存していればDEAD継続可能で、Site全滅は生存RED ground車両が0の場合だけとする。
損傷＋Radar OFF60秒のSUPPRESSEDでは、生存レーダーもLauncherもDEAD対象に含める。SEAD完了済みの前提は `site.seadCompleted`、残存数は実Groupから取得する `site.remainingTargetCount` として分離する。

## Mission Editor の前提

| グループ名 | 構成 |
|---|---|
| `TPL_SEAD_SA6` | Kub 1S91 str ×1、Kub 2P25 ln ×3 |
| `TPL_SEAD_SA8` | Osa 9A33 ln ×1 |

両方とも RED / Russia、Late Activation 有効の地上グループとして `.miz` 内で確認済み。
受注ごとに2候補から等確率で1つ選ぶ。ME の配置間隔・機体種類・兵装を継承する。
テンプレートのグループ名はスクリプトや同期処理で変更しない。

配置候補は次の4つの円形 Trigger Zone。現在の半径は各18,288 m。

- `SEAD_ZONE_PALMYRA`
- `SEAD_ZONE_SALAMIYAH`
- `SEAD_ZONE_DUMAYR`
- `SEAD_ZONE_TABQA`

名前と判定値は [src/config.lua](../src/config.lua) の `sead` に集約する。
ME で名前を変更したら設定・仕様書・テストの対応も更新する。

## 地点の抽選

1. 選んだテンプレートの車両座標を最初のルート点からの相対位置として取得する。
2. 受注時の長機位置から40～130 NMの Zone を抽出し、1つだけ選んで計画に保存する。
3. 選択した Zone の MOOSE `ZONE:GetRandomVec2()` で候補を取得する。
4. 候補、地形確認点、各車両の予定位置がすべて Zone 内か確認する。
5. すべての確認点が `LAND` で、最高・最低高度の差が20 m以内か確認する。
6. 車両の予定位置が建物・その他の障害物から200 m以上離れるか確認する。
7. 別ウィングの実配置予定点との離隔も確認する。不合格なら同じ Zone で再抽選し、50回失敗で任務生成失敗とする。別 Zone に変更しない。
8. 合格した実配置座標と、方式に応じてずらした捜索・推定座標を固定する。生成時刻まで実体を作らない。
9. 生成直前に同じ予定点の地形・障害物を再確認し、`SPAWN:NewWithAlias(...):SpawnFromVec2(point)` で生成する。

別ウィングの予約点とは、両サイトの地形確認半径の合計＋建物離隔距離以上離す。
生成直前に予定点が塞がった場合、検査APIの例外、選択Zoneの消失では任務を解除する。別地点・別Zoneへの移動や再抽選はしない。

地形検査は候補中心から半径200 mの円内を50 m間隔の格子で調べ、外周16点と各車両の予定位置も調べる。
テンプレートがこの半径より広がっている場合は、その車両を含むまで確認半径を広げる。
最高・最低高度の差が閾値を超えた時点で、その候補を拒否する。
道路・滑走路・浅瀬・水面は LAND とみなさない。
連続地形を有限個の点で検査する近似なので、確認点の間の小さな起伏・狭い障害物は実機で確認する。

### 建物との離隔

MOOSE `COORDINATE:ScanObjectsSquare` で SCENERY、STATIC、UNIT を検索する。
地図の建物だけでなく、樹木などの scenery、ME の静的配置物、既存車両も障害物として扱う。
検索範囲は候補中心から「地形確認半径＋離隔距離＋追加検索幅300 m」の正方形。
この API は南西の角を基準にするため、検索位置を補正し、高度範囲も候補の地面高度に合わせる。

各オブジェクトの外接水平円を bounding box から求め、各車両の予定位置から
「200 m＋オブジェクトの外接半径」以上離れることを要求する。箱の角よりも保守的な判定となる。
bounding box が得られないオブジェクトは半径50 mとして扱う。
標準 DCS オブジェクト API を使う理由は、MOOSE の検索結果から構造物の大きさを取得するため。
地図オブジェクトの検出・境界情報に依存する。非常に大きい建物や境界情報がない物の外縁距離は実機で確認する。
検索 API の例外・不正な戻り値は安全な地点と扱わず、任務の生成を失敗させる。

### 地上生成と戦闘設定

`SpawnFromVec2` に空中高度の引数を渡さず、各地上車両をその場所の地面へ配置する。
座標の基準はテンプレートの `route.points[1]`。最初の車両と一致すると決めつけない。
ランダムな機首・車両位置への変更は行わず、検査した ME の相対配置を維持する。
生成した各機の DCS オブジェクトと ID を記録する。

SAM には MOOSE `OptionAlarmStateRed()`、`OptionROEOpenFire()`、`RouteStop()` を適用する。
レーダーを戦闘状態にし、車両を移動させない。実際の探知・発射は AI と ME の兵装設定に依存する。
生成後の設定失敗、車両数や主要レーダー数の不一致では、生成済みのグループを削除して受注ロックを解除する。

## 時間と状態

検査は1秒ごとの監視で最大2候補ずつ処理する。1回の F10 呼び出しで全候補を調べない。
選択した1 Zoneを最大50回検査し、不合格なら通常約25秒で終了する。
見つからない Zone は受注時の候補から除外する。選択Zone不合格・API例外・生成失敗は画面とログで通知し、再受注を可能にする。
条件を緩めて無理に配置したり、Zone 中心へ代替配置したりしない。
試行上限での失敗時は、地形の高低差・LAND以外・Zone境界・障害物・他ウィングの予約との競合・座標取得失敗の件数を画面とログへ出す。
地形は早期拒否までに観測した最大の高低差も出す。候補全体を測り切った値ではない。
API例外は「Site check error」と表示し、ログに例外の詳細を残す。TOOでも機種・正確な座標・PBコードは画面に出さない。

2026-10-04の実機ログではSalamiyahの30回の抽選が不合格となり、最後の拒否理由は `uneven terrain` だった。
テンプレートの確認半径は200 mで正常。抽選上限を50回へ増やして診断を追加したが、同Zoneでの成功は再確認待ち。
同日のユーザー指定で、地形の高低差の上限を5 mから20 mへ緩和した。半径200 m・建物離隔200 mを適用し、適合地点が見つからない場合は引き続き失敗解除する。

| 状態 | 動作 |
|---|---|
| PLANNING | 受注計画の地点選定中。ウィングと UCID の受注ロックを保持 |
| ARMED | 計画確定済み。登録参加者全員の離陸待ち |
| TAKEOFF_DELAY | 全員の離陸検出から20秒待ち。途中の着地でARMEDへ戻る |
| ACTIVE | 配置済み。エミッターの状態機械を監視 |
| RTB_PENDING | 主要目標達成済み。各参加者の帰還・事故を評価 |
| DEAD_ACTIVE | 同じSEAD recordで残存Siteの全滅を目指す。SEAD報酬は維持 |
| 記録なし | 未受注、全体終了、生成失敗または全参加者の終了後 |

帰還確認中の参加者は個別に `LANDING_CHECK` となる。個人中止・全体中止は選定中・戦闘中・帰還待ちに操作できる。

受注時の同じ BLUE Hornet グループの人間全員で訓練を共有する。空席・AI・途中参加者は登録しない。
同一ウィングで SEAD / Intercept / Follow-on DEADを同時に受注できない。別ウィングは別々のカテゴリも同時に実行できる。
敵の名前は `DT_SEAD_<受注番号>#001` のような別名を使い、再受注・別ウィングとの衝突を防ぐ。

地点選定中に受注時の機体・操縦者が無効になったら選定を取り消す。
選定中の個人中止は残る参加者で選定を続け、全体中止は生成前でもキャンセルする。
離陸待ち・20秒待ちの間の死亡・退出・機体／操縦者変更は予約全体を解除する。
離陸判定は2秒間隔。計画完成後、全員の離陸を検出してから20秒待つため、通常は実際の全員離陸から約20～22秒で生成する。
受注後に計画が完成する前に全員が離陸した場合は、計画完成後の離陸検出から20秒待つ。
個人中止で離陸待ちから外れた人は対象外とし、計画を維持して残る参加者でカウントをやり直す。
配置後の個人中止・機体喪失は残る参加者の訓練を維持する。全員終了後の敵はdispositionに従い、標準は削除、明示RETAINは保持する。
切断・スロット変更だけで配置済み訓練を自動終了しない。元の参加者は UCID を照合した個人中止が可能。
共有メニューと受注ブロックの詳細は [WING.md](WING.md) を参照する。

## 表示・操作

受注・開始・`Mission Status` は共通の計画ブリーフィングを使い、TOO / PBの情報制限を維持する。
地域表示名は `sead.zoneLabels`、SAM表示名はテンプレートの `type` に置き、ME の参照名と分離する。
`Mission Status` では方式別の情報に加え、計画中の地点選定回数・生成までの残り時間・各参加者の状態を表示する。
生成後は `Emitter state: ACTIVE / SUPPRESSION PENDING / SUPPRESSED / DESTROYED` と、計測中の継続時間を表示する。
`Player Statistics` では SEAD Score を Intercept Score と別に表示する。
SEAD達成後の残存あり時だけContinue/Preserveを表示し、StatusへSite dispositionとFollow-on DEAD availableを加える。
`Abort Mission` でウィング全体、`Abort Sortie: <名前> [<機体>]` でその参加者だけを中止する。
今回、F10 地図マーカー・コックピットのウェイポイント設定は追加しない。

## 検証と反映

- [src/sead.lua](../src/sead.lua): Zone 抽選・地形／離隔判定・地上生成・主要レーダーの追跡。
- [src/sead_objective.lua](../src/sead_objective.lua): エミッター観測・遷移表・終端状態・デバッグ状態表示。
- [src/sead_sites.lua](../src/sead_sites.lua): サイト参照の登録・全員終了後の削除・削除失敗時の再試行。
- [src/dead.lua](../src/dead.lua): 保持Siteの選定・残存対象snapshot・DEAD判定。
- [src/DynamicTraining.lua](../src/DynamicTraining.lua): F10・共有受注・段階的な地点選定・状態・終了。
- [scripts/Test-SEAD.lua](../scripts/Test-SEAD.lua): 方式抽選・情報制限・計画固定・PB誤差・距離候補・離陸待ち・配置条件・失敗復旧・主要目標・個別採点・複数ウィングの模擬検証。
  状態遷移、60秒境界、無傷OFF、再発信、観測不明、開始時Life、終端状態での観測停止、全員精算、Cleanup再試行も検証する。

`Build-Mission.ps1` で結合後、Lua 5.1 で `scripts/Test-SEAD.lua`、`scripts/Test-DEAD.lua` と既存4種類のテストを実行する。
SEAD61件と既存84件を維持し、DEAD follow-onの検証は [TESTING.md](TESTING.md) にまとめる。
実際のDCSでのRadar状態・損傷Life・イベント順序・残存SAMのCleanupはゲーム内確認待ち。
既存の埋め込み Lua に結合するため、ME の追加トリガー登録は不要。
`Sync-Mission.ps1` と `-Check` を順に実行し、ME で `.miz` を開き直してミッションを再開始する。

DCS 内では4 Zone それぞれで SA-6／SA-8 の車両位置、建物からの離隔、地面への配置、レーダー・発射動作を確認する。
地上受注で計画を受け取ってもSAMが出現せず、全員の離陸後20秒で同じ計画のSAMが出現することを確認する。
TOOで捜索座標が表示され、機種・正確な座標・PBコードが表示されないこと、PBのコードと推定座標を使ってHARMを設定・攻撃できることを確認する。
Intercept との二重受注拒否、選定中の中止、MP2 の共有操作、別ウィングの同時受注も確認する。
SA-6 は発射機を残してレーダーだけ破壊し、SA-8 は車両を破壊して帰還待ちになることを確認する。
無傷のRadar OFFでは未達成、損傷＋OFFで計測開始、途中のONでリセット、損傷＋連続60秒OFFでSuppressedとなることを確認する。
完了後のRadar再開・残存車両撃破で結果が変わらず、全員の精算まで残存Groupが保持されることを確認する。
その後の帰還150、墜落・死亡・脱出90、達成前の事故0、および SEAD Score の加算を確認する。

# 任務メッセージのタイミング・分岐一覧

更新: 2026-10-27。現在の `training-13` の実装を読み取った、表示を見直すための一覧。
本文・タイミングは現在の実装に合わせる。実画面のキャプチャではない。2026-10-15の変更でPBのTHREAT AREAを推定座標へ統一し、抑制条件を30秒へ短縮した。DEADの座標をラベルと同じ行へまとめ、受注本文の並び順も更新した。

対象は実装済みの Intercept / CAP / SEAD / Immediate DEAD / Follow-on DEAD / Strike / Air Interdiction。
CAS / Anti-Ship は未実装なので、現在の受注通知やクリア通知はない。
画面の英語本文とDCSログの詳細例は [MESSAGES.md](MESSAGES.md) も参照。

## 読み方と共通タイミング

- 下のIDはこの資料内の参照番号。画面には出ない。
- `<名前>` / `<人数>` / `<座標>` / `<累計>` などは実行時に埋まる値。ポイントは初期設定値。
- 「表示60秒」は表示の寿命であり、次の通知まで60秒待つ意味ではない。
- 受注通知→ブリーフィングなどは、同じ処理内で連続して送る。前の通知の表示終了を待つ仕組みはない。
- 通常通知は対象Group全員へ送る。個人の精算も元の任務Group全員に見える。初期化通知だけ全体へ送る。
- 宛先Groupを取得できなければ画面へ送れない。表にエラー本文があっても、Group不在の場合は表示されない。
- 画面通知は同じ本文をDCSログの `MESSAGE` にも記録する。`DEBUG` は画面に出ない。
- 監視はミッション時刻の1秒間隔、離陸確認は2秒間隔、メニュー更新は通常2秒間隔＋イベント・操作時。
- Intercept / 地上受注SEADの生成待ちは全員離陸検出後20秒。画面にはカウントダウンを自動表示しない。
- 座標付き通知と該当するStatusは `coordinateBriefingSeconds`（現在60秒）を使う。
- 帰還は目標達成後の有効な着地を入口とし、BLUE基地・対応空母で5 knots以下を連続10秒維持して確定する。監視間隔による遅れはある。
- 通常飛行中に繰り返し出る定時リマインダーはない。下記のイベント・遷移か手動操作で表示する。

## 1. Intercept

| ID | タイミング・分岐 | 画面本文 | 秒・回数 |
|---|---|---|---|
| INT-01 | 地上の参加者を含む状態で受注 | `Intercept mission armed. Registered pilots: <人数>.`<br>`Waiting for ALL registered pilots to take off.` | 10秒、受注時1回 |
| INT-02 | 全員空中で受注した直後。または地上受注で全員離陸検出＋20秒後、敵生成成功 | `Intercept MISSION START` | 15秒、1回 |
| INT-03 | 今回生成した敵航空機が全滅 | 下の達成本文 | 20秒、1回 |

INT-03:

```text
Intercept PRIMARY OBJECTIVE COMPLETE
All hostile aircraft destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

全員空中で受注した場合、INT-01は出ずINT-02から始まる。
離陸検出・20秒待ち開始・生成前の再着地による待ち直しはDEBUGのみ。
Range / Altitude / Aspect / Hostiles / Pilotsも開始時DEBUGのみ。
途中の1機撃破・未達成での帰還・再武装・再離陸では専用の画面通知は出ない。
帰還成功・事故・Abortは「6. 個人精算」へ。

## 2. CAP

| ID | タイミング・分岐 | 画面本文 | 秒・回数 |
|---|---|---|---|
| CAP-01 | 距離内の空域を確定し受注成立。地上／空中共通 | `CAP mission accepted.` | 10秒、1回 |
| CAP-02 | CAP-01直後、同じ受注処理内 | 下の空域ブリーフィング | 60秒、1回 |
| CAP-03 | 未精算・操作中・空中の登録者が初めて空域内に入った監視時 | `CAP on station.` | 10秒、1回 |
| CAP-04 | 時間未達の間、全対象者が空域外・地上・観測不能になったとき | `CAP patrol paused. Return to the assigned area.` | 10秒、停止への遷移ごと |
| CAP-05 | 時間未達の間、誰かが有効な空域内状態に戻ったとき | `CAP patrol resumed.` | 10秒、再開への遷移ごと |
| CAP-06 | 哨戒累計24 / 48 / 72 / 96秒に到達した監視時 | `CAP patrol progress: 20%` / `40%` / `60%` / `80%` | 各10秒、各閾値1回 |
| CAP-07a | 累計120秒到達、敵が残っている | `CAP patrol progress: 100%`<br>`Patrol time complete. Destroy all remaining hostiles.` | 10秒、1回 |
| CAP-07b | 累計120秒到達、敵はすでに全滅 | `CAP patrol progress: 100%`<br>`Patrol time complete.` | 10秒、1回。直後にCAP-08も送る |
| CAP-08 | 累計120秒＋敵全滅の両条件成立 | 下の達成本文 | 20秒、1回 |

CAP-02:

```text
CAP AREA: <空域中心のDDM座標>
Objective: patrol inside for 120 seconds AND destroy all hostiles.
Registered pilots: <人数>.
Reward per pilot: 150 points.
```

CAP-08:

```text
CAP PRIMARY OBJECTIVE COMPLETE
Patrol time complete and all hostile aircraft destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

地上受注でもACTIVEとなり、離陸待ち専用通知・20秒生成待ちはない。
受注時すでに空域内なら、次の監視でCAP-03が続くことがある。
敵生成は哨戒累計30〜120秒内に固定した時刻で1回。生成そのものの画面通知はなくDEBUGのみ。
敵全滅が先なら時間を満たすまで待ち、時間が先なら敵全滅まで待つ。
累計120秒以降はCAP-04/05を出さない。残敵数の変化も自動通知しない。

## 3. SEAD（TOO / PB）

| ID | タイミング・分岐 | 画面本文 | 秒・回数 |
|---|---|---|---|
| SEAD-01 | SAM・Zone・方式を固定して受注成立 | `SEAD mission accepted.`<br>`Mission planning in progress.` | 10秒、1回。MODEはまだ出さない |
| SEAD-02T | 配置計画が確定、TOOの場合 | 下のTOOブリーフィング | 60秒、自動は1回 |
| SEAD-02P | 配置計画が確定、PBの場合 | 下のPBブリーフィング | 60秒、自動は1回 |
| SEAD-03 | 計画点を再検査してSAMを生成したとき | 下の開始本文 | 25秒、1回。座標なし |
| SEAD-04D | 主要レーダー全対象を破壊したとき | 下の破壊達成本文 | 20秒、1回 |
| SEAD-04S | 生存主要レーダーが損傷＋連続30秒OFFを満たしたとき | 破壊達成本文の2行目を `Enemy radar suppressed.` に置換 | 20秒、1回 |

SEAD-02T（機種・正確な配置座標・PBコードは隠す）:

```text
SEAD MISSION
MODE: TOO
THREAT AREA: <実配置点から3〜5 NMずらしたDDM座標>
TARGET TYPE: UNKNOWN
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

SEAD-02P（正確な配置座標は隠す）:

```text
SEAD MISSION
MODE: PB
THREAT AREA: <実配置点から1〜3 NMずらしたDDM座標>
THREAT: <SA-6 または SA-8>
HARM PB CODE: <SA-6は108、SA-8は117>
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

SEAD-03:

```text
SEAD TRAINING START
Objective: destroy primary emitter, or damage it and keep radar OFF for 30 seconds; then RTB.
```

SEAD-04D:

```text
SEAD Objective Complete
Enemy radar destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

計画は1秒ごと最大2候補、選んだZoneの中で最大50候補を調べる。確定通知までの秒数は一定ではない。
受注時から全員空中ならSEAD-02直後に同じ処理で生成を試み、SEAD-03が続く。
地上受注なら計画確定後に離陸待ち。全員離陸検出＋20秒で生成する。生成前に着地すると待ち直し。
受注時に地上だった者が計画中に離陸しても、受注時全員空中の即生成ルートには切り替わらない。
離陸待ち・生成カウントダウン・リセット・HARMの操作指示・開始時PilotsはDEBUGのみ。
抑制の計測開始・進行・再発信によるリセット・車両の部分撃破は自動画面通知なし。

SEAD達成時、残車両があり操作可能な未精算参加者がいる場合、F10に `Continue as DEAD` / `Preserve Site for DEAD` が追加される。
**メニューが増えたことを知らせる専用メッセージはない。** 残車両0や観測不能の場合、継続候補にならない。

## 4. SEAD達成後の分岐

### 4A. 何も選ばず帰還

追加の分岐通知はない。SEAD-04の帰還指示から、そのままSEADの個人帰還精算へ進む。
全員終了後は残SiteをCleanupする。削除完了の画面通知はない。

### 4B. Continue as DEAD（同じ出撃で継続）

| ID | タイミング | 画面本文 | 秒・回数 |
|---|---|---|---|
| IMM-01 | 有効な `Continue as DEAD` を選択した直後 | 下の継続本文。別の受注／開始通知はない | 60秒、1回 |
| IMM-02 | DEAD開始時に固定した残存対象を全破壊 | 下の達成本文 | 20秒、1回 |
| IMM-03 | DEAD未達のまま安全帰還が確定 | 個人精算。SEAD150 / DEAD0 | 20秒、参加者ごと1回 |
| IMM-04 | DEAD達成後に安全帰還が確定 | 個人精算。SEAD150 / DEAD150 | 20秒、参加者ごと1回 |

IMM-01:

```text
Immediate DEAD started.
Destroy all remaining SAM site vehicles.
Remaining targets: <残数>
SITE LOCATION: <Site実配置基準点のDDM座標>
Additional DEAD reward per pilot: 150 points.
SEAD reward also retained.
```

IMM-02:

```text
DEAD Objective Complete
SAM site destroyed.
Return to base.
DEAD reward per pilot: 150 points; recovery failure: 90 points.
SEAD reward also retained.
```

敵の再生成・離陸待ち・20秒待ちはない。部分撃破の現在残数はStatusにも出さない。
帰還確認中にDEADも達成するとIMM-02を表示し、確認タイマーを維持して合計300を精算する。
未達帰還の専用説明は出ず、IMM-03の精算表示だけになる。未精算の僚機は継続可能。
精算の見出しはDEADでなく、元のカテゴリを維持して **`SEAD RTB_SUCCESS` / `SEAD RTB_FAILURE`** になる。

### 4C. Preserve Site for DEAD（保持して次の出撃へ）

PRE-01 — 有効な `Preserve Site for DEAD` 選択時、20秒:

```text
SAM site preserved for follow-on DEAD.
Keeper: <保持者名>
Site remains reserved for your wing after SEAD settlement.
Return to base and rearm.
Site will be cleaned when the keeper disconnects.
```

この操作だけでは正確なSite座標を公開しない。元SEADを継続し、帰還精算はSEAD150。
通常メニューは保持後にPreserveを隠すが、まだ有効な古いcallbackを再実行するとPRE-01を再表示する場合がある。
保持しただけではDEADの受注・開始通知は出ない。元SEAD全員終了・再武装後の `Task: DEAD` は「5」へ。
保持者の切断によるCleanupや、残対象全滅によるCleanupには画面通知がない。

### 4D. Release Site Reservation（専用保持の開放）

| ID | 分岐 | 画面本文 | 秒 |
|---|---|---|---|
| REL-01 | 元SEADの使用予約がまだある間に開放 | `SAM site reservation released.`<br>`Available to other wings after SEAD settlement.`<br>`Cleanup after 30 minutes without a reservation.` | 20 |
| REL-02 | 元SEADの使用予約解消後に開放 | `SAM site reservation released.`<br>`Available to all wings via 'Task: DEAD'.`<br>`Cleanup after 30 minutes without a reservation.` | 20 |

保持元WingのF10操作。複数保持なら地域名付き個別メニュー。
開放操作でSEADの精算・帰還は変化しない。未予約30分の期限切れと削除には画面通知なし。
この30分はミッション時刻で、使用中assignmentがなくなってからの未予約時間。

## 5. Task: DEAD（保持／開放されたSiteを次の任務で取得）

| ID | タイミング・分岐 | 画面本文 | 秒・回数 |
|---|---|---|---|
| DEAD-00 | 取得可能なSiteがない | `No preserved SAM sites available for DEAD.` | 15秒、操作ごと。任務は開始しない |
| DEAD-01 | Site取得と準備に成功 | `DEAD mission accepted.` | 10秒、1回 |
| DEAD-02 | DEAD-01直後、同じ受注処理内 | 下のSiteブリーフィング | 60秒、自動は1回 |
| DEAD-03 | 全員空中で受注ならDEAD-02直後。地上受注なら全員離陸検出時 | `DEAD TRAINING START`<br>`Objective: destroy all remaining SAM site vehicles; then RTB.` | 25秒、1回 |
| DEAD-04 | 受注時に固定した残存対象を全破壊 | 下の達成本文 | 20秒、1回 |

DEAD-02:

```text
DEAD MISSION
TARGET SITE: <SAM機種>
SITE LOCATION: <Site実配置基準点のDDM座標>
STATUS: Primary radar destroyed
OBJECTIVE: Destroy all remaining SAM site vehicles.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

レーダー破壊ではなく抑制済みなら `STATUS: Previously suppressed`。
Site座標は車両ごとの座標ではない。保持Siteでも他Wingへ開放済みSiteでも通知本文は同じ。

DEAD-04:

```text
DEAD Objective Complete
SAM site destroyed.
Return to base.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

地上待機中の専用画面通知はなく、人数・残数・全員離陸待ちはDEBUGに残る。
敵は既存の実体を使用し、再生成や20秒待ちはない。部分撃破の自動通知もなく、現在残数はStatusにも出さない。
未達成の着陸では精算しない。同じ機体で再武装・再出撃できる（Immediate DEADの未達帰還とは異なる）。

## 6. 全任務共通の個人精算・Abort

### 6A. 表示の組み立て（20秒、参加者ごと1回）

通常は次の本文を元任務Groupへ送る。MP2なら各人の精算が別々に表示される。

```text
<Intercept / CAP / SEAD / DEAD / Strike / Air Interdiction> <結果>: <参加者名>
<理由>
Points: +<今回加算>
Total Score: <累計>
<保存状態>
```

| 分岐 | 結果 | 理由の正確な本文 | 通常加算 |
|---|---|---|---|
| 目標達成後、有効な安全帰還が確定 | `RTB_SUCCESS` | `Safe recovery confirmed (100%).` | 150 |
| 目標達成後、帰還確定前に事故イベント | `RTB_FAILURE` | `<事故名> before safe recovery (60%).` | 90 |
| 目標達成前に事故イベント | `FAILED` | `<事故名> before primary completion (0 points).` | 0 |
| 個別 `Abort Sortie` | `ABORT` | `Individual sortie aborted. No reward.` | 0 |
| 全体 `Abort Mission` | `ABORT` | `Wing mission aborted. No reward.` | 各0 |
| CAPの監視／生成処理が失敗 | `FAILED` | `CAP setup/spawn failed. No reward.` | 各0 |
| Follow-on DEADの生成前予約が機体変更等で解除 | `FAILED` | `DEAD reservation cancelled. No reward.` | 各0 |

`<事故名>` は受け取った `Crash` / `Dead` / `PilotDead` / `Ejection` / `UnitLost`。
同一参加者の重複事故では二重精算通知を出さない。
未生成のIntercept / SEADは参加者の採点IDがまだないため、Abort本文は見出し＋理由だけでPoints等は付かない。
全体Abort時、CAP以外で敵実体が未設定なら、さらに `<カテゴリ> reservation cancelled.` を10秒表示する。
Follow-on DEADは地上受注時から採点IDを持ち、既存敵実体もあるため、同じ未生成扱いではない。

### 6B. Immediate DEADの追加行と加算

見出しは元の `SEAD <結果>: <名前>`。通常精算の `Points` の前に以下を加える。

```text
SEAD Points: +<SEAD分>
DEAD Points: +<DEAD分>
```

| 分岐 | 画面の見出し結果 | SEAD / DEAD / 合計 |
|---|---|---|
| DEAD未達で安全帰還 | `SEAD RTB_SUCCESS` | 150 / 0 / 150 |
| DEAD達成後に安全帰還 | `SEAD RTB_SUCCESS` | 150 / 150 / 300 |
| DEAD未達で事故 | `SEAD RTB_FAILURE` | 90 / 0 / 90 |
| DEAD達成後に事故 | `SEAD RTB_FAILURE` | 90 / 90 / 180 |
| 個人／全体Abort | `SEAD ABORT` | 0 / 0 / 0 |

理由文は6Aと共通。未達DEADの0点について追加の説明文は出ない。
UCID不明の精算ではPoints・Total Score・保存状態・SEAD/DEAD内訳の代わりに
`Unscored sortie (UCID unavailable).` だけを付ける。

### 6C. 帰還時に何も表示しない分岐

未達成の通常任務での着地、接地検出、`LANDING_CHECK` 開始、10秒の停止確認、復行／ボルター、再武装、再離陸は自動通知なし。
未達成帰還では通常任務を継続し、ロックを維持する。Immediate DEADのみ6Bの未達帰還精算がある。
全参加者終了による任務ロック解除・敵Cleanupにも画面通知はない。

## 7. 手動で呼び出す情報

### 7A. Mission Status（公開済み情報の再表示）

表示済みの本文を任務recordの `publicReport` に保存し、手動操作でそのコピーを再表示する。
座標・指示を見返す用途とし、現在の敵やレーダー・Siteを照会して新しい情報を付けない。

| 対象・段階 | 再表示する本文 | 秒（初期設定） |
|---|---|---|
| 有効任務なし | `Intercept: Idle.` / `SEAD: Idle.` / `DEAD: Idle.` / `CAP: Idle.` / `Strike: Idle.` / `Air Interdiction: Idle.` の6行 | 10 |
| Intercept離陸待ち・生成待ち | INT-01の公開済み待機通知。生成カウントダウンは付けない | 10 |
| Intercept開始後 | INT-02の `Intercept MISSION START` | 15 |
| Intercept達成後 | INT-03の達成結果と帰還指示 | 20 |
| Strike受注後・攻撃中 | STRIKE-02T/PのTOO施設DDMまたはPB目標DMS＋標高・破壊指示・報酬・人数 | 60 |
| Strike達成後 | STRIKE-03の達成・帰還指示だけ（座標なし） | 20 |
| Air Interdiction受注後・攻撃中 | AI-02の周回中心DDM・3両破壊指示・報酬・人数 | 60 |
| Air Interdiction達成後 | AI-03の達成・帰還指示だけ（座標なし） | 20 |
| CAP受注後・哨戒中 | CAP-02の空域座標・目的・人数・報酬。進捗・出現有無・残敵を追加しない | 60 |
| CAP達成後 | CAP-08の達成結果と帰還指示だけ（座標なし） | 20 |
| SEAD計画中 | SEAD-01の受注・`Mission planning in progress.`。MODE・SAM機種・PBコード・検査回数はまだ出さない | 10 |
| SEAD計画確定後・離陸待ち | SEAD-02T/Pの公開済み座標ブリーフィング（報酬・人数も含む） | 60 |
| SEAD開始後 | SEAD-02T/P＋SEAD-03の公開済み開始・目標指示 | 60 |
| SEAD達成後・Preserve/Release後 | SEAD-04D/Sの達成結果・帰還指示だけ（座標なし） | 20 |
| Immediate DEAD継続後 | IMM-01の公開済み本文。前段SEADの推定座標は重ねない | 60 |
| Immediate DEAD達成後 | IMM-02の達成結果・帰還指示だけ（座標なし） | 20 |
| Follow-on DEAD地上受注・離陸待ち | DEAD-02の受注時ブリーフィング | 60 |
| Follow-on DEAD開始後 | DEAD-02＋DEAD-03の開始・目標指示 | 60 |
| Follow-on DEAD達成後 | DEAD-04の達成結果・帰還指示だけ（座標なし） | 20 |

目標達成前はブリーフィングと開始通知を空行で区切る。達成時は古い座標ブリーフィングと開始通知を外し、達成・帰還通知だけを保持する。
新しい座標ブリーフィングは前段のブリーフィング・開始／達成通知を置き換える。
Preserve/Release、個人精算、受注拒否、エラー、CAP進捗／停止／再開通知は、この再表示用情報を上書きしない。

IMM-01に含まれる `Remaining targets` はContinue時に公開した値をそのまま再表示する。
現在の残数に更新しない。Follow-on DEADでは受注時ブリーフィングに残数がないため、Statusにも追加しない。
目標達成前の公開済み `STATUS: Primary radar destroyed` / `Previously suppressed` は当時の履歴として残す。

Wing名・長機・内部phase・参加者別状態・精算・生成予定時刻・レーダー状態／OFF秒数・現在の敵残数・Site/予約状態は追加しない。
Statusはブリーフィングを再生成せず、座標の再計算・抽選・目標観測・Site Refresh・採点を行わない。
同じGroupまたは搭乗中UCIDに紐づく複数任務がある場合、対象任務の公開済み本文だけを空行で結合する。他Wingの無関係な情報は混ぜない。

表示時間は保持した各本文の表示時間の最大値（最低10秒）。座標付きは公開時の `coordinateBriefingSeconds` を引き継ぐ（初期60秒、90秒設定なら90秒）。
通常は到達しないが、任務に公開済み本文がまだない場合は `Mission briefing unavailable.` を10秒表示し、内部状態から補完しない。
任務全員終了後はIdleに戻り、過去任務の本文は復元しない。

### 7B. Player Statistics（25秒）

現在搭乗中の人間ごとに以下を空行区切りで表示し、最後に保存状態を1回付ける。

```text
PLAYER STATISTICS: <名前> [<機体名>]
Total Score: <累計>
Career Points: <累計>
Settled Missions: <件数>
Primary Success: <件数>
RTB Success: <件数>
Recovery Failure: <件数>
Death Count: <件数>
<保存状態>
```

UCID不明者は `PLAYER STATISTICS: <名前>` と `UCID unavailable; unscored.` の2行。
任務カテゴリ別Score、Abort数、未達成失敗数はこの画面には表示しない。

### 7C. 保存状態の可変行

| 状態 | 正確な本文 |
|---|---|
| 保存設定OFF | `Session only; persistence disabled.` |
| Hook未接続 | `Session only; persistence hook not connected.` |
| 保存エラーあり | `Persistence unavailable; scores not confirmed saved.` |
| 確認待ち・未保存revisionあり | `Persistence pending; not yet saved.` |
| 最新revisionの保存確認済み | `Persistent scores saved.` |

精算とStatisticsでその時点の1行を付ける。Hook接続・保存成功・保存エラー発生だけで新たな画面通知は送らない。

## 8. 受注拒否・取り消し・エラー

以下はそれぞれ独立した画面通知。人数分に結合するUCID警告を除き、原則1操作／検出あたり1回。

| 分岐・条件 | 正確な本文 | 秒 |
|---|---|---|
| 同Wing／参加UCIDの任務が計画・待機中 | `<カテゴリ> mission is already armed. Wing assignment blocked.` | 10 |
| 同Wing／参加UCIDの任務が実行・帰還待ち中 | `<カテゴリ> mission is already active (including return to base). Wing assignment blocked.` | 10 |
| Group不在（宛先Groupなしなら画面送信なし） | `Player group unavailable.` | 10 |
| 人間搭乗者なし | `At least one human pilot is required.` | 10 |
| 操縦者不明 | `Human pilot unavailable.` | 10 |
| 陣営／機種が対象外 | `A BLUE F/A-18C player aircraft is required.` | 10 |
| 機体識別取得失敗 | `Player aircraft identity unavailable.` | 10 |
| 同一UCIDが参加2機に重複 | `The same UCID cannot occupy two participating aircraft.` | 10 |
| UCID APIなし、受注は継続 | `<名前>: Server UCID API unavailable; this sortie is unscored.` | 15 |
| UCID照合失敗、受注は継続 | `<名前>: UCID could not be verified; this sortie is unscored.` | 15 |
| CAP中心が距離内にない | `No CAP areas within 40-100 NM. Change position and retry.` | 20 |
| CAP受注準備例外 | `ERROR: CAP setup failed. See DCS log; select 'Task: CAP' to retry.` | 20 |
| Intercept敵生成失敗 | `ERROR: Intercept enemy spawn failed. Select 'Task: Intercept' to retry.` | 15 |
| SEAD受注準備例外（距離内候補なしもここ） | `ERROR: SEAD setup failed. See DCS log; select 'Task: SEAD' to retry.` | 15 |
| SEAD生成失敗・計画点が生成直前に不適合 | `ERROR: SEAD spawn failed. Select 'Task: SEAD' to retry; see DCS log.` | 20 |
| SEAD計画中に参加機操作不可 | `SEAD selection cancelled. Player aircraft changed or unavailable.` | 10 |
| Intercept / SEAD / DEADの開始前に参加機操作不可 | `<カテゴリ> reservation cancelled. Player aircraft changed or unavailable.` | 10 |
| Follow-on DEAD準備失敗 | `ERROR: DEAD setup failed. Site reservation rolled back; see DCS log.` | 20 |
| Continue / Preserveの古い・無効な操作 | `Follow-on DEAD is no longer available for this SEAD mission.` | 10 |
| 開放の古い・無権限操作 | `This site reservation is no longer available to release.` | 10 |
| 終了済み個人Abort | `This sortie is already closed.` | 10 |
| 元Wing外で以前の任務が複数あり全体Abort先を特定不可 | `Multiple earlier wing missions found. Use the named Abort Sortie command.` | 10 |
| 登録参加者による操作ではないAbort | `Only registered mission participants may abort this mission.` | 10 |
| 別Wingから他人を個人Abort | `Only your own sortie may be aborted from another wing.` | 10 |
| 別Wingから複数人任務を全体Abort | `Use Abort Sortie for your own pilot; wing abort is available in the original wing.` | 10 |
| 保護呼出内の未処理例外 | `ERROR: <操作名>. See DCS log.` | 15 |

UCID警告は各人の警告行を改行で結合し、任務受注通知より先に表示する。人間取得自体が失敗した場合は受注しない。
保護呼出の汎用ERRORには同一原因を1回に抑える仕組みがなく、監視で例外が続くと1秒ごと、メニュー走査なら走査のたびに再表示され得る。Groupなしの内部操作はログだけとなる。
Follow-on DEADの開始前予約解除では、各人に6AのFAILED精算を出した後、共通の予約取消通知も出す。
有効なFollow-on判定後でも保持者を取得できない／Preserve処理がfalseになる場合、Preserveには失敗専用の通知がない。
任務なしのAbort Missionは、7AのIdleの6行を10秒表示する。

### SEAD配置候補50回不適合（25秒）

```text
ERROR: SEAD placement failed.
Area: <地域名>
No safe site in 50 attempts.
<拒否理由ごとの件数>
Largest height range sampled before rejection: <標高差> m.
Select 'Task: SEAD' to retry.
```

拒否理由行は件数があるものだけ出す。`Uneven terrain (height range > 20 m): <件数>` / `Not LAND: <件数>` /
`Outside area: <件数>` / `Near obstacles: <件数>` / `Near another reserved site: <件数>` / `No location returned: <件数>`。
標高差の行も該当観測があるときだけ。TOOでも機種・座標・PBコードは出さない。

配置検査API例外なら理由の代わりに次の本文（25秒）:

```text
ERROR: SEAD placement failed.
Site check error. See DCS log.
Select 'Task: SEAD' to retry.
```

## 9. 全体通知・ログだけの遷移

| タイミング | 全体へ出す正確な本文 | 秒 |
|---|---|---|
| 初期化成功 | `Dynamic Training ready. Wing UCID scoring.`＋改行＋`Persistence initialization pending.` | 10 |
| 同じbundleを再ロード | `Dynamic Training is already loaded.` | 10 |
| MOOSE未ロード | `ERROR: Load MOOSE before DynamicTraining.` | 15 |

起動時の保存状態は通常 `Persistence initialization pending.`。
設定OFF等では7Cの該当行になる。起動通知で保存成功を保証しない。

画面に出さないがDCSログに残る主な遷移:

- 登録機体・Wing、受注方式、離陸カウントダウン開始／リセット。
- Interceptの実距離・高度・HOT・機種／機数・編隊・Pilots。
- CAPの抽選空域・敵テンプレート・出現予定累計時刻・実生成情報。
- SEADの計画試行数・HARM操作指示・発信状態変化・観測不能。
- Follow-on DEADの地上予約待ち・受注残数・開始時ブリーフィング再記録。
- DEADの対象観測不能、SAM Siteの保持者切断／未予約期限切れ／Cleanup。
- 各人の精算・任務Close、敵削除待ちと再試行、保存Hookの接続・保存確認・エラー。

任務と無関係なDCSのATC・地上クルー・標準戦績/BDA・MOOSE自身の表示は、このカタログの対象外。
画面右側に出るすべての表示が、この訓練スクリプトの通知というわけではない。

## 10. 表示を修正するときに確認したい箇所

以下は現状の観察。まだ変更案を実装したものではない。

| 箇所 | 現状 | 見直す論点 |
|---|---|---|
| CAP / Follow-on DEAD受注 | 10秒通知と60秒ブリーフィングを直後に送る | 1つにまとめるか |
| 空中SEAD受注 | 受注→計画ブリーフィング→開始25秒が近接する | 情報の重複と読み切れる量 |
| CAP 100%・敵全滅済み | 100%通知と達成通知を同じ監視で送る | 達成通知だけで十分か |
| 達成通知 | 150点／帰還失敗90点を毎回説明 | 報酬説明を受注時・Statusへ寄せるか |
| Follow-on DEAD達成 | `Return to base.` と `Each pilot: return to a BLUE airfield or carrier.` が重複 | 帰還指示を1行にするか |
| SEAD→DEADメニュー | 選択肢が増えるが案内はない | 継続・保持の選択肢を達成通知で知らせるか |
| Immediate DEAD未達帰還 | SEAD成功の通常理由＋DEAD0点だけ | DEADが個人終了したことを明示するか |
| Mission Status | 達成前は公開済み座標＋開始指示、達成後は達成・帰還指示だけを再表示 | 現行仕様は7A。未公開の状態・残数を追加しない |
| 状態や見出し | `MISSION START` / `TRAINING START` / `Objective Complete` / `PRIMARY OBJECTIVE COMPLETE` が混在 | 名称・大文字・状態表示を統一するか |
| 地上待機・再武装 | 無通知の遷移が多い | 必要な節目だけ補うか |
| SEAD距離内候補なし | 通常拒否ではなく汎用ERROR | CAPと同じ拒否説明へ揃えるか |

## 実装参照・確認範囲

- [main.lua](../src/main.lua): 受注、開始、達成、分岐、精算、Abort、メニュー、監視・イベント。
- [notifications.lua](../src/notifications.lua): 宛先・既定10秒・MESSAGEログ・保護呼出エラー。
- [mission_report.lua](../src/mission_report.lua): Mission Status / Statisticsの組み立てと表示時間。
- [cap.lua](../src/cap.lua): CAPブリーフィング・進捗・状態。
- [sead.lua](../src/sead.lua) / [sead_objective.lua](../src/sead_objective.lua): TOO/PBブリーフィング・配置失敗・Emitter状態。
- [dead.lua](../src/dead.lua): DEADブリーフィングと正確なSite基準座標。
- [recovery.lua](../src/recovery.lua): 帰還確認。専用画面通知を送らないことも確認。
- [missions.lua](../src/missions.lua) / [player.lua](../src/player.lua): 二重受注拒否と搭乗者・UCIDの警告。
- [persistence.lua](../src/persistence.lua) / [config.lua](../src/config.lua): 保存状態と時間・報酬の初期値。

本文・呼出順・分岐はソースと照合した。DCS内の同時通知の積み重なり方・読みやすさを今回実測したものではない。

## 11. Strike（固定施設）

| ID | タイミング | 本文 | 秒 |
|---|---|---|---:|
| STRIKE-01 | 抽選・生成成功時。地上／空中共通 | `Strike mission accepted.` | 10 |
| STRIKE-02T/P | STRIKE-01直後に1回 | 下記の方式別ブリーフィング | 60 |
| STRIKE-03 | TOOの従来必要数、またはPBの指定司令部/タンク/弾薬庫1個を破壊 | 下記達成・帰還通知 | 20 |
| STRIKE-04 | 近い2施設が使用不可 | `No available Strike targets among the two nearest sites. Try again later.` | 20 |
| STRIKE-05 | 受注準備・生成・座標整形の失敗 | `ERROR: Strike setup failed. See DCS log; select 'Task: Strike' to retry.` | 20 |

STRIKE-02T（従来から見出しだけ変更、座標・目標・7個生成は維持）:

```text
STRIKE MISSION (TOO)
TARGET AREA: <施設基準点のDDM、分の小数3桁>
OBJECTIVE: <Destroy any 2 of the 4 storage containers / Destroy the command center / Destroy both trucks>; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

STRIKE-02P（選んだ目標そのものの座標と地表標高）:

```text
STRIKE MISSION (PB)
TARGET AREA: <選んだ目標のDMS、秒の小数2桁>, <整数> ft MSL
OBJECTIVE: <Destroy the command center / Destroy the fuel tank / Destroy the ammunition depot>; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

TOO/PBは各1/2、近い2施設の使用可能な1つ、その方式の3目標は各1/3。受注後は固定。PBは施設一式9個を生成するが、指定1個だけ破壊が必要。全54原本を起動時に除去する。PB標高が不明なら生成せず解除する。スモーク基準点はTOOでは司令部、PBでは指定目標。

STRIKE-03:

```text
Strike Objective Complete
Assigned targets destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

Statusは達成前にSTRIKE-02T/Pを同じ本文で再表示し、達成後はSTRIKE-03だけを20秒表示する。現在残数・未選択施設・抽選候補・予約を追加しない。途中撃破・全員離陸・生成待ちの自動通知はない。精算は6章の共通通知でカテゴリ名Strikeを使用する。全員終了後の削除失敗は予約を維持して再試行し、精算通知を繰り返さない。詳細は[STRIKE.md](STRIKE.md)。

### 11A. Strikeの任意スモーク

| ID | タイミング | 本文 | 秒 |
|---|---|---|---:|
| STRIKE-06 | ACTIVE中のMark Strike Target選択で点煙成功 | `Strike target marked with RED smoke.`＋改行＋`Smoke is 50 m north of the target; lasts 120 seconds.` | 10 |
| STRIKE-07 | 煙の停止前に再要求 | `Strike target already marked. Try again later.` | 10 |
| STRIKE-08 | 古いcallback・操作資格喪失 | `Strike target marking is no longer available.` | 10 |
| STRIKE-09 | 点煙APIの例外・拒否 | `ERROR: Strike target smoke failed. See DCS log; retry later.` | 15 |

色・距離・時間は初期設定。自動点煙はせず、目標の北50 mの地表へ任意要求で赤煙を1本出す。約120秒後・達成・全員終了で無通知停止する。停止後は再要求可能。点煙通知はStatusを上書きせず、座標・得点・対象・基地予約は変えない。他プレイヤーにも見える視覚効果。停止失敗は5秒ごとに再試行し、個人精算・基地解放を妨げない。F10項目が多い場合はMoreから続きへ進む。

## 12. Air Interdiction（移動車列）

| ID | タイミング・分岐 | 本文 | 秒 |
|---|---|---|---:|
| AI-01 | 近い2地域からの抽選・生成成功。地上／空中共通 | `Air Interdiction mission accepted.` | 10 |
| AI-02 | AI-01直後、1回だけ | 下記の中心座標ブリーフィング | 60 |
| AI-03 | 今回生成した3両すべての破壊 | 下記の達成・帰還指示 | 20 |
| AI-04 | 近い2地域が使用不可 | `No available Air Interdiction routes among the two nearest sites. Try again later.` | 20 |
| AI-05 | 準備・生成・座標整形に失敗 | `ERROR: Air Interdiction setup failed. See DCS log; select 'Task: Air Interdiction' to retry.` | 20 |

```text
AIR INTERDICTION MISSION
TARGET AREA: <周回WPの外接矩形中心DDM・分の小数3桁>
OBJECTIVE: Destroy all 3 convoy vehicles; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

```text
Air Interdiction Objective Complete
All 3 convoy vehicles destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

AI-02はcoordinateBriefingSeconds設定を使う。攻撃中のStatusはAI-02と同じ本文、達成後は座標を外したAI-03だけ20秒。部分撃破・移動開始・周回・散開の自動通知はなく、車列の現在位置・方向・残数は追加しない。個別精算は共通通知にカテゴリ名Air Interdictionを使う。削除再試行中も精算通知を繰り返さない。詳細は[AIR_INTERDICTION.md](AIR_INTERDICTION.md)。

## training-13の観測・削除修正

通常の画面本文とStatus再表示は維持。帰還観測失敗は停止計測を再開しログだけへ記録する。同Wingの別参加者は帰還評価を続ける。監視間隔が初期2秒を超えた場合も帰還10秒・SEAD30秒の連続計測を再開する。部分生成後の削除待ちはログと再試行で管理し、失敗した任務のロック解放後に成功・報酬を追加しない。

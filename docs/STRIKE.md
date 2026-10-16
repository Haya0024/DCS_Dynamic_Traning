# Strike（固定地上目標）

実装仕様: 2026-10-16。DCS内での生成・実射・精算は確認待ち。

## 受注と抽選

`Task: Strike` は受注時の登録参加者の長機位置を基準とする。MP2では機体番号が最小の操縦中機を長機とし、途中参加者・AIを加えない。既存のWing/UCIDロックを生成前に取得する。

対象はMEに配置したSITE01～05と、それぞれに対応する赤基地。基地中心（MOOSE AIRBASEの現在位置）までの水平距離で並べ、近い2基地に限定する。2基地から使用可能な基地を等確率で1つ選び、燃料施設・弾薬庫・倉庫を各1/3で抽選する。1基地だけ使用中ならもう一方を使い、両方使用中なら採点なしで解除する。3番目の基地へ回さない。登録基地がREDでなければ候補外とし、候補が1基地のみならその基地を使う。移動・離陸・長機交代では再抽選しない。

| Site | 基地 | MEテンプレート名（各ユニット名は末尾`-1`） |
|---|---|---|
| SITE01 | Damascus | TPL_STRIKE_SITE01_TANK_01～03 / AMMO_01 / WAREHOUSE_01 |
| SITE02 | Palmyra | TPL_STRIKE_SITE02_TANK_01～03 / AMMO_01 / WAREHOUSE_01 |
| SITE03 | Bassel Al-Assad | TPL_STRIKE_SITE03_TANK_01～03 / AMMO_01 / WAREHOUSE_01 |
| SITE04 | Hama | TPL_STRIKE_SITE04_TANK_01～03 / AMMO_01 / WAREHOUSE_01 |
| SITE05 | Gecitkale | TPL_STRIKE_SITE05_TANK_01～03 / AMMO_01 / WAREHOUSE_01 |

Strikeの座標はJDAM/JSOWのPP直接入力用にDMS（度・分・秒、秒の小数2桁）とする。COORDINATE:ToStringLLDMSへLL_Accuracy=2を明示し、全体の表示設定に依存させない。CAP/SEAD/DEADのDDMは変更しない。

位置・向き・種類はMEだけを正とし、Luaには座標を複製しない。起動時にMOOSEのStaticテンプレートを取得し、25個の原本をイベントなしで除去する。原本除去が確認できるまでその基地は使用しない。欠落・不正なテンプレートの基地は使用不可とし、他カテゴリを停止しない。

受注時に選んだ施設だけを同位置・同方向にSPAWNSTATICで生成する。生成物は任務別の一意な名前・IDを使い、元テンプレート名を変更しない。座標を合わせるための移動・地形への再配置は行わない。生成途中の失敗でも生成済み参照を保持して削除を再試行する。

## 状態・達成・終了

受注準備 → ACTIVE（地上でも即生成）→ 全目標破壊でRTB_PENDING → 全参加者精算で終了。離陸待ち・20秒生成待ちは設けない。達成前にRTBしても任務は継続する。

燃料施設は3基すべて、弾薬庫・倉庫は各1棟の破壊を要求する。Lifeが残る損傷を破壊扱いしない。対象の明示死亡イベントまたは同一実体の死亡観測を使い、nil・例外・不正値・別IDを全滅根拠にしない。第三者の攻撃による指定目標の破壊も任務達成となる（撃破者限定ではない）。

基地単位で使用予約し、異なるWingによる同じ基地への同時生成を防ぐ。全員終了までは予約と残存目標を維持する。終了後は生成物を削除し、削除に失敗した場合は予約を維持して5秒ごとに再試行する。削除完了後に予約解除する。目標達成直後には削除せず、保持・次Sortie継続は設けない。

各自の帰還150、達成後事故90、達成前事故・Abort0。共有達成・個人精算・帰還条件は既存任務と同じ。Strike Scoreを独立集計し、Total/Careerと既存統計を更新する。保存schema3でstrikeScoreを追加し、schema1/2はStrike=0で読む。MissionとサーバーHookを同時更新し、Hook再導入とDCS再起動が必要。進行中任務・予約・生成物は再起動後に復元しない。

## 表示

受注通知10秒、その後の座標ブリーフィングは共通coordinateBriefingSeconds（初期60秒）で1回。本文は見出し・座標と標高の同一行・破壊指示・報酬・人数の5行とし、TARGET BASE / TARGET / TARGET ELEVATIONの独立行は表示しない。

```text
Strike mission accepted.
```

```text
STRIKE MISSION
TARGET LOCATION: <誤差を加えないDMS・秒の小数2桁>, <地表標高> ft MSL
OBJECTIVE: Destroy all 3 fuel tanks; then RTB.
Reward per pilot: 150 points.
Registered pilots: 1.
```

燃料施設の案内点は3基の水平座標の中心。弾薬庫・倉庫は各物体のME配置点。標高は案内点の地表標高で、建物の屋上高度ではない。1任務で表示する座標は1組だけ。中心狙いの1発で3基全滅することは保証せず、未破壊分は追加攻撃する。

Mission Statusは公開済み本文をそのまま再表示し、残数・内部予約・抽選候補・未選択目標を追加しない。達成後は座標を外し、公開済み達成・帰還通知だけを20秒表示する。全員終了後はIdle。

## 任意の目標スモーク

StrikeがACTIVEで、受注Wingに操縦中・未精算の登録参加者がいる場合だけF10へ `Mark Strike Target` を表示する。選択時に赤煙を目標案内点の北50 mの地表へ1本出し、約120秒後に停止する。燃料は3基の中心が基準。座標・抽選・目標・採点は変更せず、自動点煙はしない。色・北オフセット・表示時間はConfig.strike.smokeで管理する。スモークはDCS内の実体なので他プレイヤーからも見える。F10項目が増えた場合はMoreで続きへ進める。1ページはコマンド9件＋Moreを上限とし、MP2の個人中止も到達可能にする。

成功通知は `Strike target marked with RED smoke.` と次行 `Smoke is 50 m north of the target; lasts 120 seconds.` を10秒表示する。煙が停止するまでは連打しても追加せず、`Strike target already marked. Try again later.` を10秒表示する。停止後は再度要求できる。Mission Statusへ点煙通知・残数・煙の状態は追加しない。

達成時と全員終了時に煙を停止する。古いメニューcallbackは任務・状態・Wing・操縦中の登録参加者を再照合し、無効なら `Strike target marking is no longer available.` を10秒表示して終了する。煙APIの失敗は `ERROR: Strike target smoke failed. See DCS log; retry later.` を15秒表示し、任務・得点を維持する。停止失敗は共通監視で5秒ごとに再試行する。煙の寿命は基地予約・目標削除から分離し、停止失敗で帰還精算や基地解放を妨げない。

自動検証はscripts/Test-Strike.lua、実.mizの25テンプレートと基地対応はscripts/Test-StrikeMission.ps1で確認する。実DCSでは地上/空中受注、PB入力、燃料3基判定、3Dの埋まり・重なり、MP2個人精算、並行Wing、再受注とHook保存を確認する。

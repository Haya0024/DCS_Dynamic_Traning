# Strike（PB精密攻撃・TOO捜索攻撃）

実装仕様: 2026-10-27 / training-12。PB/TOO分岐と追加建物のDCS内生成・実射・精算は確認待ち。

## 受注と抽選

F10は共通の`Task: Strike`。受注時の人間参加者を固定し、機体番号が最小の操縦中長機の位置を使う。Wing/UCIDロックを先に取得する。受注ごとにTOO/PBを各1/2で抽選し、その方式を固定する。別方式への自動切替はしない。

SITE01～06の司令部配置点までの水平距離で近い2施設を先に固定し、その方式で使用可能な施設を等確率で1つ選ぶ。同距離はSite ID順。両方使用不可なら採点なしで解除し、3番目へ回さない。空港所有権・距離上下限では選別しない。次に方式ごとの目標3種類を各1/3で抽選する。受注後の移動・離陸・長機交代・Statusでは再抽選しない。

| 方式 | 目標候補 | 達成条件 |
|---|---|---|
| TOO | コンテナ02～05 | 従来どおり4個のうち任意2個。2個を隠れて指定しない |
| TOO | 司令部01 | 1個破壊 |
| TOO | トラック06・07 | 2両とも破壊 |
| PB | 司令部 | 選んだ司令部1個を破壊 |
| PB | 燃料タンク | 選んだTank 3を1個破壊 |
| PB | 弾薬庫 | 選んだAmmunition depotを1個破壊 |

## MEテンプレートと生成

各Siteは次の9個。ME名・位置・向きを正とし、Luaへ座標を複製しない。実ユニット名の末尾-1の有無はMOOSEのStaticNameから解決し、名前を変更しない。

| MEグループ名の例 | 実TypeName | 個数 | 受注時生成 |
|---|---|---:|---|
| TPL_CMD_SITE01_01 | .Command Center | 1 | 両方式 |
| TPL_CONT_SITE01_02～05 | container_20ft | 4 | 両方式 |
| TPL_TRUCK_SITE01_06～07 | Ural-375 | 2 | 両方式 |
| TPL_TANK_SITE01_01 | Tank 3 | 1 | PBのみ |
| TPL_AMMO_SITE01_01 | .Ammunition depot | 1 | PBのみ |

起動時に全54原本を取得・イベントなしで除去し、未受注の追加建物が常時残らないようにする。原本除去を確認するまではそのSiteを使用しない。取得済み原本は一部構成が不正でも除去する。元7構成の欠落・非RED・死亡済み・不正Typeは両方式を無効化し、PB追加2構成だけの不備はそのSiteのPBを無効化する。司令部の位置が分かる無効Siteも距離順に残すため、遠方への黙った切替をしない。位置不明のSiteは順位付けできない。他カテゴリは停止しない。

地上でも即ACTIVE・生成。TOOは従来の7個を維持し、追加タンク・弾薬庫は生成しない。PBは選んだ施設一式9個を同位置・同方向へSPAWNSTATICで生成し、指定1個だけを達成対象にする。周辺設備の破壊は必須にしない。任務別名・新規IDを使い、再配置・Life補正・Staticトラックの暖機/移動はしない。生成後例外も作成済み参照を保持して回収する。

## 座標と画面表示

受注成功は`Strike mission accepted.`を10秒、続いて以下の5行をcoordinateBriefingSeconds（初期60秒）で1回。方式を別行で追加しない。

TOOは見出しだけ変更。司令部配置点のDDM（分の小数3桁）1組、誤差追加なし、標高なしを維持する。

```text
STRIKE MISSION (TOO)
TARGET AREA: <従来の施設基準点DDM・分の小数3桁>
OBJECTIVE: Destroy any 2 of the 4 storage containers; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

TOOの他候補は`Destroy the command center`または`Destroy both trucks`。PBは抽選した目標そのもののME配置点をDMS（度・分・秒、秒の小数2桁）にし、その地点の地表標高をft MSLの整数へ丸めて同じTARGET AREA行に付ける。共通司令部位置やモデル屋根の高さへ置き換えない。MOOSEへLL_Accuracy=2を明示し、地表標高の観測不能・不正値や座標整形失敗では生成せず解除する。標高を0へ代替しない。

```text
STRIKE MISSION (PB)
TARGET AREA: <目標そのもののDMS・秒の小数2桁>, <整数> ft MSL
OBJECTIVE: Destroy the fuel tank; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

PBの他候補は`Destroy the command center`または`Destroy the ammunition depot`。PBはJDAM/JSOWのPP入力向けの表示だが、任務方式名はユーザー指定どおりPBとする。座標の精度は兵器の命中や一発での破壊を保証しない。

Mission Statusは公開済み本文のコピーだけを表示する。現在残数・内部予約・別候補を追加せず、座標や標高を再取得しない。達成後は座標と標高を外し、以下の既存本文だけ20秒。全員終了後はIdle。

```text
Strike Objective Complete
Assigned targets destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

候補なしは`No available Strike targets among the two nearest sites. Try again later.`、準備失敗は`ERROR: Strike setup failed. See DCS log; select 'Task: Strike' to retry.`を各20秒。方式・Site・対象数はDEBUGへ記録し、画面本文は共通MESSAGEログにも残す。

## 状態・達成・終了

受注準備→ACTIVE→必要数破壊でRTB_PENDING→全参加者終了。離陸待ちや20秒生成待ちはなく、未達成帰還は任務継続。plan.targetsとrequiredCountはTOOで4/1/2候補に対して2/1/2、PBで1に対して1。生成した対象の実体とIDを固定し、明示死亡・同一実体のLife0を数える。nil・例外・不正Life・別IDは残存扱い。同じ死亡の重複は増やさず、第三者の対象撃破も数える。

両方式ともMissions.strikeSitesで施設単位の排他を共有する。異なる施設では別WingのPB/TOOを並行可能。達成直後は残存物を削除せず、全員終了後に生成した7個/9個を全削除する。失敗時は予約を維持して5秒ごと再試行、実体削除確認後に解除する。保持・進行の永続化はしない。

各自150／達成後事故90／達成前事故・Abort0、共有達成・個人精算・共通帰還を維持する。PBも同じstrikeScoreへ加算する。保存schema4は変更せず、この変更によるサーバーHook更新は不要。

## 任意の目標スモーク

StrikeがACTIVEで、受注Wingに操縦中・未精算の登録参加者がいる場合だけF10へ `Mark Strike Target` を表示する。選択時にTOOでは従来の司令部案内点、PBでは抽選した目標そのものの北50 mの地表へ赤煙を1本出し、約120秒後に停止する。PBの点煙基準はブリーフィングの目標座標と一致させる。TOOの点煙位置は変更しない。座標・抽選・目標・採点は変更せず、自動点煙はしない。色・北オフセット・時間はConfig.strike.smokeで管理する。煙は他プレイヤーからも見える。各F10ページは9コマンド＋Moreを上限とする。

成功通知は `Strike target marked with RED smoke.` と次行 `Smoke is 50 m north of the target; lasts 120 seconds.` を10秒表示する。この通知のtargetはTOOの案内点またはPBの目標そのものを指す。停止前の連打は `Strike target already marked. Try again later.` を10秒表示し追加しない。停止後は再要求可能。点煙通知はMission Statusを上書きしない。

達成時と全員終了時にも停止する。古いcallbackは任務・状態・Wing・操縦中登録者を再照合し、無効なら `Strike target marking is no longer available.` を10秒表示する。煙API失敗は `ERROR: Strike target smoke failed. See DCS log; retry later.` を15秒表示し、任務・得点を維持する。停止失敗は施設予約・目標削除とは独立に5秒ごと再試行し、帰還精算や施設解放を妨げない。

## 検証

Test-Strike.luaでTOOの回帰とPB3目標・DMS2桁・目標地点標高・Status・排他・採点・失敗回収を模擬検証する。Test-StrikeMission.ps1は実.mizの54テンプレートを読み、6サイト×2方式×3目標の全36選択で生成位置・向き・指定目標・7/9個削除を確認する。地表標高APIは模擬であり、実地形上の標高、建物の3D重なり、PP実入力・実射・耐久・MP2はゲーム内確認待ち。全Luaスイートと結合検証後に既定.mizへSync/Checkし、登録済みLua以外のZIP内容保持を確認する。

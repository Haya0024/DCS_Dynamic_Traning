# SEAD全地域の実地形配置検査

更新日: 2026-10-09

全10地域×SA-6/SA-8の20組合せについて、各50点（合計1,000点）をMOOSEのGetRandomVec2で抽選する。成功後も50点まで続け、成功数・最初の成功回・拒否理由別の件数・観測エラーを記録する。適合点はVALID_POINTとしてDCS Vec2座標を診断ログだけに記録し、中心を調整する場合の根拠にする。

## 検査する条件

通常のSEAD計画と同じ `SEAD.CheckPlacement` を使い、テンプレートの実配置間隔、LAND、半径200 mと全車両点のZone内収容・高低差20 m以内、各車両と建物・静的物体・実行中ユニットの200 m離隔を確認する。SAMはSpawnしない。任務台帳・採点・保存bridgeを初期化しない。進行中の他WingのSite予約はない隔離環境で検査するため、混雑時の予約競合やSAMの交戦・実Spawn成功を保証するものではない。

元ミッションのTrigger・テンプレート・リソース対応表は変更しない。Build-SEADPlacementMission.ps1がbuild内の検査用コピーを作り、コピーのmain.luaだけを検査入口に置換して、通常のSync-Mission.ps1で既存DynamicTraining.luaへ結合する。元の実ミッションには検査自動実行を追加しない。

## 作成と実行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-SEADPlacementMission.ps1
```

地域を絞る場合は `-ZoneNames SEAD_ZONE_MORPHOU,SEAD_ZONE_NICOSIA_NORTH` を作成時に指定する。既知の候補名だけを指定し、対象地域数×2×50点の完了を確認する。

生成物は `build/SEAD_Placement_Check.miz`。通常のDCSでこのミッションを開始し、一時停止せず約8分半待つ。搭乗・離陸・攻撃は不要。1秒に最大2点を検査するので、1,000点には約500秒かかる。

隔離プロファイルでの起動補助は `scripts/Start-SEADPlacementCheck.ps1`。Saved Gamesに新しいDCS.SEADPlacementCheck-*を作り、通常のConfigやHook、scores.datをコピー・変更しない。直接ミッションを読み込む場合は `-SinglePlayer`、Steam版は `-SinglePlayer -ThroughSteam` によりSteamのコマンド起動を使う。直接DCS.exeを起動するとSteamのURL起動へ転送され、起動引数確認で待つことがある。確認待ちの古い要求が残っている場合は、実行中のゲームがない状態で `-RestartSteam` を追加してSteamの通常終了・再起動を使える。確認ダイアログの自動承認や認証設定の変更は行わない。ログ・プロセス確認は `-Status`、この検査に対応するDCSだけを終了する場合は `-Stop`。DCSの認証・Steam連携や起動状態によっては起動できないので、起動したことを検査完了としない。

## 結果の読み方

実行したDCSプロファイルのLogs/dcs.logへ `[SEADPlacementCheck]` を付けて出力する。

```text
[SEADPlacementCheck] START areas=10 templates=2 samplesPerPair=50; no SAM spawn or scoring
[SEADPlacementCheck] RESULT zone=SEAD_ZONE_AKKAR template=TPL_SEAD_SA6 checked=50 passed=12 firstSuccess=3 errors=0 rejected=non-LAND:8;uneven terrain:30
[SEADPlacementCheck] COMPLETE pairs=20 checked=1000 passed=... errors=0
```

上記のpassed・firstSuccess・拒否件数は書式の例で、実測結果ではない。RESULTが20行、各checked=50、COMPLETEのchecked=1000・errors=0を確認してから比較する。SETUP_ERRORやOBSERVATION_ERRORは観測・準備の失敗として扱い、地形不適合と混ぜない。

passedが1以上なら、その組合せでは今回の50点以内に安全配置可能な点が見つかったことを示す。passed=0は今回の抽選で見つからなかったことを示し、Zone内の全地点が不適という証明ではない。1回のランダム標本だけで常時成功を保証しない。結果と拒否理由を見て、必要ならZone中心・半径を調整して再検査する。

検査制御はTest-SEADのSEAD-63〜66で模擬検証する。全20組合せ・成功後も50点・全拒否・テンプレート欠落・観測例外・非Spawn・Config候補復元を確認する。模擬成功数は実地形の結果として扱わない。

## 2026-10-09 初回実DCS結果（追加6地域の半径5 NM）

DCS World Steam Edition 2.9.30.28738 / Syria terrain revision 7039 / training-6の配置条件。隔離プロファイルで--norenderと--mission-fileを使って実ミッションの地形・scenery APIを検査した。実行時間は09:11:49〜09:20:11 JST。20組合せ×50点=1,000点を完了し、適合350点・拒否650点・観測エラー0。

| 地域 | SA-6成功/50 | SA-8成功/50 | SA-6初回成功 | SA-8初回成功 |
|---|---:|---:|---:|---:|
| Palmyra | 24 | 23 | 2 | 1 |
| Salamiyah | 18 | 26 | 1 | 1 |
| Dumayr | 41 | 45 | 1 | 1 |
| Tabqa | 34 | 42 | 4 | 1 |
| Osmaniye | 21 | 23 | 2 | 1 |
| Islahiye | 0 | 0 | NONE | NONE |
| Kilis | 8 | 7 | 4 | 2 |
| Morphou | 2 | 5 | 15 | 19 |
| Nicosia North | 2 | 3 | 20 | 31 |
| Akkar | 10 | 16 | 5 | 5 |

9地域は両テンプレートで50点以内に適合点を発見。Islahiyeは両方0/50で、100点のうち96点を高低差超過で拒否した。この時点の中心位置は見直しが必要だった。Morphouは2/50・5/50、Nicosia Northは2/50・3/50と適合点が少なく、初回成功は最大31点目。両地域も中心・範囲の改善候補。今回の検査ではZone設定・半径を変更していない。

各地域の失敗率を確定する統計試験ではなく、1回の50点標本。診断で適合した点にSAMを実Spawnして交戦・配置姿勢まで確認したものではない。描画を無効にした実行中、GRAPHICSVISTAのmodel読み込み警告が複数出たが、配置判定APIの例外は0件だった。通常描画でのscenery/model状態と実Spawnは別途確認する。

| Zone / Template | 拒否理由別件数 |
|---|---|
| SEAD_ZONE_PALMYRA / TPL_SEAD_SA6 | near scenery/static/unit:2 / non-LAND:5 / uneven terrain:19 |
| SEAD_ZONE_PALMYRA / TPL_SEAD_SA8 | near scenery/static/unit:3 / non-LAND:5 / uneven terrain:19 |
| SEAD_ZONE_SALAMIYAH / TPL_SEAD_SA6 | near scenery/static/unit:2 / non-LAND:14 / uneven terrain:16 |
| SEAD_ZONE_SALAMIYAH / TPL_SEAD_SA8 | near scenery/static/unit:2 / non-LAND:11 / uneven terrain:11 |
| SEAD_ZONE_DUMAYR / TPL_SEAD_SA6 | non-LAND:6 / uneven terrain:2 / zone boundary:1 |
| SEAD_ZONE_DUMAYR / TPL_SEAD_SA8 | non-LAND:3 / uneven terrain:2 |
| SEAD_ZONE_TABQA / TPL_SEAD_SA6 | near scenery/static/unit:2 / non-LAND:11 / uneven terrain:3 |
| SEAD_ZONE_TABQA / TPL_SEAD_SA8 | near scenery/static/unit:1 / non-LAND:6 / uneven terrain:1 |
| SEAD_ZONE_OSMANIYE / TPL_SEAD_SA6 | non-LAND:13 / uneven terrain:16 |
| SEAD_ZONE_OSMANIYE / TPL_SEAD_SA8 | near scenery/static/unit:1 / non-LAND:6 / uneven terrain:20 |
| SEAD_ZONE_ISLAHIYE / TPL_SEAD_SA6 | non-LAND:3 / uneven terrain:47 |
| SEAD_ZONE_ISLAHIYE / TPL_SEAD_SA8 | non-LAND:1 / uneven terrain:49 |
| SEAD_ZONE_KILIS / TPL_SEAD_SA6 | near scenery/static/unit:1 / non-LAND:9 / uneven terrain:32 |
| SEAD_ZONE_KILIS / TPL_SEAD_SA8 | non-LAND:6 / uneven terrain:36 / zone boundary:1 |
| SEAD_ZONE_MORPHOU / TPL_SEAD_SA6 | non-LAND:35 / uneven terrain:13 |
| SEAD_ZONE_MORPHOU / TPL_SEAD_SA8 | non-LAND:37 / uneven terrain:7 / zone boundary:1 |
| SEAD_ZONE_NICOSIA_NORTH / TPL_SEAD_SA6 | near scenery/static/unit:1 / non-LAND:21 / uneven terrain:26 |
| SEAD_ZONE_NICOSIA_NORTH / TPL_SEAD_SA8 | near scenery/static/unit:4 / non-LAND:32 / uneven terrain:8 / zone boundary:3 |
| SEAD_ZONE_AKKAR / TPL_SEAD_SA6 | near scenery/static/unit:3 / non-LAND:27 / uneven terrain:10 |
| SEAD_ZONE_AKKAR / TPL_SEAD_SA8 | near scenery/static/unit:2 / non-LAND:24 / uneven terrain:8 |

生の診断行はbuild/SEAD_Placement_Check.log、表形式データはbuild/SEAD_Placement_Results.csv。元ログはSaved Games/DCS.SEADPlacementCheck-e0ef3cf11ab1/Logs/dcs.log。検査ミッションSHA256: `7d7f90af70dfefdff4fc1d35711ccfe4a8e236ac5e24536bd357c2b8e1f0ca65`。完了後にこの検査プロファイルのDCSだけを終了した。


## 2026-10-09 半径統一後（中心は初期位置）

追加6地域を先に既存MEと同じ18,288 m（約9.9 NM）へ拡大し、中心を動かさず全20組合せを再検査した。09:41:50〜09:50:12 JST、1,000点中適合310点、観測エラー0。

| 地域 | SA-6成功/50 | SA-8成功/50 |
|---|---:|---:|
| Palmyra | 26 | 22 |
| Salamiyah | 23 | 23 |
| Dumayr | 38 | 36 |
| Tabqa | 31 | 32 |
| Osmaniye | 11 | 11 |
| Islahiye | 2 | 3 |
| Kilis | 12 | 12 |
| Morphou | 3 | 4 |
| Nicosia North | 2 | 5 |
| Akkar | 4 | 10 |

Islahiyeは0/0から2/3へ増えたが、Morphouは3/4、Nicosia Northは2/5、Akkarは4/10に留まった。半径を広げるだけでは適合点が十分増えないため、診断のVALID_POINTと出撃距離を根拠に4地域の中心を調整した。LAND・高低差・障害物離隔・50回上限は維持する。non-LANDは道路などLAND以外も含み、すべてを海上判定とは解釈しない。

この段階の生ログはbuild/SEAD_Placement_Check_Expanded.log、集計はbuild/SEAD_Placement_Results_Expanded.csv、実行情報はbuild/sead-placement-run-expanded.json、検査ミッションhashはbuild/sead-placement-expanded.sha256。


## 2026-10-09 中心調整後の結果（training-7）

Islahiye / Akkar / Morphou / Nicosiaの中心を変更し、半径18,288 mを維持した。IslahiyeとAkkarは09:54:15〜09:57:37 JST、Morphou Eastは10:02:04〜10:03:46、Nicosia Eastは10:04:58〜10:05:50の各検査で最終中心に一致する結果を採用。変更しない6地域は09:41:50〜09:50:12の半径統一後の結果を使う。単一の全地域連続実行とは区別する。

| 地域 | SA-6成功/50 | SA-8成功/50 | SA-6初回成功 | SA-8初回成功 | 採用実行 |
|---|---:|---:|---:|---:|---|
| Palmyra | 26 | 22 | 1 | 2 | Expanded |
| Salamiyah | 23 | 23 | 1 | 2 | Expanded |
| Dumayr | 38 | 36 | 1 | 1 | Expanded |
| Tabqa | 31 | 32 | 2 | 1 | Expanded |
| Osmaniye | 11 | 11 | 2 | 2 | Expanded |
| Islahiye | 10 | 12 | 2 | 3 | Relocated1 |
| Kilis | 12 | 12 | 1 | 3 | Expanded |
| Morphou East | 7 | 7 | 1 | 1 | Relocated2 |
| Nicosia East | 6 | 9 | 3 | 3 | FinalNicosia |
| Akkar | 14 | 10 | 3 | 1 | Relocated1 |

合算した20組合せ・1,000点の適合は352点、観測エラー0。全地域・両SAMで50点以内に適合点を発見した。半径統一だけの結果から、Islahiyeは2/3→10/12、Morphouは3/4→7/7、Nicosiaは2/5→6/9、Akkarは4/10→14/10。乱数の異なる1回ずつの標本であり、毎回の成功や成功率の統計的向上を保証する数値ではない。

キプロスの中心変更途中では、Akrotiriの一部駐機位置からNicosia中心が40 NM未満となりTest-ZoneCoverageで拒否された。最終中心は北へ調整し、全BLUE Hornet Client駐機位置でCAP / SEADとも2〜3候補を確認した。Nicosiaの地域表示名はNicosia East、MorphouはMorphou Eastとし、Zone識別子は維持する。中心DDM・DCS Vec2・距離はTRAINING_AREASを参照する。

集計CSVはbuild/SEAD_Placement_Results_Final.csv。source_run列は、Expanded / Relocated1 / Relocated2 / FinalNicosiaの各CSVを指す。対応する診断ログはbuild/SEAD_Placement_Check_Expanded.log、_Relocated1.log、_Relocated2.log、_FinalNicosia.log。各実行のmetadataとhashも同じbuildに保存する。中間位置の不採用結果をCSVに残し、最終集計に混ぜない。

全356 Luaケース、BUILD2、SYNC3、INSTALL5、ZONES2が通過。通常ミッションをSync/Checkし、backupとの比較で既存DynamicTraining.lua以外のZIP内容が不変であることを確認した。検査用DCSは完了後に終了。通常Config、Hook、実成績は変更していない。実SAMのSpawn・交戦・描画は引き続き確認待ち。

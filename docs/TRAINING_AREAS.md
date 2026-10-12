# 訓練Zoneと出撃地点からの距離

更新日: 2026-10-12 / training-8

CAPは受注時の長機からZone中心まで40〜100 NM、SEADは40〜130 NMを含む候補から等確率で1つ選ぶ。CAPは9候補、SEADは10候補で、すべて実ミッションのME円形Zoneとして登録する。機体位置を動的に使い、空港名による受注条件分岐は設けない。受注後の移動・長機交代で選び直さない。

## 各出撃地点の候補

以下は4空港のDCS基準点とCVN-71のミッション初期位置からの水平直線距離、単位はNM。各地点で両任務とも2〜3候補になる。実際の受注では駐機位置・空中位置・移動中の空母に応じて候補が変わる。

| 出撃地点 | CAP候補（40〜100 NM） | SEAD候補（40〜130 NM） |
|---|---|---|
| Incirlik | North Coast 44.4 / Iskenderun 61.5 / Osmaniye 58.9 | Osmaniye 58.9 / Islahiye 62.7 / Kilis 83.9 |
| Akrotiri | Cyprus West 58.7 / Cyprus East 48.1 | Morphou East 41.2 / Nicosia East 41.7 |
| Beirut | Central Coast 65.3 / Homs West 72.1 / Cyprus East 86.5 | Salamiyah 112.2 / Dumayr 81.2 / Akkar 56.7 |
| Ramat | Golan 55.9 / Levant South 85.5 | Dumayr 108.9 / Akkar 125.7 |
| Carrier | Golan 88.1 / Cyprus East 67.8 / Levant South 51.2 | Akkar 124.2 / Morphou East 122.7 / Nicosia East 114.5 |

空港基準点と緯度経度の換算は[pydcsのSyria空港定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/airports.py)と[投影定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/projection.py)を参照。既存Zone中心と空母初期位置はレポ内の実ミッションから取得した。駐機位置からの距離には基準点との差があるが、実ミッションの全出撃用Client位置でも2〜3候補を検証する。

追加SEAD6地域は、既存MEと同じ半径18,288 m（約9.9 NM）に統一する。中心距離で選定するため、半径の拡大だけでは候補数は変わらない。実地形の適合点を根拠にIslahiye / Akkar / Morphou / Nicosiaの中心も調整し、すべての実Client駐機位置で2〜3候補を再検証する。識別子は維持し、地域表示名はMorphou East / Nicosia Eastへ合わせる。

## Zone一覧

| 名前 | 中心DDM | 半径 | 定義元 |
|---|---|---:|---|
| `CAP_ZONE_CENTRAL_COAST` | N34°53.691′ E035°14.162′ | 約9.9 NM | ME |
| `CAP_ZONE_GOLAN` | N33°24.231′ E035°51.718′ | 約9.9 NM | ME |
| `CAP_ZONE_NORTH_COAST` | N36°15.794′ E035°29.417′ | 約9.9 NM | ME |
| `CAP_ZONE_HOMS_WEST` | N34°53.223′ E036°09.761′ | 約9.9 NM | ME |
| `SEAD_ZONE_PALMYRA` | N34°39.320′ E037°58.327′ | 約9.9 NM | ME |
| `SEAD_ZONE_SALAMIYAH` | N34°53.202′ E037°20.578′ | 約9.9 NM | ME |
| `SEAD_ZONE_DUMAYR` | N33°33.074′ E037°04.271′ | 約9.9 NM | ME |
| `SEAD_ZONE_TABQA` | N35°36.486′ E038°42.714′ | 約9.9 NM | ME |
| `SEAD_ZONE_OSMANIYE` | N37°03.000′ E036°39.000′ | 約9.9 NM | ME |
| `SEAD_ZONE_ISLAHIYE` | N36°57.835′ E036°43.708′ | 約9.9 NM | ME |
| `SEAD_ZONE_KILIS` | N36°48.000′ E037°09.000′ | 約9.9 NM | ME |
| `SEAD_ZONE_AKKAR` | N34°37.056′ E036°06.281′ | 約9.9 NM | ME |
| `SEAD_ZONE_MORPHOU` | N35°15.725′ E033°09.183′ | 約9.9 NM | ME |
| `SEAD_ZONE_NICOSIA_NORTH` | N35°11.604′ E033°24.210′ | 約9.9 NM | ME |
| `CAP_ZONE_CYPRUS_WEST` | N33°57.000′ E032°06.000′ | 約9.9 NM | ME |
| `CAP_ZONE_CYPRUS_EAST` | N34°30.000′ E033°57.000′ | 約9.9 NM | ME |
| `CAP_ZONE_LEVANT_SOUTH` | N32°42.000′ E033°30.000′ | 約9.9 NM | ME |
| `CAP_ZONE_ISKENDERUN` | N36°27.000′ E036°30.000′ | 約9.9 NM | ME |
| `CAP_ZONE_OSMANIYE` | N37°00.000′ E036°39.000′ | 約9.9 NM | ME |


## 調整後の追加SEAD中心（DCS Vec2）

| Zone | x（北方向m） | y（東方向m） | 半径m |
|---|---:|---:|---:|
| OSMANIYE | 223136 | 73828 | 18288 |
| ISLAHIYE | 213414 | 80579 | 18288 |
| KILIS | 194417 | 117757 | 18288 |
| MORPHOU | 37949 | -249346 | 18288 |
| NICOSIA_NORTH | 29000 | -226958 | 18288 |
| AKKAR | -45416 | 17335 | 18288 |

## 定義と変更方法

候補名・地域表示名・距離制限は `src/config.lua` の `cap` / `sead`、全Zoneの中心・半径は `mission/Persistent_and_Dynamic_FA-18C_Training.miz` のME Trigger Zoneを唯一の定義元とする。座標はSyriaのDCS Vec2メートル座標（x=北方向、y=東方向）。他マップへ移植するときはMEでZoneを配置し、Configの候補名を一致させる。

CAP / SEADと配置診断はMOOSEの `ZONE:FindByName` でME Zoneを直接参照する。Config.zoneDefinitionsとtraining_zones.luaは削除し、Luaで代替円を生成しない。追加していた11円は2026-10-12のユーザー依頼で同じ座標・半径のままMEへ移し、名前・座標・半径はMEで確認・編集できる。初回移行では既存8円を維持し、zoneId 312〜322を重複なく追加した。

Zoneの追加・移動・半径変更はMEで行い、候補名・距離制限の変更はConfigで行う。MEで保存後、Test-ZoneCoverageを実行して候補の存在・円形・距離条件を再確認する。Luaを編集した場合は従来どおりSync/Checkする。ゲーム内反映には更新した.mizでミッションを再開始し、開いているMEではファイルを開き直す。

## 安全配置と確認範囲

追加SEAD地域もLAND、全車両と地形確認点のZone内収容、200m内の高低差20m以内、障害物から200m以上、他Siteとの離隔を検査する。選んだZoneだけを最大50回試し、不合格なら安全に解除する。別Zoneへの変更や配置条件の緩和は行わない。候補数は中心距離の条件を示し、実地形の配置成功率はDCSで確認する。

`scripts/Test-ZoneCoverage.ps1` は実際の.mizのmissionエントリを読み、すべてのBLUE Hornet Client駐機位置で両任務が2〜3候補になることを検証する。各出撃地点の全候補を本番bundleで受注し、CAP計画・SEADの計画からSpawn・中止・ロック解放まで模擬する。全19円のME登録・名前/ID重複なし・半径18,288 m・可視設定を確認する。別確認グループではME実体の直接参照、Zone欠落時にLuaで補完しないこと、安全な受注解除と復旧後の再受注を確認する。Test-Allに含める。

2026-10-09、半径統一と中心調整後の全10地域・両SAM各50点で適合点を発見。変更しない地域の再検査結果と、変更した地域の最終再検査結果を合算した記録は適合352/1,000、観測エラー0。単一の全地域連続実行ではなく複数の実行の記録で、常時成功の保証とは分ける。実Spawn・交戦、追加CAP空域への到達・哨戒は未確認。手動確認はTESTINGのMAN-06 / MAN-52 / MAN-56を参照する。


全地域・両テンプレートで各50点の実地形配置検査は [SEAD_PLACEMENT_CHECK.md](SEAD_PLACEMENT_CHECK.md) を参照。配置成功率の実測と模擬テストの結果を分けて記録する。

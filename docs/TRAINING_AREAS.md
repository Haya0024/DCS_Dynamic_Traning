# 訓練Zoneと出撃地点からの距離

更新日: 2026-10-09 / training-6

CAPは受注時の長機からZone中心まで40〜100 NM、SEADは40〜130 NMを含む候補から等確率で1つ選ぶ。CAPは9候補（既存ME4＋追加5）、SEADは10候補（既存ME4＋追加6）。機体位置を動的に使い、空港名による受注条件分岐は設けない。受注後の移動・長機交代で選び直さない。

## 各出撃地点の候補

以下は4空港のDCS基準点とCVN-71のミッション初期位置からの水平直線距離、単位はNM。各地点で両任務とも2〜3候補になる。実際の受注では駐機位置・空中位置・移動中の空母に応じて候補が変わる。

| 出撃地点 | CAP候補（40〜100 NM） | SEAD候補（40〜130 NM） |
|---|---|---|
| Incirlik | North Coast 44.4 / Iskenderun 61.5 / Osmaniye 58.9 | Osmaniye 58.9 / Islahiye 70.9 / Kilis 83.9 |
| Akrotiri | Cyprus West 58.7 / Cyprus East 48.1 | Morphou 42.7 / Nicosia North 43.3 |
| Beirut | Central Coast 65.3 / Homs West 72.1 / Cyprus East 86.5 | Salamiyah 112.2 / Dumayr 81.2 / Akkar 52.3 |
| Ramat | Golan 55.9 / Levant South 85.5 | Dumayr 108.9 / Akkar 121.7 |
| Carrier | Golan 88.1 / Cyprus East 67.8 / Levant South 51.2 | Akkar 119.5 / Morphou 127.9 / Nicosia North 120.8 |

空港基準点と緯度経度の換算は[pydcsのSyria空港定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/airports.py)と[投影定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/projection.py)を参照。既存Zone中心と空母初期位置はレポ内の実ミッションから取得した。駐機位置からの距離には基準点との差があるが、実ミッションの全出撃用Client位置でも2〜3候補を検証する。

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
| `SEAD_ZONE_OSMANIYE` | N37°03.000′ E036°39.000′ | 5.0 NM | Lua設定 |
| `SEAD_ZONE_ISLAHIYE` | N37°00.000′ E036°54.000′ | 5.0 NM | Lua設定 |
| `SEAD_ZONE_KILIS` | N36°48.000′ E037°09.000′ | 5.0 NM | Lua設定 |
| `SEAD_ZONE_AKKAR` | N34°34.200′ E036°01.800′ | 5.0 NM | Lua設定 |
| `SEAD_ZONE_MORPHOU` | N35°18.000′ E033°00.000′ | 5.0 NM | Lua設定 |
| `SEAD_ZONE_NICOSIA_NORTH` | N35°16.200′ E033°16.800′ | 5.0 NM | Lua設定 |
| `CAP_ZONE_CYPRUS_WEST` | N33°57.000′ E032°06.000′ | 約9.9 NM | Lua設定 |
| `CAP_ZONE_CYPRUS_EAST` | N34°30.000′ E033°57.000′ | 約9.9 NM | Lua設定 |
| `CAP_ZONE_LEVANT_SOUTH` | N32°42.000′ E033°30.000′ | 約9.9 NM | Lua設定 |
| `CAP_ZONE_ISKENDERUN` | N36°27.000′ E036°30.000′ | 約9.9 NM | Lua設定 |
| `CAP_ZONE_OSMANIYE` | N37°00.000′ E036°39.000′ | 約9.9 NM | Lua設定 |


## 定義と変更方法

候補名・地域表示名・距離制限は `src/config.lua` の `cap` / `sead`、追加円形Zoneの中心・半径は `Config.zoneDefinitions` に置く。中心はSyriaのDCS Vec2メートル座標（x=北方向、y=東方向）。他マップへ移植するときはこの地図固有の定義を変更する。

`src/training_zones.lua` は同名の既存ME Zoneを優先し、なければ追加定義から `ZONE_RADIUS:New(name, center, radius, true)` を作る。追加円は非登録でモジュール内に保持し、受注・SEAD計画・生成時の検査で同じ参照を使う。MEのZoneを移動・改名・上書きせず、trigger設定やリソース対応表を変更しない。追加Zoneの描画・全体告知は行わない。

Luaと既存埋め込みをSyncすれば反映でき、追加のME操作は不要。MEで同名Zoneを追加した場合はそちらが優先されるため、中心・半径変更後は距離の検証を再実行する。

## 安全配置と確認範囲

追加SEAD地域もLAND、全車両と地形確認点のZone内収容、200m内の高低差20m以内、障害物から200m以上、他Siteとの離隔を検査する。選んだZoneだけを最大50回試し、不合格なら安全に解除する。別Zoneへの変更や配置条件の緩和は行わない。候補数は中心距離の条件を示し、実地形の配置成功率はDCSで確認する。

`scripts/Test-ZoneCoverage.ps1` は実際の.mizのmissionエントリを読み、すべてのBLUE Hornet Client駐機位置で両任務が2〜3候補になることを検証する。各出撃地点の全候補を本番bundleで受注し、CAP計画・SEADの計画からSpawn・中止・ロック解放まで模擬する。別確認グループでは追加円の非登録・参照再利用・ME優先・座標コピー・不正定義の拒否を確認する。Test-Allに含める。

DCS内の追加SEAD地域の実地形・建物判定と交戦、追加CAP空域への到達・哨戒は未確認。手動確認はTESTINGのMAN-06 / MAN-52 / MAN-56を参照する。


# 訓練Zoneと出撃地点からの距離

更新日: 2026-10-14 / training-8

CAPは受注時の長機からZone中心まで40〜100 NM、SEADは40〜130 NMを含む候補から等確率で1つ選ぶ。CAP9円・SEAD10円はすべて実ミッションのME円形Zone。空港名で受注条件を分岐せず、受注後の移動・長機交代で再抽選しない。

## 各出撃地点の候補

4空港の基準点とCVN-71の初期位置からの水平直線距離、単位はNM。CAPは各2〜3候補、SEADはBeirutが4候補、他は各2〜3候補。Beirutの4候補はユーザー指定で許容する。全15 Client駐機位置でも候補数を検証する。実際の受注は機体の現在位置を使う。

| 出撃地点 | CAP候補（40〜100 NM） | SEAD候補（40〜130 NM） |
|---|---|---|
| Incirlik | North Coast 44.4 / Hatay South 65.8 / Mersin South 50.8 | Turkoglu 73.8 / Hassa 57.6 / Kilis 83.9 |
| Akrotiri | Cyprus West 58.7 / Cyprus East 48.1 | Morphou North 41.9 / Gecitkale East 56.6 |
| Beirut | Central Coast 65.3 / Latakia South 85.4 / Cyprus East 86.5 | Salamiyah 112.2 / Dumayr 81.2 / Akkar 56.7 / Gecitkale East 117.5 |
| Ramat | Golan 55.9 / Levant South 85.5 | Dumayr 108.9 / Akkar 125.7 |
| Carrier | Golan 88.1 / Cyprus East 67.8 / Levant South 51.2 | Akkar 124.2 / Morphou North 127.1 / Gecitkale East 111.9 |

基準点と緯度経度換算は[pydcsのSyria空港定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/airports.py)と[投影定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/projection.py)を参照。Zoneと空母位置は保存済み.mizから取得。駐機位置や移動中の空母からの距離は表と異なる。

## Zone一覧

| 名前 | 地域表示名 | 中心DDM | 半径 |
|---|---|---|---:|
| `CAP_ZONE_NORTH_COAST` | North Coast | N36°15.794′ E035°29.417′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_CENTRAL_COAST` | Central Coast | N34°53.691′ E035°14.162′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_LATAKIA_SOUTH` | Latakia South | N35°15.000′ E035°30.000′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_GOLAN` | Golan | N33°24.231′ E035°51.718′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_CYPRUS_WEST` | Cyprus West | N33°57.000′ E032°06.000′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_CYPRUS_EAST` | Cyprus East | N34°30.000′ E033°57.000′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_LEVANT_SOUTH` | Levant South | N32°42.000′ E033°30.000′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_HATAY_SOUTH` | Hatay South | N36°06.000′ E036°12.000′ | 18,288 m（約9.9 NM） |
| `CAP_ZONE_MERSIN_SOUTH` | Mersin South | N36°25.000′ E034°40.000′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_PALMYRA` | Palmyra | N34°39.320′ E037°58.327′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_SALAMIYAH` | Salamiyah | N34°53.202′ E037°20.578′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_DUMAYR` | Dumayr | N33°33.074′ E037°04.271′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_TABQA` | Tabqa | N35°36.486′ E038°42.714′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_TURKOGLU` | Turkoglu | N37°22.678′ E036°53.481′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_HASSA` | Hassa | N36°45.451′ E036°34.934′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_KILIS` | Kilis | N36°48.000′ E037°09.000′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_AKKAR` | Akkar | N34°37.056′ E036°06.281′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_MORPHOU_NORTH` | Morphou North | N35°17.237′ E033°00.424′ | 18,288 m（約9.9 NM） |
| `SEAD_ZONE_GECITKALE_EAST` | Gecitkale East | N35°13.677′ E033°49.815′ | 18,288 m（約9.9 NM） |

## 2026-10-14の改名とCAP移動

ユーザーがMEで移動したSEAD4円の中心・半径は維持し、実際の地域へ名前を合わせた。CAP3円はSAM射程から離して改名。その他の円・半径・Zone ID・機体・経路・トリガー・リソース対応表は変更しない。

| 旧Zone名 | 現在のZone名 | 座標変更 |
|---|---|---|
| `SEAD_ZONE_OSMANIYE` | `SEAD_ZONE_TURKOGLU` | ユーザー保存座標を維持 |
| `SEAD_ZONE_ISLAHIYE` | `SEAD_ZONE_HASSA` | ユーザー保存座標を維持 |
| `SEAD_ZONE_MORPHOU` | `SEAD_ZONE_MORPHOU_NORTH` | ユーザー保存座標を維持 |
| `SEAD_ZONE_NICOSIA_NORTH` | `SEAD_ZONE_GECITKALE_EAST` | ユーザー保存座標を維持 |
| `CAP_ZONE_HOMS_WEST` | `CAP_ZONE_LATAKIA_SOUTH` | CAP中心を移動 |
| `CAP_ZONE_ISKENDERUN` | `CAP_ZONE_HATAY_SOUTH` | CAP中心を移動 |
| `CAP_ZONE_OSMANIYE` | `CAP_ZONE_MERSIN_SOUTH` | CAP中心を移動 |

## CAPとSAMの離隔

全CAP9円×SEAD10円の90組で、中心距離から両半径を引いた外縁間隔を20 NM以上にする。`sead.templates[].planningRangeNM`はSA-6:15 NM、SA-8:8 NM、`cap.samSafetyBufferNM`は5 NM。全Zoneで両SAMが抽選されるため最大値15＋5を適用する。現在の最短外縁間隔は23.8 NM（Hatay South / Hassa）。

計画射程はインストール済みDCSの3M9M Kub / 9M33 Osa定義（D_max:25,000 / 10,300 m）に余裕を取った配置検証値で、AIの発射射程を変更する値ではない。CAP円内と、全車両をSEAD円内へ配置する条件を対象にする。進入・追撃でCAP円外へ出る場合、CAP敵機の円外生成・進入経路、別途MEで配置したSAMまでは安全を保証しない。

## 定義・変更・検証

候補名・地域表示名・距離制限は`src/config.lua`、全円の中心・半径はME Trigger Zoneが唯一の定義元。Luaの代替円は持たない。通常の変更はMEで行う。名称変更はConfigと仕様書へ揃え、Lua変更後はSync/Check、MEでは開き直してミッションを再開始する。

`scripts/Test-ZoneCoverage.ps1`は全ClientのCAP2〜3・SEAD2〜4候補、全19円の存在・一意な名前/ID・可視性・半径、全候補の受注・模擬生成・解除、ME欠落時の安全解除・再受注、全90組のSAM離隔を検証し、Test-Allに含める。

SEADはLAND、200 m内の高低差20 m以内、全車両と検査点の円内収容、各車両と障害物の200 m離隔を要求する。1 Zoneを最大50回検査し、適合点がなければ安全に受注解除する。候補があることと実地形で安全配置できることは区別する。現在の地形検査・実生成結果は[SEAD_PLACEMENT_CHECK.md](SEAD_PLACEMENT_CHECK.md)。2026-10-09の結果は当時の中心位置の記録であり、今回移動した4円へ流用しない。

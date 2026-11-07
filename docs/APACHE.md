# ApacheのAir Interdiction / CAS訓練

仕様: 2026-11-07 / training-17.3。Apache限定のCASを追加。単独JTAC試験でK型3発3中はユーザー報告。動的CASの交信・実射・人間PLT/CPGのネットワーク動作はDCS内確認待ち。

## 出撃

2026-11-06 / training-16から通常の出撃はDynamic Spawnへ移行し、ユーザー指定でDCS標準の機体設定を使う。SOLO/MP2原本と倉庫の参照リンクは削除済み。以下のSOLO/MP2配置・距離表は削除前の参考記録で、現在の固定スロットや実際の動的駐機位置ではない。各空港から1機ずつ生成する。別機体はF10のMission Team、同一機のPLT/CPGは自動共有。更新したサーバーHookが必要。詳しくは[DYNAMIC_SPAWN.md](DYNAMIC_SPAWN.md)。

### 削除前の配置原本（参考）

BLUE / USAのAH-64D_BLK_IIをIncirlik / Akrotiri / Beirut / Ramat Davidに配置。各空港にSOLO（Client ×1）とMP2（Client ×2）、合計8グループ・12 Client機。MP2は2機編隊を意味し、同一機のPLT/CPGを意味しない。空母のApacheは置いていない。

グループ名は `BLUE_APACHE_<INCIRLIK / AKROTIRI / BEIRUT / RAMAT>_<SOLO / MP2>_01`。全機がBLUE空港の駐機場からコールド開始し、Apache間の駐機位置と全任務の機体名・IDに重複はない。MEのグループTaskがCASでも問題なく、F10任務のカテゴリはスクリプトが管理する。

検出と受注の条件にグループ名や空港名を使わない。`config.playerTypes`で対応機種と任務を管理する。ApacheのF10には `Task: Air Interdiction`、コード選択付き `Task: CAS` と共通のMission Status / Abort Mission / Abort Sortie / Player Statisticsを表示する。Hornetは従来の6任務を維持する。

## 受注と候補

Apacheでは `config.airInterdiction.helicopter.templates` のTPL_AI_01〜10から、受注時の長機位置と周回WP外接矩形中心の水平距離が3〜13 NM（両端含む）の地域に絞る。その中の近い2地域を固定し、使用可能な1地域を等確率で選ぶ。1地域だけならその地域、候補なし・近い2地域が使用不可なら採点・生成なしで解除する。3番目へ回さず、範囲を自動拡張しない。地上でも即生成する。

HornetはTPL_AI_01〜06のうち、長機から中心まで20〜100 NMにある近い2地域を使う。両機種は同じ地域予約を使い、同じ道路に別任務の車列を重ねて生成しない。

案内する中心は現在の車列位置ではなく捜索基準。座標はMEから計算し、Luaへ座標を複製しない。経路・速度・車種・散開・周回指示はMEの設定をそのまま使う。

## 編成追加の拡張

2026-11-05に経路と編成を分離した。現在は編成候補が空なので既存の車列を維持する。将来は`helicopter.convoyTemplates`へ3両のMEグループ名を登録すると、同じ経路で編成を抽選できる。配置条件・設定例・継承規則は[AIR_INTERDICTION.md](AIR_INTERDICTION.md#経路と編成の分離2026-11-05)を参照。Hornetとは候補を分けられ、地域予約と3両破壊・採点は共通のまま。

## 削除前の駐機位置を使った距離参考値

2026-11-01の保存済み12 Apache駐機位置から周回中心までの直線距離。表の幅はSOLO1機とMP2の2機の駐機位置差。飛行経路の長さや、道路上の全地点までの距離を保証する値ではない。

| 出撃空港 | 近隣地域 | 中心までの距離 | 3〜13 NMの受注候補 |
|---|---|---:|---|
| Incirlik | TPL_AI_01 | 9.248〜9.297 NM | 対象 |
| Incirlik | TPL_AI_09 | 3.706〜3.799 NM | 対象 |
| Akrotiri | TPL_AI_10 | 7.859〜7.895 NM | 対象 |
| Akrotiri | TPL_AI_06 | 25.005〜25.012 NM | 対象外：13 NM超過 |
| Beirut | TPL_AI_08 | 10.903〜10.957 NM | 対象 |
| Ramat David | TPL_AI_07 | 12.513〜12.519 NM | 対象 |

距離条件を5〜12 NMから3〜13 NMへ変更したため、全4青空港・12駐機位置で受注候補を確保した。IncirlikはTPL_AI_09とTPL_AI_01の2候補、Akrotiri / Beirut / Ramat Davidは各1候補。保存座標と経路は変更していない。距離条件は周回中心までであり、RamatのTPL_AI_07の一部WPは約13.46 NMまで離れる。

## 参加者・帰還・採点

受注時に同じグループの搭乗中人間を固定し、AI・空席・途中参加を追加しない。ApacheではネットワークのME unitIdと乗員席suffixを照合し、同じ機体の人間PLT/CPGを別UCIDの参加者として扱う。人間CPG＋AI操縦士も対象。同一機内の席交換は認めるが、別機体へ移った参加者の帰還を元任務へ流用しない。UCID不明は無採点で、他の乗員のUCIDや表示名で代用しない。

3両全滅の目標は共有し、各参加者に満額150ポイント。帰還成功はBLUE空港または既存対応空母への着陸後、5 knots以下を連続10秒。達成後の機体喪失は各90、未達成の機体喪失・任意中止は0。FARP帰還は今回追加しない。機体単位の喪失イベントはその機体の全登録乗員に適用し、別機の参加者は継続する。個別中止済み乗員がいても同機の残る参加者の精算を止めない。人間乗員1人だけが死亡する場合のDCSイベント挙動は確認待ち。

同一機のPLT/CPGは同じ着陸でそれぞれ帰還確認する。途中で座席を離れた参加者は操縦中と認めず、帰還時間を加算しない。1人が精算しても全参加者終了までWing/UCIDロックを維持する。Air InterdictionはairInterdictionScore、CASはcasScoreへ加算する。現在はschema5のため、CAS導入時に更新Hookを再導入してサーバーDCSを再起動する。

## 表示と検証

受注10秒→周回中心MGRS 8桁・3両破壊・報酬・登録人数の既存5行ブリーフィング60秒。Registered pilotsはCPGを含む登録人数。Mission Statusは公開済み本文のみで、達成後は座標なしの達成結果と帰還指示20秒。TSD自動登録、スモーク、敵残数・現在位置の追加表示は行わない。

Apacheの受注表示例（座標値は例示）：

```text
AIR INTERDICTION MISSION
TARGET AREA: MGRS 37S BV 1234 5678
OBJECTIVE: Destroy all 3 convoy vehicles; then RTB.
Reward per pilot: 150 points.
Registered pilots: 1.
```

座標は周回中心で、車列の現在位置や個別車両の座標ではない。受注時に1回整形して保存し、Mission Statusでは同じMGRSを再表示する。変換失敗時は生成前に任務を解除する。Apacheの8桁入力の根拠は[ED公式FAQ](https://forum.dcs.world/topic/283298-dcs-ah-64d-faq/)を参照する。

候補なし・使用不可は次を20秒表示する。

```text
No available Air Interdiction routes among the two nearest sites within 3-13 NM. Try again later.
```

`scripts/Test-Apache.lua`は27ケース。MGRSはMOOSEの`ToStringMGRS({ MGRS_Accuracy = 4 })`を使い、東4桁＋北4桁の計8桁（10 m単位）にする。UTMゾーンと100 kmグリッド識別子も表示し、先頭ゼロを保持して各軸を切り捨てる。グローバル表示設定には依存しない。Hornetは従来のDDM・分小数3桁。`Test-AirInterdictionMission.ps1`は保存済み10経路・12 Apache駐機位置・タイトル・空港所属・スロット構成を検証し、全12駐機位置で候補があることを要求する。候補なしの拒否と3/13 NM境界はTest-Apache.luaで確認する。全10経路をApacheから受注できる位置で抽選・生成・3両破壊・削除も模擬検証する。

DCSでは4空港でのF10受注、CPG単独・人間2乗員、MP2、座席交換、損失、ヘリ着陸イベント、Hookへの精算保存を確認する。MEの保存確認は実際の道路追従・3D駐機衝突・実射の保証ではない。

## CAS（training-17）

`Task: CAS → Laser 1688 / 1687 / 1686`で受注する。長機の実位置から敵先頭車まで3～13 NMの近い2地域から、使用可能な1地域を抽選する。現在はRamat付近の地域01だけ。敵3両・味方3両・JTAC1両をME位置へ即生成し、味方位置・目標地域をMGRS 8桁で案内する。標準無線メニューで担当JTACへ連絡し、指定敵3両を全滅させて帰還する。人間PLT/CPGとMission Teamの共有・個別150/90/0を使う。CAS専用成績schema5に対応するHookへ更新してDCSを再起動する。詳細は[CAS.md](CAS.md)。

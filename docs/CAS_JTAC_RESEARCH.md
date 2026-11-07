# 動的JTAC / CASの公開実装調査

調査日: 2026-11-07。公開README・実装コードを読み、現在の標準FAC方式と比較した。紹介先を実DCSで実行した検証ではない。各URLのbranchは更新され得るため、取得したfile blob SHAも残す。

## 照射方式の区別

現在のsrc/jtac.luaは生成した敵Group IDをME由来FAC_EngageGroupへ設定し、DCS標準FACが交信・検出・対象選定・照射を担当する。Luaはレーザー点を作成しない。

CTLD、MOOSE AUTOLASE、DCS-MYTHS-JTACはSpot.createLaserまたはMOOSE SPOTでレーザー点を管理する。F10や独自通知の仕組みも含み、DCS標準JTACの交信手順をそのまま置換できる部品とは扱わない。

## 1. CTLD: 動的に展開したJTAC

- [READMEのJTAC説明](https://github.com/ciribob/DCS-CTLD#jtac-automatic-targeting-and-laser): ヘリ・crateからJTACを展開し、自動照射を開始する。遮蔽・撃破で対象を変更し、既に他JTACが照射する対象との重複を避ける。
- [CTLD.lua](https://github.com/ciribob/DCS-CTLD/blob/master/CTLD.lua#L6958): laseUnitは目標getPointのyへ2 mを加算し、発射側相対位置もy=2 mとしてSpot.createLaserする。既存spotはsetPointで更新する。
- [現在対象の再検査](https://github.com/ciribob/DCS-CTLD/blob/master/CTLD.lua#L7041): 生存・active・距離を検査し、両端2 m上のland.isVisibleを確認する。コメントは地表付近の丸め誤差と車体の高さを理由としている。
- 移動・風への補正はJTACごとの切替式。コード上の経験的係数を使う機能であり、DCS標準FACや今回の静止車両・Hellfireに同じ補正が必要だとは結論しない。
- READMEはLOSに建物・樹木が含まれない旨を明記している。CTLDの判定範囲の説明であり、標準FACの全検出条件へ一般化しない。
- 取得CTLD.lua blob SHA: 07a5d065dac0607569a56119dccdadd6d6507d99。

## 2. MOOSE AUTOLASE / SPOT: 車両ごとの照射と寿命管理

- [公式AUTOLASE例](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Functional.Autolase.html): SPAWNのOnSpawnGroupで生成したRecceの実Unit名にレーザーコードを割り当てる例がある。
- [CanLase](https://github.com/FlightControl-Master/MOOSE/blob/master-ng/Moose%20Development/Moose/Functional/Autolase.lua#L945): 車両別の距離、2.5 m offsetのLOS、対象属性、Recceのcooldownを確認する。
- [CleanCurrentLasing](https://github.com/FlightControl-Master/MOOSE/blob/master-ng/Moose%20Development/Moose/Functional/Autolase.lua#L717): 発射元と目標の生存、見通し、照射時間を再評価し、失視・timeoutでは照射を止める。TargetLost / TargetDestroyed / LaserTimeoutを別イベントにしている。
- [SPOTの生成処理](https://github.com/FlightControl-Master/MOOSE/blob/master-ng/Moose%20Development/Moose/Core/Spot.lua#L231): 発射側の既定相対高さ2 m、目標getPointから1 m上へレーザー点を作り、継続中も目標座標を更新する。
- 現リポジトリ同梱Moose.luaにも2.5 mのCanLaseと目標+1 mのSPOT処理が存在することを読み取り確認した。現在のCASがこれらを使用しているという意味ではない。
- 取得Autolase.lua blob SHA: cc4a8591e2cd13d5c6bf57d2db2187802905a69e。Spot.lua: 14a9d285d8d958bcc8df9a681ed6cc991242b3bb。

## 3. DCS-MYTHS-JTAC: 要求ごとの地上・ドローン展開

- [README](https://github.com/behaguer/DCS-MYTHS-JTAC): F10で受注し、map marker付近へ地上またはdrone packageを生成する。任務ごとのコード、スロット変更後の制御継続、切断時Cleanupを管理する。
- v0.4では遅延生成の位置snapshot、nil laserPos、実体と内部状態の照合、地上とdroneの寿命分離を修正対象としている。
- [JTAC.lua](https://github.com/behaguer/DCS-MYTHS-JTAC/blob/main/JTAC.lua#L1766): 選択Unitを追跡し、8 mを超える移動でレーザー点を作り直す実装がある。標準FAC方式ではない。
- そのまま採用する根拠にはしない。同じ関数にUnit.getByNameがnilなら撃破とする処理があるが、このプロジェクトでは観測不能を死亡にしない方針を維持する。
- 取得JTAC.lua blob SHA: aeb65499321abd102625fa59d775fb05ca131d56。

## 4. MOOSE AUFTRAG: 標準FACを動的タスクとして扱う設計例

- [Auftrag.luaのNewFAC / NewFACA](https://github.com/FlightControl-Master/MOOSE/blob/master-ng/Moose%20Development/Moose/Ops/Auftrag.lua#L1654): NewFACは地上・航空機の地域巡回FAC、NewFACAは対象Groupを指定する航空FACを構成する。
- 同ファイルのFACAタスク生成はCONTROLLABLE.TaskFAC_AttackGroup、FACはEnRouteTaskFACを使う。DCS標準FACを動的に任務化する設計自体は存在する。
- これを現在の地上FAC_EngageGroupの完全同等例や、現DCSでの命中成功例とは扱わない。対象、タスク種別、運用範囲が異なる。
- 取得Auftrag.lua blob SHA: 6aa1f063dc17c6c9daf117658575773d7da68639。

## 今回に適用する判断

1. 地形判定の2 m offsetだけが特別に厳しいとはいえない。CTLDも2 m、AUTOLASEも2.5 mで車両別に検査する。ただし標準FACの内部発射点・照射部位は今回取得できていない。
2. 今回のBMP-2×2=false / truck=trueは配置の調査根拠として維持する。一方、遮蔽が標準FACのレーザーを手前の地面へずらす機序は、今回読んだソースからは確認できていない。原因確定とはしない。
3. 次の比較は、同じ敵・JTAC配置を使う標準FACの初期配置版と動的生成版。両方で全3両が見通せる配置を用意し、対象ごとの実LST指示位置と誘導を比較する。現行の単独成功試験は場所が異なり、動的生成だけを比較する対照にはなっていない。
4. 標準FACを維持する場合、配置検査と生成実体検査、FAC対象Group ID、交信成功、照射成功、命中を別々の証拠として残す。LOS=falseだけで任務・採点を取り消す実装へ戻さない。
5. 継続診断を追加するなら、対象別の生死・LOSの変化だけをログへ出し、毎秒の同文出力を避ける。現在の1回だけの地形ログでは攻撃時点の変化を観測していない。
6. 自前照射を比較用に作る場合は別の試験に分離し、標準FACの照射を同時に動かさない。対象Unit、要求したspot位置、codeを記録できる利点はあるが、標準9-lineや照射判断の代替設計になる。CTLDの+2 mだけを標準FACへ移植することはできない。
7. 現在実装済みのWing/UCID固定、通信枠予約、実Group IDへの結合、期限付き生成待ち、Cleanup再試行を活用する。外部例の周辺敵全検索や独自死亡判定を、指定3両の任務へ無条件に持ち込まない。

この調査ではゲーム側Lua、ME配置、ミッション、Hook、照射方式を変更していない。

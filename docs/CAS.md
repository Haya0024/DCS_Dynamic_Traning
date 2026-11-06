# CAS / 標準JTAC

training-17.1。CASを実装し、単独試験で使用したDCS標準FAC / JTACへ接続する。単独Apacheで離隔後にAGM-114Kが3発3中だったことはユーザー報告。動的生成したJTACの交信・照射・実射はDCS内確認待ち。

## 受注・地域・生成

- 初版はApacheだけ。F10 `Task: CAS` サブメニューからレーザーコードを選択して受注する。Hornetのメニューには出さず、古いcallbackからの受注も拒否する。
- 受注時の搭乗者を固定し、Dynamic Spawn / Mission Team / Apacheの人間PLT・CPGを既存のWing・UCIDロックと個別精算へ接続する。同機種のMission Teamに対応する。
- Config.casの地域を、受注時の長機実位置から敵先頭車までの水平距離3～13 NMで絞る。両端を含む。
- 近い2地域を固定し、その中の使用可能な地域を等確率で1つ抽選する。1候補ならそれを使い、候補なし・使用中・不正な近傍2地域では採点せず解除する。3番目や距離範囲外へ拡張しない。
- 現在は地域01だけ。ApacheはRamat付近からの利用を想定する。出撃空港名をロジックの条件にしない。
- 地上 / 空中とも受注時に生成準備を開始する。離陸待ち・20秒待ちは設けない。DCSで新しい車両が有効になるまでPREPARINGを維持し、1秒ごとに再観測する。setupTimeoutSeconds（初期10秒）を超えた次の監視で失敗解除する。
- 状態は `PREPARING → ACTIVE → RTB_PENDING → 終了`。全3グループとJTAC担当設定が成立して初めてACTIVE・採点開始とする。

## Mission EditorのTPL

| 地域01のグループ | 陣営 / 国 | 構成 |
|---|---|---|
| TPL_CAS_ENEMY_01 | RED / Russia | BMP-2 ×2、Ural-375 ×1 |
| TPL_CAS_FRIENDLY_01 | BLUE / USA | M-113 ×2、M 818 ×1 |
| TPL_CAS_JTAC_01 | BLUE / USA | M1045 HMMWV TOW ×1 |

全グループがLate Activation、単一の停止WP、Weapon Hold、Disperse under fire OFF。初版は敵の反撃・移動を追加しない。座標・向き・車間・兵器マスク・その他のME設定は継承し、Luaに代替座標を置かない。地域を増やすときは3グループを同じ地域番号で複製し、Config.cas.sitesへ明示追加する。名前の自動走査で未登録地域を採用しない。

JTACの初期WPには有効な `FAC_EngageGroup` を1つだけ置き、同地域の敵原本Groupを指定する。DesignationはLaser、VisibleはON。原本は有効化せず、固有alias `DT_CAS_<assignmentID>_<role>` でコピーする。

生成順は敵 → 味方 → JTAC。敵の実Group IDを取得してから、JTACコピーのFAC対象をそのIDへ置換し、予約したコールサイン・無線・コードを設定してJTACを生成する。元TPLを変更しない。MOOSEラッパーで欠けるlaserCode / visibleなどのME保存フィールドを維持するため、FACタスクだけDCS形式のコピーを扱う。生成・座標・LOS・削除はMOOSEを使う。

全実体の陣営・数・車種・IDを照合する。MOOSEのGetUnitsは取得順を保証しないため、車種ごとの台数で構成を照合し、テンプレートの配列順とは比較しない。有効化途中の実体や未取得の一覧は期限内で再観測し、期限切れ・観測不正は部分生成を回収する。生成JTACから敵全車両への地形LOSをMOOSEで検査する。LOS通過は建物・樹木を含めた照射成功の保証ではなく、ME配置とDCS実射で確認する。失敗時に別地点へ移動しない。

## 無線・コード枠

| 選択コード | コールサイン | 無線 |
|---|---|---|
| 1688 | Axeman 1 | 133.000 MHz AM |
| 1687 | Axeman 2 | 134.000 MHz AM |
| 1686 | Axeman 3 | 135.000 MHz AM |

地域と通信枠は同時使用不可。希望コードが使用中なら別コードへ自動変更せず、生成・採点なしでロックを戻す。全生成物の削除確認まで枠を保持する。現在のBLUE AWACS / 給油機の251 / 251.1 / 251.2 MHzとは重複しない。空港管制など他の無線との完全な周波数管理を行うものではない。

標準JTACへの交信・Laser OnなどはDCSの無線メニューで実施する。独自の9-lineや照射機構を追加しない。他のBLUEプレイヤーから標準JTACへの接触を完全に禁止する機能はなく、ブリーフィングで担当を明示する。自機レーザーとのコード競合は搭乗者が調整する。

## 達成・帰還・支援喪失

- 今回生成した敵3両を固定IDで監視し、全3両の破壊で共有達成。損傷だけでは達成しない。第三者による対象撃破も数える。
- nil・例外・ID違い・Group一覧欠落を破壊とみなさない。明示死亡イベントまたは信頼できる固定IDの死亡観測を使う。
- 撃破を確認するのは訓練Lua。標準JTACの台詞や交信手順・攻撃許可を採点のトリガーにしない。使用兵器も限定しない。
- 達成前のRTBでは精算せず任務を維持する。達成後は既存のBLUE基地 / 対応空母への5 knots以下・連続10秒の帰還確認を使う。FARPを新設しない。
- 各自150、達成後事故90、未達成事故・Abort0。途中終了者へ遡及加点しない。全員終了まで他の参加者は継続できる。
- 味方車両喪失・JTAC喪失は各実体で一度だけ通知する。JTAC喪失後も自力攻撃で継続可能。自動補充・交代は行わない。初版は誤射の減点・自動失敗を追加せず、喪失原因が味方の攻撃かも断定しない。

## 公開メッセージ

有効化待ちがある場合は `CAS mission accepted. Preparing JTAC.` を10秒表示し、Statusもこの準備通知だけを再表示する。全実体の検証・担当設定後、受注通知10秒に続けて以下をcoordinateBriefingSeconds（初期60秒）で1回表示する。

```text
CAS MISSION
FRIENDLY LOCATION: <味方先頭車の座標>
TARGET AREA: <敵先頭車の座標>
FRIENDLIES: 2 M113s and 1 truck.
TARGETS: 2 BMP-2s and 1 truck.
JTAC: Axeman 1 / 133.000 MHz AM / LASER 1688
OBJECTIVE: Destroy all 3 designated enemy vehicles; then RTB.
Reward per pilot: 150 points.
Registered pilots: <人数>.
```

Apache向けにMGRSの東4＋北4桁で表示する。座標にランダム誤差を加えず、車両ごとの精密座標を列挙しない。部隊説明は地域ごとの設定で、ME構成変更時に更新する。

Mission Statusは保存済みブリーフィングを再表示し、支援喪失の公開通知も保持する。現在残数・内部予約・未公開座標を追加しない。達成後は座標を含まない公開済み結果・帰還指示を20秒表示する。標準JTACの音声・交信履歴は取得・再表示しない。

```text
CAS Objective Complete
All 3 designated enemy vehicles destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

## 終了・保存・検証

全参加者終了、Abort、準備失敗でJTAC・味方・敵をすべて削除する。部分生成やMOOSE登録前の生成失敗も固有aliasで回収し、削除未確認は5秒ごとに再試行する。全消失まで地域・通信枠を解放しない。古いcallbackと削除中の喪失イベントを新任務や目標達成へ適用しない。

CAS ScoreはcasScoreへ独立加算する。保存schema5で末尾へ追加し、schema1～4は従来の値を保持してCASを0へ移行する。missionとHookを同時更新し、サーバーHookの再導入・DCS再起動が必要。開発テストは実成績ファイルを変更しない。途中の任務・地域・JTACは再起動後に復元しない。

自動検証はTest-CAS.lua、実.mizの構成検査はTest-CASMission.ps1、保存はTest-Persistence.lua。全既存スイートとBuild / Sync / Installも確認する。DCS内では動的JTACの登録・交信・対象追従、Apache K / L、複数JTAC、支援喪失、終了後の残留を別途確認する。Hornet対応は将来の追加対象。

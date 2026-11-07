# CAS / AUTOLASE JTAC

training-18.1。受注後は照射せず待機し、F10 `Dynamic Training → CAS JTAC → Request laser` で依頼してから、指定した敵3両をMOOSE AUTOLASEの距離・LOS判定とSPOTで1両ずつ照射する。`Stop laser` で停止・再依頼が可能。標準JTACとの無線交信は不要。固定ID・単一照射・観測不能・通知・回収をCAS専用アダプターで管理する。詳細な設計と境界は[CAS_AUTOLASE.md](CAS_AUTOLASE.md)。実DCSでのLST・Hellfire誘導は確認待ち。

旧training-17.3では交信・レーザー捕捉後もTADS指示点と着弾が手前へずれるとのユーザー報告があった。単独Apacheの別配置でのAGM-114K 3発3中という報告、2026-11-07のサーバーログは履歴として維持し、AUTOLASEで修復済みとは扱わない。

## 受注・地域・生成

- 初版はApacheだけ。F10 `Task: CAS` サブメニューからレーザーコードを選択して受注する。Hornetのメニューには出さず、古いcallbackからの受注も拒否する。
- 受注時の搭乗者を固定し、Dynamic Spawn / Mission Team / Apacheの人間PLT・CPGを既存のWing・UCIDロックと個別精算へ接続する。同機種のMission Teamに対応する。
- Config.casの地域を、受注時の長機実位置から敵先頭車までの水平距離3～13 NMで絞る。両端を含む。
- 近い2地域を固定し、その中の使用可能な地域を等確率で1つ抽選する。1候補ならそれを使い、候補なし・使用中・不正な近傍2地域では採点せず解除する。3番目や距離範囲外へ拡張しない。
- 現在は地域01だけ。ApacheはRamat付近からの利用を想定する。出撃空港名をロジックの条件にしない。
- 地上 / 空中とも受注時に生成準備を開始する。離陸待ち・20秒待ちは設けない。DCSで新しい車両が有効になるまでPREPARINGを維持し、1秒ごとに再観測する。setupTimeoutSeconds（初期10秒）を超えた次の監視で失敗解除する。
- 状態は `PREPARING → ACTIVE → RTB_PENDING → 終了`。全3グループとAUTOLASE初期化が成立して初めてACTIVE・採点開始とする。実照射はACTIVEかつRequest laser依頼中に限る。準備中・達成後は依頼できない。
- DCSのUnit IDは正の整数または十進文字列を許可する。固定対象には元のIDを保持し、重複検査とGroup ID診断は数値へ正規化する。不正ID・実体欠落・有効化未完了は準備待ちとし、IDのLua型・実体の有無も診断へ記録する。

## Mission EditorのTPL

| 地域01のグループ | 陣営 / 国 | 構成 |
|---|---|---|
| TPL_CAS_ENEMY_01 | RED / Russia | BMP-2 ×2、Ural-375 ×1 |
| TPL_CAS_FRIENDLY_01 | BLUE / USA | M-113 ×2、M 818 ×1 |
| TPL_CAS_JTAC_01 | BLUE / USA | M1045 HMMWV TOW ×1 |

全グループがLate Activation、単一の停止WP、Weapon Hold、Disperse under fire OFF。初版は敵の反撃・移動を追加しない。座標・向き・車間・兵器マスク・その他のME設定は継承し、Luaに代替座標を置かない。地域を増やすときは3グループを同じ地域番号で複製し、Config.cas.sitesへ明示追加する。名前の自動走査で未登録地域を採用しない。

現在のJTAC原本の初期WPには有効な `FAC_EngageGroup` が1つあり、同地域の敵原本Groupを指定している。DesignationはLaser、VisibleはON。この対応を検証したうえで動的コピーからFACを除去し、標準FACとの二重照射を防ぐ。原本は有効化せず、固有alias `DT_CAS_<assignmentID>_<role>` でコピーする。

生成順は敵 → 味方 → JTAC。元TPLを変更せず、JTACコピーはFACを除去した状態で生成する。全実体検証後、今回のJTACと固定した敵3両をCASAutolaseへ渡し、選択したコードで単一照射を管理する。既定はJTAC→目標3 NM、選定監視1秒、照射300秒。対象を保持して追従し、撃破・失視・未知・時間切れで停止・再選定する。別任務の車両を候補にしない。

全実体の陣営・数・車種・IDを照合する。MOOSEのGetUnitsは取得順を保証しないため、車種ごとの台数で構成を照合し、テンプレートの配列順とは比較しない。有効化途中の実体や未取得の一覧は期限内で再観測し、期限切れ・実体の観測不正は部分生成を回収する。

AUTOLASEのCanLaseは対象ごとに距離と2.5 m offsetの地形LOSを検査する。MOOSE SPOTは発射側相対2 m・目標位置+1 mを使う。既存のUNIT:IsLOSによる両端2 mの診断は全実体検証後の次の監視で1回だけDEBUGへ記録し、生成条件にはしない。false・nil・例外でもCASを解除せず、座標案内・Status・採点を維持する。中止・回収中は診断しない。配置は動かさず、実射はME配置とDCSで別途確認する。

2026-11-07の実サーバーでは12:36と13:19 JSTの2生成とも、BMP-2の2両がvisible=false、Ural-375だけtrueだった。生成後の各位置は保存済みTPLと一致し、JTACの地表高は130.78 m、敵は119.63 / 119.80 / 122.53 m、AGLはほぼ0 m。生成位置・高度のずれを示す結果ではなく、現配置での地形遮蔽を優先して調べる根拠となる。ただし診断は実レーザー点・照射対象・車体の照射部位を取得しておらず、着弾ずれの原因確定ではない。

インストール済みMEのme_action_param_panels.luaでは、FACのgetTerrainLOSが対象グループの1両でも見えればtrueを返す。従ってLaserのproblem: no LOS警告が消えても全3両の見通しを保証しない。配置検証では車両別の見通しを確認する。今回の調査では原本の配置・FAC設定を変更していない。

CASME-4は実.mizと同梱MOOSEのSpawn/Prepare/DATABASE関数を通し、coalition.addGroupへ渡る座標・向き・車種・Skill・WPとFAC除去を検査する。CASME-2とCAS追加ケースでは実AUTOLASE Constructor / CanLase / SPOT関数を実行し、選択コード・対象限定・追従・停止を検証する。native生成・spot・scheduler・イベント処理は模擬境界であり、実レーザー表示や誘導弾命中を再現する検査ではない。

## 無線・コード枠

| 選択コード | JTAC識別 |
|---|---|
| 1688 | Axeman 1 |
| 1687 | Axeman 2 |
| 1686 | Axeman 3 |

地域と通信枠は同時使用不可。希望コードが使用中なら別コードへ自動変更せず、生成・採点なしでロックを戻す。全生成物の削除確認まで枠を保持する。現在のBLUE AWACS / 給油機の251 / 251.1 / 251.2 MHzとは重複しない。空港管制など他の無線との完全な周波数管理を行うものではない。

AUTOLASEの開始・対象切替は自動。標準JTACの音声9-line・無線メニュー・Laser On依頼は使わない。設定内の旧無線値は予約互換用に残すが、音声通信は行わず公開ブリーフィングにも周波数を表示しない。自機レーザーとのコード競合は搭乗者が調整する。

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
TARGETS: 2 BMP-2s and 1 truck.
JTAC standing by. LASER 1688. F10 CAS JTAC > Request laser when ready.
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

目標達成で照射を停止し、帰還評価は維持する。全参加者終了、Abort、準備失敗でも照射を停止してJTAC・味方・敵をすべて削除する。部分生成やMOOSE登録前の生成失敗も固有aliasで回収し、削除未確認は5秒ごとに再試行する。native IR/Laserと監視・全生成物の回収完了まで地域・通信枠を解放しない。古いcallbackと削除中の喪失イベントを新任務や目標達成へ適用しない。

CAS ScoreはcasScoreへ独立加算する。保存schema5で末尾へ追加し、schema1～4は従来の値を保持してCASを0へ移行する。missionとHookを同時更新し、サーバーHookの再導入・DCS再起動が必要。開発テストは実成績ファイルを変更しない。途中の任務・地域・JTACは再起動後に復元しない。

自動検証はTest-CAS.lua、実.mizの構成検査はTest-CASMission.ps1、保存はTest-Persistence.lua。全既存スイートとBuild / Sync / Installも確認する。DCS内では自動照射通知・LST・対象追従、Apache K / L、複数JTAC、支援喪失、終了後の残留を別途確認する。training-18は保存schema5とHookを変更しないため、正常な17.3 Hookはそのまま利用できる。Hornet対応は将来の追加対象。

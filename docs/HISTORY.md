# 検証・診断履歴

現在のテスト件数・実行方法は [TESTING.md](TESTING.md)、保存方式・診断方法は [PERSISTENCE.md](PERSISTENCE.md) を参照する。以下は当時の版・設定・観測結果の記録であり、途中段階の未実装・未確認・診断仮説を現在の仕様として扱わない。過去の証跡と旧ファイル名はそのまま残す。

## 2026-10-27 StrikeのPB/TOO分岐（training-12）

ユーザーが各SITE01～06へTPL_TANK_SITE##_01（Tank 3）とTPL_AMMO_SITE##_01（.Ammunition depot）を1個ずつ追加した保存済み.mizを確認した。全12個はRED/Russia・Static・未破壊で、名前/IDの重複なし。追加時にはSITE05のコンテナ2個の移動とME保存に伴うoptions/warehouses更新も含まれており、これらユーザー保存内容を維持する。

受注時にTOO/PBを各1/2、近い2施設の使用可能な1施設、その方式の3対象を各1/3で抽選・固定する。TOOは見出しだけSTRIKE MISSION (TOO)にし、従来の司令部DDM3桁・7個生成・任意2コンテナ/司令部/トラックの条件を維持。PBは司令部・燃料タンク・弾薬庫から1個を選び、9個生成・指定1個破壊。座標の意味をユーザーに確認し、共通施設基準点ではなく、抽選した目標そのもののDMS秒小数2桁＋その地点の地表標高ft MSLをTARGET AREAの同じ行に表示することを確定した。

原本54個を起動時に除去。方式間で施設予約を共有し、PB追加構成の不備はPBだけ無効化する。Statusは公開済み本文を再表示し、達成後は座標/標高なし20秒。スモークはTOO基準点/PB目標の北50 m。両方式は既存strikeScoreと150/90/0、schema4を共有しHookは変更しない。

Lua全476ケース（11スイート、Strike67）・BUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2・INTERDICTIONME2が通過。実.mizの全36選択でTOO7/PB9個の生成位置・対象・達成・削除を模擬確認した。実DCSの地表標高・PP入力・実射・信管/耐久はMAN-63として未実施。既定.mizへSync/Check成功。ZIP CRC・結合Lua一致・直前版と同一のbackupを確認し、変更は埋め込みDynamicTraining.luaのみ。他8エントリ（mission設定、warehouses、options、MOOSE、リソース等）は同期直前のユーザー保存版と同一。

## 2026-10-17 Air Interdiction追加（training-11）

ユーザー保存済みのTPL_AI_01～06を確認。各RED/Russia・Late Activation・Tigr/BTR-70/Ural各1両、全8WPがOn Road・9.25 m/s、最終WPからWP0へ戻る指示あり。全体のMEグループ/ユニット名とIDは一意。WP0のOption30・60.96は車間距離約61 mであり、Disperse under fireの設定と混同しない。TPL_AI_04内の複製元名TPL_AI_03-1-*も有効な一意名として維持した。ME位置・経路・設定は変更しない。

受注時の長機から近い2周回中心のうち使用可能な1地域を抽選し、ME経路を使う3両を即生成するTask: Air Interdictionを追加。周回中心は全WPの外接矩形中心、DDM分小数3桁でTOO捜索を案内し、3両全滅で達成。Statusは公開済み本文、達成後は座標なし20秒。共有達成と個人150/90/0、地域排他・削除再試行を実装。schema4へairInterdictionScoreを追加し、schema1/2/3の移行と独立保存/復元を確認する。サーバーHook更新・DCS再起動が必要。

Lua全459ケース（11スイート、Air Interdiction39・Persistence48）とBUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2・INTERDICTIONME2を検証。実.mizの全6中心から近い2候補の12選択で元経路保持・生成・中心・3両破壊・削除を模擬確認し、既定先へSync/Checkする。実走行・橋・散開後復帰・実射・実サーバー保存はMAN-62として未実施。

## 2026-10-17 Strikeを6施設のTOO捜索・攻撃へ変更（training-10）

ユーザーがMEで旧飛行場の25物体を削除し、SITE01～06へ司令部1個・コンテナ4個・Staticトラック2両の7個セットを配置した保存済み.mizを確認した。MEグループ名はTPL_CMD / TPL_CONT / TPL_TRUCKで、実ユニット名の末尾-1の有無が混在するためMOOSE登録済みStaticNameから解決する。ME名・座標・向き・物体は変更しない。

受注時の長機から司令部配置点までの距離で近い2施設を固定し、使用可能な1施設と3種類の攻撃対象を等確率抽選する。ユーザー確認により、倉庫任務は4コンテナの任意2個、司令部任務は1個、トラック任務は2両の破壊。原本42個を起動時に除去し、受注時は選択施設の7個をすべて生成する。対象候補4/1/2個と必要数2/1/2個を分離し、周辺設備を達成必須にしない。Missions.strikeSitesで施設予約し、全員終了後は全7個の削除を確認して解除する。

ブリーフィングを施設基準点のTARGET AREA・DDM分小数3桁へ変更し、PP用DMS・標高を除いた5行でTOO捜索を案内する。Statusは公開済み本文だけ、達成後は座標なし20秒を維持。任意スモークは施設案内点北50 m・赤・約120秒、連打防止・停止再試行・旧callback拒否を維持した。採点150/90/0・MP2・schema3・サーバーHookは変更しない。

全10Luaスイート418ケース（Strike50）、BUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2が通過。任意2コンテナの全6組、損傷・重複死亡・観測不能、周辺設備の生成/残存/削除、6施設×3種類の全18選択を模擬検証した。実.mizへSync/Checkし、ZIP CRC・bundle一致・同期直前backup一致・登録済みDynamicTraining.lua以外の全内容不変を確認した。実DCSのTOO捜索、Command Centerを破壊する兵装・信管、3D配置・煙の見え方・MP2実射精算はMAN-60/61で確認待ち。

## 2026-10-16 Strikeの任意目標スモークを追加

ユーザー指定により、受注Wingに操縦中・未精算の登録者がいるACTIVE StrikeへF10のMark Strike Targetを追加した。要求時だけ案内点の北50 mの地表へ赤煙を1本出し、約120秒後・達成・全員終了時に停止する。色・北オフセット・時間はConfig.strike.smoke、点煙・停止はMOOSE COORDINATE:Smoke/StopSmokeを使用する。グローバルSmokeOffsetの影響と追加乱数を避け、効果名は任務・要求ごとに分離する。

連打による重複を拒否し、点煙通知はStatusの座標ブリーフィングを上書きしない。古いcallbackは任務・状態・Wing・操縦中登録者を再照合する。点煙後の例外も効果参照を保持し、停止失敗を5秒ごとに再試行する。煙の寿命は基地予約とStatic削除から分離し、煙APIの失敗で任務・精算を中断しない。MP2で任意メニューと個人Abortが増えても操作できるよう、9コマンドごとにMoreを追加し、各ページ10項目以内にした。

STRIKE-33～43を追加し、全施設の点煙位置・色・地表高度、手動のみ・期限・再要求・Status維持、達成/Abort停止、MP2・並行Wing・旧callback、API失敗・停止再試行、メニュー到達性を模擬検証した。Lua全411ケース（10スイート、Strike43）とBUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2が通過。仕様・メッセージ一覧・タイムライン・日英BRIEFING・ARCHITECTURE・TESTINGを更新し、実.mizへSync/Checkした。ZIP CRC・bundle一致・登録済みDynamicTraining.lua以外の内容不変を確認。実DCSの煙の見え方・停止・MP2メニューはMAN-61で確認待ち。

## 2026-10-16 Strike座標をJDAM/JSOWのPP入力向けDMSへ変更

ユーザー指定によりStrikeのTARGET LOCATIONをDMS（度・分・秒、秒の小数2桁）へ変更した。COORDINATE:ToStringLLDMSへLL_Accuracy=2を明示し、MOOSE全体の表示設定から独立させた。座標と地表標高ft MSLの同一行・5行のブリーフィング・受注時とStatusの本文一致を維持する。CAP/SEAD/DEADは従来のDDM・分の小数3桁のまま。

STRIKE-02/03/12/31を更新。STRIKE-12では同梱MOOSEの実ToStringLLDMS・tostringLL・Roundを読み、既知座標の23.400分→23分24.00秒、秒の0埋め・2桁、全体精度設定5でも明示2桁になることを検証した。Lua全400ケース（10スイート）とBUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2が通過した。仕様・README・日英BRIEFING・メッセージ一覧・タイムライン・TESTING・AGENTSを更新し、実.mizのSync/Check・ZIP CRC・bundle一致・登録済みLua以外の内容不変を確認。実DCSでのPP入力・命中・表示はMAN-60で確認待ち。

## 2026-10-16 Strikeブリーフィングを5行へ整理

ユーザー指定により、STRIKE MISSION・TARGET LOCATION（DDM座標と地表標高ft MSLをカンマ区切りで同じ行）・OBJECTIVE・報酬・人数の5行へ変更した。TARGET BASE、TARGET、独立したTARGET ELEVATION行は表示しない。破壊指示は選択施設に応じて燃料3基・弾薬庫・倉庫で切り替える。受注時とMission Statusは同じ本文を使い、達成後の座標除外・表示時間・抽選・生成・採点は維持する。

STRIKE-02/03/12で全施設の本文・座標と標高の同一行・60秒を照合し、Lua全400ケース（10スイート）とBUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2が通過。仕様・メッセージ一覧・タイムライン・TESTING・AGENTSを更新した。実.mizのSync/Check、ZIP CRC、bundle一致と埋め込みDynamicTraining.lua以外の内容不変を確認した。実DCS表示はMAN-60で確認待ち。

## 2026-10-16 Strike固定施設任務を追加（training-9）

ユーザーが赤基地5か所へ配置した燃料3基・弾薬庫1棟・倉庫1棟（25物体、15施設候補）を使用するTask: Strikeを追加した。受注時の長機位置から近いRED基地2か所に限定し、使用可能な基地と3施設を等確率で抽選する。地上でも即生成し、誤差を加えないDDM精度3の座標1組と地表標高ft MSLを案内する。燃料は3基の中心を案内し、3基全滅で達成とする。未選択施設は生成しない。

起動時のME原本除去、SPAWNSTATICによる同位置・同方向の生成、任務別の一意な名前・新規ID、Missions.strikeBasesでの基地単位予約を追加した。両近傍基地が使用中なら解除し、3番目へ変更しない。nil・観測失敗・ID不一致を全滅根拠にせず、static死亡イベントとLife0も扱う。全員終了後に生成物を削除し、削除失敗中は基地予約を維持して再試行する。MOOSE登録前に例外が起きたnative Staticは一意名で直接取得してrollbackする。帰還150・達成後事故90・未達成事故/Abort0、MP2個別精算とStatusの達成後座標除外を共通機構へ接続した。

保存schema3へstrikeScoreを追加し、schema1/2の既存得点・CAPを保持してStrike=0へ移行する。mission/Hook両bundleを更新した。サーバーに導入済みのHookはこの作業では変更しておらず、更新とDCS再起動が必要。実成績データは変更していない。

Lua全400ケース（INT23・CAP35・SCORE26・WING27・PAR17・SEAD71・DEAD105・PERSIST46・MAP18・STRIKE32）とBUILD2・SYNC3・INSTALL5・ZONES3・STRIKEME2が通過した。実.mizの25テンプレート・5赤基地を確認し、15施設すべてのME位置での生成・削除を模擬検証した。実.mizのSync/Check、ZIP CRC、埋め込みbundle一致、登録済みDynamicTraining.lua以外の内容不変を確認した。仕様・画面一覧・タイムライン・日英BRIEFING・採点・保存・ARCHITECTURE・TESTINGを更新。DCS内の実射・3Dの埋まり/重なり・実基地中心での距離選定・新Hookでの保存/復元はMAN-60で確認待ち。

## 2026-10-15 達成後のMission Statusから座標を除外

ユーザー指定により、目標達成前は公開済み座標ブリーフィングと開始指示を再表示し、達成時にStatus用のブリーフィングを外す方式へ変更した。達成後は公開済みの達成結果・帰還指示だけを20秒表示する。SEAD達成後にContinue as DEADを選ぶと新しい実配置座標入り本文へ切り替わり、DEAD達成時に再び座標を外す。任務判定・帰還・採点・Site寿命は維持する。

CAP-35・SEAD-70/71・DEAD-08/104/105を現行仕様に合わせ、達成前の座標維持、達成後の座標除外と20秒表示、座標90秒設定でも達成通知は20秒、DEAD継続による座標復帰を検証した。仕様書・表示一覧・日英BRIEFING・ARCHITECTURE・TESTINGを更新。Lua全366ケース（9スイート）とBUILD2・SYNC3・INSTALL5・ZONES3が通過。実.mizをSync/Checkし、ZIP CRC・埋め込みbundle一致と登録済みDynamicTraining.lua以外の内容不変を確認した。DCS内の表示はMAN-59で確認待ち。更新版.mizでミッションを再開始して適用する。

## 2026-10-15 Mission Statusを公開済み情報の再表示へ変更

ユーザー指定により、内部状態から詳細レポートを組み立てる方式を廃止。mainのPublishMissionが案内した座標ブリーフィングと最新の開始／達成通知を任務record.publicReportへ保持し、MissionReport.Statusはその本文だけを再表示する。開始・達成後も座標を維持し、達成通知は開始通知を置き換える。Continueでは最新のSite座標入り開始本文へ切り替えて旧SEAD推定点を重ねない。計画中は受注・計画中通知だけで、MODE・SAM種類・PBコード・試行数を先出ししない。

Statusから敵残数・出現有無・発信状態／OFF秒数・Site/予約状態・Wing/長機・参加者別の内部状態・精算行を除去した。Continue本文の残数は公開時の値を再掲し、現在数へ更新しない。Preserve/Release・個人精算・拒否・エラー・CAP進捗通知は再表示用情報を上書きしない。未使用になったCAP.Status/SEADObjective.Statusも削除。任務判定・監視・採点・帰還・ロック・Site寿命・Hook/schemaは維持する。

INT-23・CAP-35・PAR-17・SEAD-70/71・DEAD-104/105を追加し、計画中の秘匿、開始／達成後の座標維持、公開後の計画座標変更や再計算API例外でも本文が変わらないこと、未公開フィールド／観測環境を参照しない純粋な再表示、別Wing・移動UCID・複数関連任務の範囲を検証した。旧Statusに内部状態を期待していた回帰テストは内部データの直接検証へ移し、Site Refreshの観測テストもStatusの副作用に依存させない。

Lua全366ケース（INT23・CAP35・SCORE26・WING27・PAR17・SEAD71・DEAD105・PERSIST44・MAP18）とBUILD2・SYNC3・INSTALL5・ZONES3が通過。実.mizのSync/Check・ZIP CRC・埋め込みbundle一致を確認し、変更内容は登録済みDynamicTraining.luaだけ。仕様・一覧・日英BRIEFING・ARCHITECTURE・TESTINGを更新。DCS内の表示はMAN-59で確認待ち。更新版.mizでミッションを再開始して適用する。

## 2026-10-15 DEADの座標行・ブリーフィング順序を整理

Immediate DEAD開始通知を開始・指示・残数・SITE LOCATION・追加報酬・SEAD報酬保持の順へ変更し、座標をラベルと同じ行にまとめた。Follow-on DEAD受注ブリーフィングはDEAD MISSION・TARGET SITE・SITE LOCATION・STATUS・OBJECTIVE・報酬・人数の順とし、AREA行を削除した。共通DEAD.Briefingを使う両DEADのMission StatusとDEBUGにも同じ整形を適用する。Status外枠の地域表示は維持する。

DEAD/SEAD仕様・MESSAGES・MESSAGE_FLOW・AGENTS・TESTINGを更新。DEAD-08でImmediate全文と90秒設定を照合し、DEAD-16をSA-6破壊済み／抑制済み・SA-8抑制済みに広げ、Follow-on全文・AREA行除外・Statusの同じ本文を検証した。座標精度・実配置点・失敗時のrollback・秘匿条件・表示時間・採点や状態遷移は維持する。

Lua全359ケースとBUILD2・SYNC3・INSTALL5・ZONES3が通過。実.mizをSync/Checkし、登録済みDynamicTraining.lua以外のZIP内容が不変、CRC正常を確認。実DCSでの表示確認は今回未実施。更新版.mizでミッションを再開始して適用する。

## 2026-10-15 SEAD PB表示の簡略化・抑制条件を30秒へ変更

PBブリーフィングの `THREAT AREA` を地域名から実配置点より1〜3 NMずらした推定DDM座標へ変更し、別の `ESTIMATED LOCATION` 行を削除した。共通のSEAD.Briefingを使う計画確定通知・手動Mission Status・DEBUGの計画本文すべてに適用し、SAM種類・PBコード・推定誤差・正確な位置の秘匿を維持する。

`sead.suppressionHoldSeconds` を60から30へ変更した。TOO/PB・SA-6/SA-8とも、開始時Lifeから損傷しRadar OFFが連続30秒でSUPPRESSEDとなる。開始通知とStatusの分母も同じ設定を参照する。無傷OFF、再発信・観測不能によるリセット、破壊時の即達成、報酬150/90、座標表示60秒は維持する。

SEAD/DEAD仕様を先に更新し、既存テストの未達成29秒／達成30秒境界、リセット、複数レーダー、別Wing、事故順序とDEAD解放境界を合わせた。PBの推定座標・旧ラベル／地域名行の除外を地上／空中受注とStatusで検証。Lua全359ケースとBUILD2・SYNC3・INSTALL5・ZONES3が通過。最初の隔離環境の一時ファイル置換失敗後、通常権限で全統合検証も完了した。

実.mizをSync/Checkし、変更したZIP内容は登録済みDynamicTraining.luaだけ。ME設定・Zone・ニーボード等は維持、ZIP CRC正常。README・AGENTS・BRIEFING・SCORING・WING・MESSAGES・MESSAGE_FLOW・TESTINGを現行値に合わせた。実DCS内の表示・30秒判定の実測は今回未実施。更新版.mizでミッションを再開始して適用する。

## 2026-10-15 全任務の画面通知・分岐タイムラインを整理

表示を見直す依頼に対し、main・各任務・MissionReport・Notifications・Recovery・Player/Missions・Persistence・Configを照合し、MESSAGE_FLOWへ日本語の一覧を追加した。Intercept / CAP / SEADのTOO・PB / Immediate DEAD / Follow-on DEAD、保持・開放・何も選ばず帰還、個人精算・Abort・拒否／例外・手動Status・Statisticsを対象とし、本文・表示時間・発生条件・回数・無通知の遷移を整理した。

連続する通知は表示時間の終了を待たないこと、Immediate DEAD未達帰還の個人終了、Statusの情報重複なども明記。表示見直し候補は未実装として分離し、既存MESSAGESのIdle例のCAP欠落と生成カウントダウンの説明を現実装に合わせた。README・ARCHITECTUREから参照できる。文書のみの変更で、ソース・実.miz・画面文言・採点・状態遷移は変更していない。実DCSでの通知の重なり方は今回検証していない。

## 2026-10-14 Interceptの生成距離を90〜110 NMへ変更

ユーザーのレーダー索敵時間を増やす依頼で、Interceptの水平生成距離を60〜80から90〜110 NMへ変更。地上受注の全員離陸後20秒待ち、空中受注の即時生成、機首方向±60°、HOT、テンプレート・編隊・高度・速度・採点は維持した。README・Intercept・AGENTS・日英BRIEFING・MESSAGESのDEBUG例とTESTINGを合わせた。

INT-08は90/100/110 NMの距離と全方位・偏角境界で配置・HOT・経路を検証し、抽選APIの上下限90/110も確認。既存の明示抽選fixtureとWingの長機基準の位置期待値を更新した。Lua全359ケースとBUILD2・SYNC3・INSTALL5・ZONES3が通過。実.mizをSync/Checkし、登録済みDynamicTraining.lua以外のZIP内容とME設定・Zone・ニーボードが不変、ZIP CRC正常を確認。新距離での実レーダー検出タイミングは実飛行確認待ち。

## 2026-10-14 Zone地域名・CAP/SAM離隔・SEAD実生成確認

ユーザーがMEでSEAD4円の中心を移動し、名称の整合と生成可否の検査を依頼。最新保存座標を基準に、Osmaniye→Turkoglu、Islahiye→Hassa、Morphou East→Morphou North、Nicosia North/East→Gecitkale EastへZone参照名と画面地域名を合わせた。ユーザー回答に従いSEAD中心・半径を維持し、BeirutのSEAD4候補を許容する。

CAPは引き続きSAM射程外へ移す依頼があり、Homs West→Latakia South、Iskenderun→Hatay South、Osmaniye→Mersin Southの3円を移動・改名。全CAP9×SEAD10の90組で円外縁間隔を、最大SAM計画射程15 NM＋安全余裕5 NM以上とし、最短23.8 NM。全15 ClientのCAP2〜3・SEAD2〜4候補を検証した。計画射程はSA-6:15/SA-8:8 NM、余裕5 NMをConfigに置き、Test-ZoneCoverageの第3確認グループで継続検査する。CAP円外への進入・追撃やCAP敵機の円外経路まで隔離するものではない。

変更前を.miz.cap-sead-20261014.bakへ保存。mission全体の意味比較で7円の名前とCAP3中心以外が不変なことを確認し、登録済みLuaをSync/Check。ZIP比較でもmission・DynamicTraining.lua以外の内容、給油機・AWACS・空母・ニーボードを維持した。

任意SpawnCheck診断を追加し、適合した最初の地点へ通常SEAD.Spawnで各SAMを1回生成、構成・主要レーダー・活動状態・実位置を確認して削除する。最初の実行はPalmyraのSA-6を生成できたが、同フレームでの削除確認が早すぎて停止。削除反映を最低3秒待つよう修正し、10秒で確認できなければ停止する方式を模擬テストへ追加した。最初の部分ログは合算しない。

DCS 2.9.30.28738の隔離プロファイルで15:30:58〜15:40:00 JSTに全20組合せ各50点・計1,000点を再実行。適合396点・観測エラー0、実生成20・削除確認20、生成／削除エラー0。全地域で両SAMを生成できた。ただしMorphou NorthのSA-8は1/50、初回43回目であり、配置の安定性には改善余地がある。保存座標を維持する指定に従い追加移動は行わなかった。診断用DCSだけを終了し、通常Config・Hook・成績を変更していない。HARM交戦・抑制FSM・帰還採点の通し確認は未実施。

Lua全359ケース（SEAD69を含む9スイート）、BUILD2・SYNC3・INSTALL5・ZONES3が通過。詳細表・ログ所在はSEAD_PLACEMENT_CHECK、全座標・距離・改名対応はTRAINING_AREAS。MEで開いていた場合は更新版を開き直し、サーバーでは更新した.mizでミッションを再開始する。

## 2026-10-13 Continue直後の通知にも実配置座標を追加

追加依頼で、Continue as DEADの開始通知末尾へSITE LOCATIONと正確なSite座標を追加。従来の開始・指示・残数・報酬の5行は維持し、DDM・分の小数3桁で1回表示する。座標表示時間は共通のcoordinateBriefingSeconds（初期60秒）へ変更。座標取得・整形は移行前に行い、失敗時は元SEADの帰還評価と採点・Site状態を維持する。Continue前・Preserveのみの秘匿と手動Statusの表示は維持する。

DEAD-08でTOO/PB両経路の通知本文・座標・90秒設定・自動再掲なしを確認し、DEAD-75で座標API失敗時の移行拒否とSEAD150の帰還精算を検証。Lua全356ケースとBUILD2・SYNC3・INSTALL5・ZONES2が通過。実.mizをSync/Checkし、登録済みDynamicTraining.lua以外のZIP内容とニーボードが不変、ZIP CRC正常を確認。DCS内の実表示は確認待ち。

## 2026-10-13 Immediate DEADの実配置座標表示

ユーザー依頼で、Continue as DEAD後のMission Statusへ既存のDEADブリーフィングを追加。Follow-onと同じSite実配置基準点をSITE LOCATIONとしてDDM・分の小数3桁で表示し、DEAD達成後の帰還待ちでも維持する。車両ごとの座標ではない。元SEADの推定点は変更せず、Continue前・Preserveのみでは実配置点を秘匿する。Continueの自動通知へ座標は追加しない。

DEAD-08をTOO/PBの両方式へ拡張し、移行前と保持時の秘匿、移行後と達成後の正確な座標・SAM種類、DDM精度・90秒の設定反映、元計画・損傷・発信状態の維持、再Spawn・再抽選なしを検証。Lua全356ケースとBUILD2・SYNC3・INSTALL5・ZONES2が通過。実.mizを同期し、登録済みDynamicTraining.luaだけの変更、ニーボードとME設定の不変、Sync/Check・ZIP CRCを確認した。DCS内の表示は確認待ち。

## 2026-10-13 origin/mainとのマージ競合解消

ローカル `4cc137a`（Add Tankers and delete AI2）とリモート `46cd17d`（Fix log）のマージで、main.lua・MESSAGES・TESTING・実.mizが競合した。テキストはCRLF/LFの差を除いて比較し、ローカルのタイトルだけのIntercept開始通知とSOLO/MP2の説明を維持しながら、リモートの敵削除待ち・再試行時の画面ERRORを出さない変更を統合した。INT-19/22の画面非表示検証も維持する。

実.mizはローカル保存済みのME設定・options・給油機入りニーボードを維持して結合済みLuaを同期。競合時のローカル版との比較でDynamicTraining.luaだけが変わり、その他のZIP内容は不変。リモート側の埋め込みMOOSEとの差は改行だけで、採用中のvendorをそのまま使う。Lua全356ケース、BUILD2・SYNC3・INSTALL5・ZONES2が通過し、実.mizのSync/Check・PNG一致・ZIP CRC確認も成功した。競合各版はbuild/merge-conflict-20261013に検査用コピーを残した。DCS内の実動作確認は未実施。

## 2026-10-13 ニーボードへ給油機追加・ME保存の整合性確認

ニーボードを空港・空母・給油機の3表に更新し、Texaco 1-1（251.10 MHz AM・31Y/TEX）とArco 1-1（251.20 MHz AM・32Y/ARC）を追加。給油機の列は給油機・無線周波数・TACANの3つとし、ユーザー指定により高度・速度を掲載しない。既存の空港値と空母74X/CVN・ICLS 1は維持した。

ユーザーがMEを開いたままにしていたため、画像更新前に保存済み.mizの整合性を確認。最新のタイトルだけのIntercept開始通知とLua同期、SOLO5/MP2 5/Client15・AI2なし、全19訓練Zone、5敵テンプレートのLate Activation、機体IDとビーコン対象、空母の往復、全リソース参照、同梱PNG一致、ZIP CRCが正常だった。Test-ZoneCoverageの2確認グループも通過し、全出撃位置でCAP / SEAD各2〜3候補を維持する。

画像更新直前を `.miz.kneeboard-update.bak` に保存し、同梱PNGだけを差し替えた。更新前後でmission・Lua・resource mapping等の他ZIPエントリはすべて不変、編集元PNGと同梱版が一致、Sync-Mission -Check成功。保存済みAWACSのOrbitは28,000 ftであり、現在の前提をIntercept仕様にも合わせた。DCS内の実表示・MEに読み込まれたメモリ内状態は確認していないため、次の保存前に更新版を開き直す。

## 2026-10-13 Intercept開始通知の簡略化

ユーザー依頼でIntercept開始時の画面表示を `Intercept MISSION START` の1行だけに変更。表示は従来どおり15秒・生成成功時に1回。Range・Altitude・Aspect: HOTはHostiles・PilotsとともにDEBUG開始ログだけへ残し、MESSAGEログは画面と同じ1行にする。受注・生成条件・手動Status・採点は変更しない。

INT-16を更新し、単独/MP2と地上/空中受注の全組合せで、開始通知の本文・表示時間・重複防止、詳細の画面非表示とDEBUG記録を確認。Lua全356ケースとBUILD2・SYNC3・INSTALL5・ZONES2が通過。初回の統合検証はWindowsのsandbox内の一時ファイル置換制約で止まったが、同じテストを通常権限で再実行して通過した。

実.mizのSync/Check成功。同期前backupとのZIP比較で登録済みDynamicTraining.luaだけが変わり、ユーザーがMEで保存した給油機・AI2削除・その他設定と同梱ニーボードが不変なことを確認した。DCS内の実表示は確認待ち。

## 2026-10-13 AI2削除後の構成・仕様書更新

ユーザーがMEで5拠点のAI2グループを削除。実.mizを照合し、SOLOが5グループ・各Client ×1、MP2が5グループ・各Client ×2、合計10グループ・15 Clientスロットで、AI2グループとBLUEのAI Hornetが残っていないことを確認した。敵のIntercept3テンプレート・SEAD2テンプレートとミッション同梱ニーボードも維持されている。

README・AGENTS・Intercept・WING・SCORING・ARCHITECTURE・TESTINGの現在の配置説明をSOLO/MP2へ合わせ、MESSAGESの旧グループ名の例を実在するMP2名へ更新。AIを参加者・精算対象に含めない判定と回帰テストは維持し、過去のAI2を使った実測ログは当時の履歴として残す。関連する記述で古いStennis表記も実.mizのCVN_71へ訂正した。

実.mizの全15 Client出撃位置でCAP / SEADが各2〜3候補となり、Test-ZoneCoverageの2確認グループが通過。Sync-Mission -CheckとZIP CRC確認も成功した。今回の作業は仕様書の更新であり、Luaやユーザー保存済み.mizは変更していない。削除後の実DCS出撃は確認待ち。

## 2026-10-12 空港・空母ニーボードを同梱

BLUEの4空港の座標・ATC VHF/UHF・TACAN・VORと、CVN-71の無線・TACAN・ICLSを別表にしたPNGを実.mizの `KNEEBOARD/IMAGES/01_BLUE_AIRFIELDS_AND_CARRIER_SYRIA.png` へ追加。ユーザーがMEで変更した空母74Xの識別コードCVNを確認し、画像もCVNへ更新した。空母座標・LINK 4・下部説明文は掲載しない。

追加前の実.mizを `.miz.kneeboard.bak` に保存し、既存8 ZIPエントリの内容不変、追加画像と編集元PNGの一致、ZIP CRC正常を確認。Sync-Mission -Check成功。DCS内の実表示は確認待ち。画像は静的なため、MEの航法設定を変更した際は編集元と同梱版を更新する。

## 2026-10-12 CAP / SEAD ZoneをMEへ統一（training-8）

ユーザーからLua追加ゾーンもMEへ反映し、二通りの定義をなくす依頼を受けた。CAP5＋SEAD6の計11円を既存と同じ名前・中心・半径18,288 mで実.mizのTrigger Zoneへ追加し、zoneId 312〜322を割り当てた。CAP9 / SEAD10の全19円をMEで管理し、Configは候補名・地域表示名・距離条件だけを持つ。CAP / SEAD / 配置診断はZONE:FindByNameで直接取得し、Config.zoneDefinitionsとtraining_zones.luaを削除した。

移行直前のユーザー保存済み.mizを `.miz.zones-migration.bak` として保存。既存8円の全項目、AWACSの燃料無限先頭、空母の往復・TACAN/ICLS/Link4、スロット・テンプレート・トリガー動作・その他のmissionフィールドを維持した。Sync後のZIP比較でも、Zone追加を含むmissionと既存DynamicTraining.lua以外の内容不変を確認した。HEADとの差分に含まれるユーザーのME変更も巻き戻していない。

全356 Luaケース、BUILD2、SYNC3、INSTALL5、ZONES2が通過し、実ミッションSync/Check成功。全出撃ClientでCAP / SEAD各2〜3候補を維持。ZONESの第2確認グループは旧Lua代替円の検証をME実体の参照・Zone欠落時解除・復旧後再受注へ置換した。最初のCAP-31実行では死亡後の再搭乗が旧CAP位置のままで次の任務を受けられず失敗したため、fixtureを出撃地点へ戻す実際の再搭乗条件へ修正し、GC・イベント受信の期待値は維持した。失敗記録はbuild/zone-migration-test-failure.log。

全19円の移行前後の幾何一致を確認し、2026-10-09の地形標本は同じ範囲の実測として残す。今回の移行後に実DCSで再抽選・Spawn・交戦した記録ではない。地域指定の配置診断ミッションはビルド確認済み。ME表示確認にはファイルを開き直し、サーバー反映には更新した.mizでミッションを再開始する。Hook更新は不要。

## 2026-10-09 追加SEAD半径の統一と配置中心の改善（training-7）

追加6地域を先にMEと同じ半径18,288 mへ拡大し、全20組合せ各50点を実DCSで再検査した。中心不変では適合310/1,000・観測エラー0。適合点の少ないIslahiye / Akkar / Morphou / Nicosiaは診断座標を根拠に中心を調整し、同じLAND・高低差・障害物条件で再検査した。最終位置のSA-6/SA-8はIslahiye10/12、Akkar14/10、Morphou7/7、Nicosia6/9（各50点）。全10地域・両SAMの最終設定に一致する複数実行を合算した結果は適合352/1,000・観測エラー0。単一の1,000点連続実行とは区別する。

Morphou East / Nicosia Eastへ表示地域名を合わせ、Zone識別子は維持した。4空港と空母の全出撃Client駐機位置でCAP / SEADの2〜3候補を維持する。Nicosiaは一部駐機位置の40 NM境界を避けるよう中心を再調整した。中心・距離はTRAINING_AREAS、条件別結果と生ログ所在はSEAD_PLACEMENT_CHECKを参照。

ボタン操作なしでSteamの通常コマンド起動を使い、隔離プロファイルだけで検査して終了した。通常Config・Hook・成績は変更しない。Lua全356ケース、BUILD2、SYNC3、INSTALL5、ZONES2が通過。実ミッションSync/Check成功、既存DynamicTraining.lua以外のZIP内容不変を確認。SAMの実Spawn・交戦は確認待ち。

## 2026-10-09 全SEAD地域の実地形50点抽選

通常のSEAD計画からSEAD.CheckPlacementを抽出し、同じ判定で全10地域×SA-6/SA-8を各50点、計1,000点検査する専用ミッションを作成した。SAM実Spawn、任務台帳・採点・保存bridgeは起動しない。既存Triggerやテンプレートを変更せず、検査用コピーだけに既存埋め込みLuaをSyncした。

最初の直接起動はSteamが再起動を要求した。隔離プロファイルのserver起動はLogin failed code 400と空のTerrainでミッションを開始できず、検査結果として扱わない。検査プロセスだけを止めて、--norender / --nopause / --mission-fileによる直接読み込みへ変更し、Syriaの実地形読み込みと検査開始を確認した。

2026-10-09 09:11:49〜09:20:11 JST、DCS 2.9.30.28738 / Syria terrain revision 7039で20 RESULTとCOMPLETE checked=1000/passed=350/errors=0を確認。9地域は両テンプレートで50点以内に適合点を発見。

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

Islahiyeは両テンプレート0/50、高低差拒否が合計96/100点。MorphouとNicosia Northも適合点が少なく、配置候補の中心・範囲に改善余地がある。設定は今回変更していない。診断中に描画model読み込み警告が出ており、実Spawnと通常描画の確認は未実施。拒否理由・対象hash・生ログの所在は [SEAD_PLACEMENT_CHECK.md](SEAD_PLACEMENT_CHECK.md) を参照する。MAN-57の静的配置診断は実施済み、MAN-06の実Spawn・交戦確認とは分ける。

Lua全356ケース（SEAD66）、BUILD2、SYNC3、INSTALL5、ZONES2が通過し、実ミッションのSync/Checkも成功。SEAD-63〜66は診断制御の模擬テストで、実地形結果と混ぜない。検査完了後に検査用DCSを終了し、通常Config・Hook・実成績・MissionScripting.luaは変更していない。

## 2026-10-09 CAP距離制限と訓練地域追加（training-6）

受注位置からの距離を見ずに4空域から選ぶCAPでは、Ramat→North CoastやIncirlik→Golanで中心まで約216 NMとなっていた。従来SEADの40〜130 NM条件ではIncirlik・Akrotiri・空母の初期位置に候補がなく、Beirutは2候補、Ramatは1候補だった。

CAPを受注時長機から中心40〜100 NMに限定し、既存4空域に5円を追加。SEADは40〜130 NMを維持して既存4地域に6円を追加した。追加円はConfig.zoneDefinitionsから非登録MOOSE ZONE_RADIUSとして用意し、ME設定を変更しない。既存ME Zoneを優先し、中心・半径・名前を維持する。CAP候補なしは通常通知20秒とロック解放、採点なしで拒否する。

実.mizの全BLUE Hornet Client駐機位置で両任務ともIncirlik/Beirut/空母は3、Akrotiri/Ramatは2候補。各出撃地点の全候補の受注、SEAD計画・Spawn、中止・ロック解放を本番bundleと模擬地形で確認した。配置と距離はTRAINING_AREAS.mdにまとめる。

Lua全352ケース（CAP34、他スイート件数維持）、BUILD2、SYNC3、INSTALL5、ZONES2が通過。最初の一括検証はサンドボックス内の一時file置換で停止したため、通常環境で再実行して全通過を確認した。実ミッションSync/Check成功、置換は既存の埋め込みLuaだけ。Hookの保存schemaや実保存データは変更していない。追加SEAD地域の実地形・建物条件・交戦、追加CAP空域はDCS内確認待ち（MAN-06/52/56）。

## 自動テスト・DCS確認の履歴

2026-10-04のDEAD追加前はLua145ケース、BUILDの2確認グループ、SYNCの3確認グループの通過を確認済み。
同日のPrimary Result/Site残存判定分離後はLua全211ケース（INT15、SCORE26、WING27、PAR16、SEAD61、DEAD66）、BUILDの2確認グループ、SYNCの3確認グループがすべて通過した。
同日のImmediate DEAD追加採点後はLua全221ケース（INT15、SCORE26、WING27、PAR16、SEAD61、DEAD76）、BUILDの2確認グループ、SYNCの3確認グループがすべて通過した。DCS内の追加採点確認は未実施。
同日のTOO/PB DDM表示変更後もLua全221ケースが通過し、実ミッションのLua同期・Checkが成功した。DDM表示のDCS内確認（MAN-07/08）は未実施。
同日のSite/DEAD nil観測修正・SEAD FSMのnil観測経路修正・Follow-on DEAD DDM統一後はLua全225ケース（INT15、SCORE26、WING27、PAR16、SEAD61、DEAD80）が通過した。BUILDの2確認グループ、SYNCの3確認グループも通過。DCS内のFollow-on座標確認（MAN-28）は未実施。
2026-10-05のSEADブリーフィング重複修正後はLua全226ケース（INT15、SCORE26、WING27、PAR16、SEAD62、DEAD80）が通過した。BUILDの2確認グループ、SYNCの3確認グループ、実ミッションのLua同期・Checkも成功。DCS内の自動表示回数とStatus再確認（MAN-07/08）は未実施。
同日の座標表示時間延長・Intercept受注通知整理後はLua全227ケース（INT16、SCORE26、WING27、PAR16、SEAD62、DEAD80）が通過した。表示時間の初期60秒と設定変更後90秒、Intercept開始表示1回を模擬検証。BUILDの2確認グループ、SYNCの3確認グループ、実ミッションのLua同期・Checkも成功。DCS内の表示時間・回数確認は未実施。
同日の成績永続化実装後はLua全247ケース（既存227＋PERSIST20）、BUILD2確認グループ、SYNC3確認グループ、INSTALL3確認グループが通過した。INSTALLでは実ファイル保存・別Luaプロセスでの復元・破損primaryのbackup復旧も確認。実ミッションのLua同期・Checkも成功。DCS内のHook接続・再起動復元・停止callback順は未確認。
同日のImmediate DEAD未達成からのSEAD帰還修正後はLua全253ケース（INT16、SCORE26、WING27、PAR16、SEAD62、DEAD86、PERSIST20）、BUILD2、SYNC3、INSTALL3確認グループが通過した。未達成RTBのSEAD150／DEAD0、MP2個別精算と僚機継続、復行、確認中事故、確認中DEAD達成を模擬検証。実ミッションのLua同期・Checkも成功。DCS内のMAN-42/43は未確認。
同日、ユーザー承認後に `Saved Games/<ユーザーフォルダー>/Scripts/Hooks/DynamicTrainingPersistenceHook.lua` へ導入し、生成bundleとのハッシュ一致を確認した。DCS再起動後の実機確認は未実施。
同日の保存Hook通信修正後はLua全258ケース（既存233＋PERSIST25）、BUILD2、SYNC3、INSTALL5確認グループが通過した。Hookとミッションの別Lua環境・文字列通信・API拒否・不正返信・再接続、ホスト設定の保持・backup・idempotence・不正設定拒否を検証。実ミッションのLua同期・Checkも成功。ユーザー承認後に実Saved GamesのHookとautoexec.cfgをbackup付きで更新し、Hookハッシュ一致・既存DLSS設定維持・userhooks→server許可ブロック1件を確認した。DCS再起動後の接続・精算保存・再起動復元は未確認。
同日のPreserve元Wing専用予約への変更後はLua全262ケース（INT16、SCORE26、WING27、PAR16、SEAD62、DEAD90、PERSIST25）、BUILD2、SYNC3、INSTALL5確認グループが通過した。元SEAD精算・再武装後の保持予約、別Wing拒否、同Wing内最寄り選択、所有者不明時の拒否、rollback後の保持予約維持、同UCIDの別Wing移動を検証。実ミッションのLua同期・Checkも成功。DCS内のMAN-30/44は未確認。

2026-10-06の明示予約解除・共有Site未予約30分Cleanup追加後はLua全275ケース（INT16、SCORE26、WING27、PAR16、SEAD62、DEAD103、PERSIST25）、BUILD2、SYNC3、INSTALL5確認グループが通過した。30分境界、元SEAD精算待ち、専用保持・地上使用予約中の保護、別Wing共有取得・二重取得拒否、期限前rollback、観測不能時timeout、削除再試行、複数Site個別解除、古いcallbackの拒否を検証。実ミッションのLua同期・Checkも成功。DCS内のMAN-45/46は未確認。

同日の画面通知整理後もLua全275ケース、BUILD2、SYNC3、INSTALL5確認グループが通過した。INT-16／SEAD-62／WING-02を変更し、生成待ち・リセット・Intercept開始詳細・TOO/PB攻撃指示のDEBUG専用出力、短い開始通知、通常メッセージのログ複写、座標秘匿・表示時間・一度だけの生成を検証。実ミッションのLua同期・Checkも成功。DCS内のMAN-47は未確認。

その後、ユーザー指定でInterceptのHostiles／Range／Altitude／HOTを画面開始通知へ戻した。Lua全275ケース、BUILD2、SYNC3が通過。INT-11/16で実編成との一致、開始15秒で1回、Pilotsとカウント通知はDEBUGのみ、通常本文のMESSAGE記録を検証。実ミッションのLua同期・Checkも成功。DCS内確認は未実施。

同日の追加整理後もLua全275ケース、BUILD2、SYNC3が通過。InterceptのHostiles、SEAD受注のMODE・計画のGround acceptance説明・開始PilotsをDEBUG専用にした。Follow-on DEADは受注10秒→座標ブリーフィング1回→座標なし開始25秒へ統一し、INT-11/16、SEAD-62、DEAD-16/17で画面／DEBUG分離、地上・空中の表示回数、Status再確認、配点・状態不変を検証。実ミッションのLua同期・Checkも成功。DCS内のMAN-47は未確認。
2026-10-06のBLUE陸上Airbase Drawing追加後はLua全293ケース（既存275＋MAP18）、BUILD2、SYNC3確認グループが通過した。既存7 Luaスイート・harnessは変更していない。作業開始時のmainはorigin/mainと一致するe3b98ad。実ミッションのBLUE airport ID6/16/30/44を静的確認し、4基地から8個のBLUE限定Drawingを作る追加模擬検証も通過した。Build・実 `.miz` のSync・Checkが成功し、同期前backupとの比較でDynamicTraining.lua以外の7 ZIP entryが不変、作業開始時のmission/warehouses/optionsも不変であることを確認した。ログはローカルの `build/map-overlay-inspection/` に置く。MAN-48/49のDCS内表示・可視性は未確認。

同日のMapOverlay文字位置修正後もLua全293ケース、BUILD2、SYNC3が通過。MAP-01でCircleの基地中心を維持し、Textのみ南1,000 mへ移動することを検証した。Build・実ミッションSync・Checkも成功。ユーザー提供のIncirlik画像では中心配置文字と通常基地名の重なりを確認したが、オフセット修正後の実DCS表示は未確認。MAN-48で文字の離隔を再確認する。

同日の黒縁追加後はLua全296ケース（既存275＋MAP21）、BUILD2、SYNC3が通過。青文字を維持したまま黒Textを8方向に描き、最後に青Textを描画すること、全10 IDのRefresh/rollback、縁幅変更/無効化を模擬検証した。Build・実ミッションSync・Checkも成功。ただしユーザー提供のBeirutの実DCS画像で黒文字が分離して見づらくなることが判明し、この方式は撤回した。模擬テストでは実描画の可読性を検証できていなかった。

同日の撤回後は黒文字の生成処理・設定・追加3テストを取り除き、南1,000 mに青文字1枚を置く前の状態へ戻した。Lua全293ケース（既存275＋MAP18）、BUILD2、SYNC3が通過し、Build・実ミッションSync・Checkも成功。オフセット版の可読改善はユーザー報告あり（版・倍率未記録）。全手動ケースの合格とは扱わない。

本書のLuaケース数・番号と実行ファイルの対応、READMEと本書のリンク先も確認済み。
2026-10-06のmission manager接続修正後はLua全296ケース（PERSIST28）、BUILD2、SYNC3、INSTALL5が通過。Hook/manager/実SSEの3環境を分離し、manager側a_do_scriptから型付き文字列だけを返す通信、dispatcher欠落時の非保存と復旧、旧server管理ブロックへのmission許可追加・server維持・backup・idempotenceを検証した。ユーザー承認後に実Hookとautoexec.cfgを更新し、Hookハッシュ一致と管理ブロック外の設定不変を確認。Sync/Check成功、CAP Zone4件保持。修正後の実DCS接続・保存・再起動復元は確認待ち。

同日18:11 JSTの実DCS再現でmission経路のAPI status=true・不正返信と保存未接続を確認した。戻り値が伝搬する旧manager fixtureは実環境を再現できていなかった。scripting直接接続への変更後はLua全297ケース（PERSIST29）、BUILD2、SYNC3、INSTALL5が通過。副作用は実行されてもmanager返信が失われる条件、dispatcher不在、status=falseの拒否を検証。実Saved Gamesへ最終Hookをbackup付きで配置しbundleとのハッシュ一致、autoexec.cfg全体の不変、実ミッションSync/Check成功とCAP Zone4件保持を確認。scores.datは未作成。新経路の実DCS接続・精算保存・再起動復元は確認待ち。

同日18:21 JSTの実DCSログでscripting経路のnil/nil返信と未接続を確認し、この経路は撤回した。ユーザーはPlayer Statisticsを押さず、起動時表示で判断したと報告。起動直後のSession only表示だけは失敗の根拠とせず、Hookエラー・後続の接続ログ・保存ファイルで判定する。mission/a_do_scriptへ戻し、報告された先頭nil・末尾値欠落に対応する末尾scalar回避策を追加。Lua全298ケース（PERSIST30）、BUILD2、SYNC3、INSTALL5が通過し、実ファイルの別プロセス保存・復元・backup復旧も位置ずれfixtureで確認した。実Hookをbackup付きで更新、bundleハッシュ一致、autoexec.cfg全体不変、Sync/Check成功、CAP Zone4件保持を確認。回避策導入後の実DCS接続・精算保存・再起動復元は未確認。

同日18:30 JSTの実DCS再現はprotocol取得後のScore storage unreadableで停止した。開始前/終了後のbridgeエラーを分離すると、実行中の失敗はLoad段階であり、スロット未選択は初期化失敗の原因ではない。通信・native I/O・transaction service・Hook寿命を分離し、errno欠落時の不存在確認、unreadable primary保護、Initialize返信喪失時の再統合防止、確認前のSaved抑止、Stop後frame抑止、slot未選択接続を追加検証。Lua全306ケース（PERSIST38）、BUILD2、SYNC3、INSTALL5が通過。実Hookをbackup付きで更新、bundleハッシュ一致とautoexec.cfg全体不変を確認。実ミッションSync/Check成功、対象DynamicTraining.lua以外の全ZIP entryとCAP Zone4件が不変。起動表示をinitialization pendingへ変更。scores.datは導入時点で未作成。I/O失敗の具体的原因とMAN-50/51、実プレイヤーの精算保存・再起動復元は引き続き実DCSで確認する。

同日18:52 JSTの再現でLoad通過後のBOOTSTRAP write判定失敗を確認。一時fileはDCS終了後も34 bytes残り、codec検証に通るrun1/revision0/空accountsだった。書込み結果とnative I/Oの返り値を分離し、void-return・flush欠落でもclose後再読とschema一致を必須とするadapterへ修正。rename/removeも実結果を検証する。Lua全309ケース（PERSIST41）、BUILD2、SYNC3、INSTALL5が通過。最終Hookを実Saved Gamesへbackup付きで導入、bundleハッシュ一致とautoexec.cfg不変、Sync/Check成功を確認。実DCSでの書込み/保存確認・復元は未確認。対象版のmethodごとの返り値形状はIO_COMPATIBILITYログで確認する。

同日19:10 JST、DCS 2.9.30.28718（Windows MT）、ユーザーのマルチプレイホスト実行で初回接続・空成績の保存・確認通知・正常終了が通過した。write/flush/closeは成功時返り値nilであることを実ログで確認。MissionLoadEnd→BOOTSTRAP_COMMITTED run1→CONNECTED、Ramat slot StatisticsのPersistent scores saved.、StopのFinal snapshot and acknowledgement confirmed.を確認。終了後scores.datのcodec検証成功、34 bytes、run1/revision0/accounts0、Hookとbundleのハッシュ一致。MAN-50の初期保存・MAN-51の正常終了部分を確認したが、slot未選択の条件、実ポイント精算保存、既存累計の再起動復元は未確認なので手動ケース全体を完了とはしない。実成績を検証用に変更していない。
2026-10-06の保存未接続診断追加後はLua全295ケース、BUILD2、SYNC3、INSTALL5確認グループが通過。通常の保存・採点・復元処理を変えず、登録/frame/非ホスト/endpoint待ちを区別するログを追加した。実ミッションのSync/Checkも成功し、ユーザー追加のCAP Zone4件を保持した。17:45 JSTの実DCSログではHook読込済み・Player Statistics未接続を確認したが、診断Hookでの再現と根本原因の確定は未実施。
DCS内のSEAD状態遷移・DEAD継続・サイト管理・採点の各手動ケースは個別結果の記録待ち。
過去の「ゲーム内で動いている」という報告は、未記録の手動ケースすべての合格とは扱わない。

CAP-trial-1追加後はLua全342ケース（INT16、CAP30、SCORE26、WING27、PAR16、SEAD62、DEAD103、PERSIST44、MAP18）、BUILD2、SYNC3、INSTALL5確認グループが通過した。Intercept/SEAD/DEAD等の既存ゲームプレイテスト本体は変更せず、共通harnessへCAPのZone/Orbit/alias模擬を追加した。実Syria.mizの4円形CAP Zone（各18,288m）と既存Intercept template3種のLate Activation・実機数を静的確認。Build・実ミッションSync・Check成功、同期直前との比較で埋め込みDynamicTraining.lua以外の全ZIP entry不変。schema2の最終Hookを実Saved Gamesへbackup付きで更新しbundleハッシュ一致を確認、autoexec.cfgと既存scores.datのハッシュは不変。旧schema→新schemaの移行・CAP90保存・次run復元・未知schema保護は専用fixtureで確認した。DCS再起動後のCAP AI・F10・実ポイント保存復元（MAN-52〜55）は未確認。

2026-10-06 20:17〜20:56 JST、CAP-trial-1、DCS 2.9.30.28718（Windows MT）、ユーザーのマルチプレイホスト、標準設定で2回のCAP実行をログ検証した。run2:CAP:1（Beirut）はGolan/Su-27×1、進入20:30:19→24/48/72/96/120秒の通知、65秒で生成、時間達成後の敵全滅20:33:12、UnitLost20:33:25で90点。run2:CAP:2（空母）はGolan/MiG-29A×2、進入20:53:29→同じ通知、74秒で生成、120秒後も敵残存、1機撃破後のUnitLost20:56:23で0点。両任務の敵交戦・任務ロック終了と、revision1/2保存・Stop最終確認を記録。終了後schema2/run2/revision2の保存fileをcodecで読取検証し、Total/Career/CAP各90、任務2、Primary成功1、帰還失敗1、未達成失敗1、Death2が一致した。証跡はbuild/cap-live-20261006.log（元dcs.logのUTC表記をJSTへ換算）。任務関連Luaエラーなし。MAN-52/53/55の一部条件のみ確認済みであり、退出停止/再開・敵全滅先行・帰還150・MP2/並行・次セッションの90点復元は未実施。全ケースPASSとは扱わない。

同日のCAP表示整理後は、CAP-01/03/25で受注/Statusの `CAP AREA: <DDM>`、Radius/PATROL CENTER行の非表示、進入時 `CAP on station.` のみを検証した。Lua全342ケース、BUILD2、SYNC3が通過し、実Syria.mizのSync/Checkも成功。時計・敵生成・達成・採点条件は変更していない。整理後の実DCS表示はMAN-52で確認待ち。

2026-10-06 21:15〜21:16 JST、DCS更新後の2.9.30.28738（Windows MT）、同PCでのホスト実行を確認した。21:15:44のrun3/source=primary接続・保存確認と21:16:47のStop最終確認が成功。終了後primary schema2/run3/revision0とbackup run2/revision2を読取codec検証し、Total/Career/CAP各90、既存統計を保持していた。Hookと生成bundleのhash一致、autoexec.cfgの既知hash一致。更新後の接続失敗ログはない。MAN-51/55の次セッションへの累計引継ぎ部分を確認したが、Statistics画面・更新後の新規精算・帰還150・得点付き旧schema移行は未実施。証跡はbuild/persistence-update-20261006.log。実成績への直接書込みや実装修正は行っていない。

F10の受注メニューは2026-10-07から `Task: Intercept / CAP / SEAD / DEAD` とする。模擬操作のコマンド名と対応表も同じ表記を使い、ケース数・達成条件・採点の期待値は維持する。DCS内ではMAN-02/05/27/52でメニュー名と受注、エラー時の再受注案内を確認する。
名称変更後はLua全342ケース（9スイート）、BUILD2、SYNC3、INSTALL5確認グループが通過した。実ミッション `mission/Persistent_and_Dynamic_FA-18C_Training.miz` へのBuild/Sync/Checkも成功。直前backupとの比較でDynamicTraining.lua以外の全ZIP entryが不変、埋め込みLua内の4メニューがTask表記であることを確認した。MEの既存ブリーフィングに旧メニュー名の記載はなかった。受注・敵生成・帰還・採点条件は維持している。変更後の実DCSメニュー表示は確認待ち。

### 2026-10-07 Statistics表示整理

2026-10-07、この表示変更でLua全342ケース、BUILD2、SYNC3が通過。現在の実ミッション `mission/Persistent_and_Dynamic_FA-18C_Training.miz` を `-MissionPath` で指定してSync/Check成功。既定の `mission/Syria.miz` は存在しないため既定パスでのSync/Checkは失敗した。新表示のDCS内確認（MAN-01）は未実施。

### 2026-10-07 全体整備（training-2）

Notifications/手動Reportをruntimeから分離し、空中目標のSnapshot/loss/生存観測を共通化した。Interceptのnil・例外・不正IsAlive・別IDを撃墜完了としない回帰ケースINT-17/18を追加。SEAD-62は生成待ちStatusのSpawn in非表示も確認し、SCORE-01で任務なしStatus/AbortのIdle一覧を揃えた。

Intercept報酬は`intercept.fullReward`へ移動し150を維持。Sync既定先を現在のミッション名へ合わせ、結合順と変数名は単一の順序付き対応表へ整理。Test-AllからLua全9スイート344ケース、BUILD2、SYNC3、INSTALL5が通過。標準引数で実ミッションSync/Check成功、同期はDynamicTraining.luaの置換だけでその他のZIP entry保持を検証した。テストで実Saved GamesのHook・設定・成績は変更していない。

ARCHITECTUREに責務・識別子・状態・命名を明記し、TESTING/PERSISTENCEの診断履歴は本書へ移動。DCS内の整備後確認は未実施。特にMAN-01/02/05/07/08/27/52でF10・Status・各任務の一巡を確認する。既存Hookの再導入は今回の変更に不要。

### 2026-10-07 Intercept削除再試行・入口改名（training-3）

実行入口のソースを`src/DynamicTraining.lua`から`src/main.lua`へ改名。Buildがmain.luaを最後に結合し、bundle/登録済み埋め込みはDynamicTraining.luaのまま。MEのトリガー・リソース登録は変更していない。

Interceptの終了時と生成後設定失敗時の敵をpendingCleanupで保持し、失敗時は初期5秒ごとに再試行。Destroyのfalse・例外、実体残存・確認不能を成功とせず、消失確認後に参照を解放する。最初の失敗と回復時だけログ、終了時のエラー画面は15秒1回。削除待ちの間も精算済み任務のロックは解放し、新しい任務を継続できる。

INT-19〜22で例外2回・5秒境界・設定失敗・nil無処理・false・検索例外／不正値・帰還150／事故90／未達成0・新任務／別Wing・遅れた死亡イベントを検証。Lua全348ケース（INT22）、BUILD2、SYNC3、INSTALL5が通過し、実ミッションSync/Check成功。DCS内の削除再試行確認は未実施。

### 2026-10-07 専用サーバーCAP死亡未精算の調査（未解決）

ユーザー提供の`C:/Users/hayat/Desktop/dcs.log`を確認。DCS_server.exe、DCS 2.9.30.28738（Windows MT）、Saved GamesのDCS.dcs_serverreleaseプロファイルで実行したサーバーログ。実行ミッションは`Missions/Persistent_and_Dynamic_FA-18C_Training.miz`。訓練bundleの版・ローカル編集元との一致はこのログだけでは確認できない。時刻はログのUTCからJSTへ換算。

Ramat SOLOの登録1人。run2:Intercept:1は21:14:42に主要目標達成、21:15:10にUnitLostをRTB_FAILUREとして90点精算し、revision1を保存した。run2:CAP:2は21:16:51受注、North Coast/MiG-29A×2/出現累計97秒。21:45:46進入、21:47:23敵生成、21:47:46に累計120秒を達成したが敵は残存。

21:50:29のejectと21:50:40のcrashは同じ機体object ID 16783362でDCSログへ記録された。21:50:53 Statisticsは精算済み任務数1・Death Count1のまま、21:51:23 StatusはCAP ACTIVE、敵残数2、登録者ACTIVE。21:52:54の個人Abortで初めてCAP0点を精算し任務を閉じ、revision2を保存した。MAN-53の未達成事故での自動精算はFAIL。MAN-52の進入・進捗・敵生成は部分確認。

任務の死亡イベント受信前に止まったのか、受注時機体との照合で一致しなかったのかは既存ログから区別できない。DCS内部のScripting event記録を、MOOSEの任務callbackへ配信済みという証拠にはしない。任務関連のLua例外は当該時間帯に見当たらず、Abort後の保存は成功している。サーバー実行版の埋め込みLuaを照合し、必要なら受信イベント・受注時機体IDの診断を追加して再現する。原因は未確定、現段階では動作ロジックを変更しない。

### 2026-10-07 受信者の寿命修正（training-4）

ユーザーからサーバーで実行した.mizはローカル／レポジトリと同じとの確認を受け、配布版の違いを調査の前提から除いた。同梱MOOSEの`EVENT:Init`は受信者を弱キーにし、`EVENT:OnEventGeneric`はcallbackだけを保存する。main.luaのBASE受信オブジェクトはローカル変数にしか保持されず、エントリ処理終了後にGCされるコード不具合を特定した。これはタイマーによるCAP時計・Statusが動き続ける一方、途中から死亡精算を受け取らなくなる実ログの挙動を説明する。

CAP-31に同じ弱キー登録で配送する模擬境界と実際の`collectgarbage`を追加。修正前はIntercept→再搭乗→CAPのGC後に受信者が消えてテスト失敗。`DynamicTrainingRuntime.eventHandler`でミッション終了まで強参照を保持する修正後は、受信者1つ・重複読み込み・未達成脱出0点／ロック解放・重複Crash・次CAPのGC後の敵全滅／帰還150が通過した。既存の直接callback配送だけではこの寿命の違いを検出できていなかった。

初期化時に`Runtime initialized; version=training-4; MOOSE event subscriber retained.`をログへ1回出し、配布版を判別できるようにした。DCS標準の追加受信経路や、機体名を使う緩い照合は導入せず、MOOSE配送・既存ID照合・一度だけの精算を維持する。

Lua全349ケース（CAP31）、BUILD2、SYNC3、INSTALL5が通過。実ミッションのSync/Check成功。サーバー側は更新した.mizを差し替えてミッション再開始が必要。Hook更新は不要。修正版の専用サーバーでのMAN-53確認は未実施、過去にAbortで保存された成績を直接修正していない。

### 2026-10-07 死亡イベント診断ログ（training-5）

サーバーログでイベント未受信・機体照合不一致・精算失敗を分けるため、受注時に固定したWing/機体名/object ID、死亡系MOOSE callbackの受信と受信者保持状態、登録参加者への一致と精算前state/doneをDEBUGへ記録する。Crash / Dead / PilotDead / Ejection / UnitLostだけが受信トレース対象。照合後の精算・任務解放・保存確認は既存ログで追う。画面の本文・表示時間・採点条件は維持し、UCIDは出力しない。

破壊後のraw getID/getName失敗は保護しUNAVAILABLEと記録する。元の実体参照・固定IDによる照合を緩めず、同名別IDは受信ログだけで精算しない。CAP-31を拡張してこれらの診断、UCID秘匿、初期化版ログ1回、GC後の失敗／成功精算を確認。Lua全349ケース、BUILD2、SYNC3、INSTALL5と実ミッションSync/Checkが通過。実サーバーでの診断出力確認は未実施、サーバーには更新版.mizを差し替えてミッション再開始が必要。

## 成績保存の診断履歴

2026-10-06 17:45 JSTの実DCSログで、BLUE_HORNET_SC_AI2_01のPlayer Statisticsが `Session only; persistence hook not connected.` であることを確認した。Hookの読み込み、同梱bundleとの一致、ホストAPI許可は確認済みだが、scores.datは未作成で接続ログもない。実行中endpointの所在／callbackの呼び出しを区別できるログが旧Hookになかったため、診断ログを追加する。診断Hook導入後のDCS確認と根本原因の確定は未実施。
診断HookはinstallerでSaved Games/DCSへ旧Hookのbackup付きで導入し、生成bundleとのハッシュ一致を確認した。autoexec.cfgと他Hookは変更していない。読み込みにはDCS本体の再起動が必要。

同日17:55 JSTの再現では `MISSION_LOAD_BEGIN` と `FIRST_SIMULATION_FRAME` を確認し、callbackが実行されていることを確認した。`WAITING_ENDPOINT: server protocol=nil; endpoint=nil; trigger=table; timer=table; coalition=table; a_do_script=nil` が記録され、接続先serverで任務の公開globalが見えないことが判明した。Player Statisticsは引き続き未接続。これは保存fileへのI/O以前の問題。
ユーザー承認後、mission manager経由の接続を実ソースへ適用した。テストもHook/manager/実SSEを分離し、serverと実SSEを同一環境とする旧fixtureの誤りを修正した。
Lua全296ケース、BUILD2、SYNC3、INSTALL5確認グループが通過。installerの `-ConfigureHost` で実Saved GamesのHookとautoexec.cfgをbackup付きで更新した。Hookハッシュ一致、管理ブロック以外の設定不変、userhooks/mission許可追加・server許可維持を確認済み。実ミッションのSync/Checkも成功し、CAP Zone4件を保持した。導入直後のscores.datは未作成であり、DCS再起動後の接続確認待ち。

同日18:11 JSTの再現ではmission bridgeがAPI status=trueでも不正返信となった。ミッション側SetErrorは反映され、Player Statisticsは `Persistence unavailable; scores not confirmed saved.`、scores.datは未作成。呼び出しの実行と戻り値の伝搬を同じものとしていた模擬fixtureが実DCSを再現できていなかった。
managerが副作用だけを実行して返信を落とすfixtureへ修正し、許可済みmissionの範囲でscriptingへ直接接続する実装へ変更した。manager dispatcher欠落時も接続できることと、返信を落とす旧経路を使わず90ポイントを保存・確認することを検証する。修正後の実DCS接続・保存・再起動復元は確認待ち。
Lua全297ケース、BUILD2、SYNC3、INSTALL5が通過。最終Hookを実Saved Gamesへbackup付きで配置しbundleとのハッシュ一致を確認。autoexec.cfgは既存の許可をそのまま使用し全体が不変、実ミッションSync/Check成功、CAP Zone4件保持を確認済み。導入時点でscores.datは未作成。

同日18:21 JSTの再現では `transport=scripting`、`replyType=nil; replyBytes=0; status=nil` を確認し、scores.datは未作成。同梱APIのscripting説明を実SSE接続に当てはめた修正は実環境で成立せず撤回した。呼び出しが実行されていたmission経路に戻し、上記の末尾scalar・第1/第2位置照合を適用する。fixtureは単純な全返信欠落ではなく、報告された先頭nil・末尾値欠落と正常dispatcherの両方を模擬する。全返信欠落の場合は依然として保存せず、復旧後の再接続を検証する。修正後の実DCS接続・保存・再起動復元は確認待ち。
Lua全298ケース、BUILD2、SYNC3、INSTALL5が通過。修正版Hookを実Saved Gamesへbackup付きで配置しbundleとのハッシュ一致、autoexec.cfg全体不変、実ミッションSync/Check成功、CAP Zone4件保持を確認済み。導入時点でscores.datは未作成。ユーザーは今回Player Statisticsを操作しておらず、起動直後のSession only表示を見ていた。接続より先に出る初期表示だけで成否を判断せず、後続のHook接続ログ・通信エラー・ファイルで確認する。Player Statisticsの操作自体は接続条件ではない。

18:30 JSTの再現を含め全体を見直し、上記4責務へ分離した。Lua全306ケース（PERSIST38）、BUILD2、SYNC3、INSTALL5が通過。実Hookをbackup付きで更新しbundleハッシュ一致、autoexec.cfg不変を確認。実ミッションSync/Check成功、対象Lua以外の全ZIP entryとCAP Zone4件保持を確認済み。scores.datは導入時点で未作成。実DCSでの新adapterによる初回保存・成績精算・再起動復元は未確認であり、旧ログだけからI/O差異の具体的原因を確定しない。

18:52 JSTの再現ではLoadを通過し、BOOTSTRAPのwrite/flush/close判定で停止した。Beirut slotのPlayer Statisticsは保存未確認。DCS終了後のscores.dat.tmpは34 bytesで、codec検証に通るrun1/revision0/空accountsの正常な初期snapshotだった。書込みが全面的に拒否されているわけではなく、native methodの返り値判定と実際のfile生成を区別する必要がある。ただしどのmethodが返り値を省略したかは旧ログでは不明。
同梱MOOSEのRANGE:_SaveTargetSheetもfile:write/file:closeの返り値を必須にしていないことを確認。上記adapterは呼出し成功と保存成功を分離し、void-return/flush欠落を再読・移動結果の検証で扱う。模擬ケースではその条件で保存・復元が通り、欠落bytes・例外・false・移動未実行は成功としない。実DCSでの保存確認は修正版導入後に行う。
Lua全309ケース（PERSIST41）、BUILD2、SYNC3、INSTALL5が通過。最終Hookを実Saved Gamesへbackup付きで導入しbundleハッシュ一致とautoexec.cfg不変を確認。Sync/Checkも成功。導入時点でscores.datは未作成で、既存の正常な初期一時fileはテストで編集していない。新adapterによる実DCS保存・復元は確認待ち。

2026-10-06 19:10 JST、DCS 2.9.30.28718（Windows MT）でユーザーのマルチプレイホスト実行により初期接続・初回保存・確認通知・正常終了を確認した。ログはIO_COMPATIBILITYでwrite/flush/closeそれぞれの成功時返り値がnilであることを示し、BOOTSTRAP_COMMITTED run=1 source=new、storage and acknowledgement confirmed、CONNECTEDへ進んだ。Ramat slotのPlayer StatisticsもPersistent scores saved.。StopではFinal snapshot and acknowledgement confirmed.、保存エラーなし。
DCS終了後のscores.datは34 bytes、codec検証成功、counter/session=1、revision=0、accounts=0。ここまで確認できたのは空の成績の初期保存とrun採番であり、実ポイントの保存や再起動後の復元ではない。実プレイヤーの150/90/0精算→保存確認→ミッション再開始/DCS再起動の検証は引き続き必要。確認のために実成績を直接書き換えていない。

同日20:17〜20:56 JST、CAP対応schema2 Hookでrun2/source=primaryの接続を確認。CAP:1の達成後UnitLostで90点を精算し、SNAPSHOT_COMMITTED revision1。CAP:2の未達成UnitLostで0点を精算しrevision2、Stopで最終snapshotと確認成功。終了後scores.datを読取検証し、schema2/run2/revision2、Total/Career/CAP各90、任務2・Primary成功1・帰還失敗1・未達成失敗1・Death2を確認。実ポイント保存は確認済み。今回のrun開始時の旧成績は空だったため、得点を持つ旧schema移行・次セッションでの90点復元・帰還150点保存はまだ実DCSで未確認。保存fileの直接編集は行っていない。

同日21:15〜21:16 JST、ユーザーからDCS更新後の保存障害の疑いが報告されたため、このPCの最新ログと保存fileを確認した。DCSは2.9.30.28718から2.9.30.28738へ更新済み。21:15:44にBOOTSTRAP_COMMITTED run3/source=primary、storage and acknowledgement confirmed、CONNECTED、21:16:47にStopの最終snapshot/確認成功を記録。Hookは生成bundleと同一hash、autoexec.cfgも既知のhashと一致。終了後primaryはschema2/run3/revision0、backupはschema2/run2/revision2で、両方codec検証に通りTotal/Career/CAP各90と既存統計を保持していた。更新後の初期接続・新runへの累計引継ぎ・正常終了は確認済み。このログではStatistics操作や新規精算がなく、更新後の新ポイント保存と画面表示は未確認。保存fileやHookへの修正は行っていない。

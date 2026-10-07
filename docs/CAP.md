# CAP 訓練任務

更新日: 2026-10-07

## 今回の仕様

F10のTask: CAPで、受注時のBLUE F/A-18C人間参加者を固定する。同じWing/UCIDの受注ロック、個別中止・帰還評価を既存任務と共有する。
現在MEにあるCAP_ZONE_CENTRAL_COAST / CAP_ZONE_GOLAN / CAP_ZONE_NORTH_COAST / CAP_ZONE_HOMS_WESTの4円形trigger zoneを等確率で選ぶ。名前はConfig.capで管理し、中心座標・半径はruntimeのMOOSE ZONEから取得する。MEのzone・template・view設定をLuaから変更しない。
受注直後に `CAP AREA: <中心DDM>`（分の小数3桁）と達成条件を60秒設定で1回表示する。空域名・半径・PATROL CENTER行は表示しない。Mission Statusも同じ形式で再確認できる。

## 状態と時間

受注からACTIVEとし、全員離陸待ちやInterceptの20秒待ちは使わない。登録者のうち未精算・操作中・空中の誰かがzone内なら滞在時計を進める。地上・AI・空席・途中参加者・別Wingはカウント対象外。
最初の進入でカウントを開始し、累計120秒を保持する。全対象者がzone外/観測不能なら停止し、再進入で再開する。時計はDCSミッション時刻、位置確認は共通1秒poll。前後の確認が両方zone内の区間だけを加算し、長い観測欠落は最大2秒までしか加算しない。境界通過の実測誤差はpoll間隔程度。
進入通知は `CAP on station.` のみ。`Patrol clock started.` は表示しない。
累計24/48/72/96/120秒に20/40/60/80/100%をグループへ各1回通知する。100%は滞在時間達成を示し、敵全滅までPrimary達成にはしない。
達成は「累計120秒」と「今回生成した敵機の全滅」の両方。敵を先に全滅させても滞在時間を続ける。120秒を先に達成した場合は敵全滅を待つ。120秒達成後の撃墜はzone外でも評価し、滞在進捗を取り消さない。

## 敵機

受注時にzone内累計時間30〜120秒から整数秒を等確率で抽選し、固定する。出現時計もzone外では停止する。到達時に1編隊だけ生成し、再進入・再度の100%到達で再生成しない。120秒抽選では生成を行ってから達成条件を評価する。
Config.intercept.templatesの登録済み3候補を暫定使用し、各1/3で選ぶ。Interceptの60〜80NM生成条件や開始処理は呼び出さない。敵はzone外周から15〜25NM離れたランダム方位に生成し、空域中心へ進入・哨戒する。高度15,000〜30,000ftと速度230m/sは初期値。Fighters/Multirole fightersだけを交戦対象にし、BLUE AWACSを訓練目標にしない。
生成Group名はDT_CAP_<assignmentID>のaliasで分離する。実機の識別子と生死を追跡し、IsAliveのnil/例外を全滅根拠にしない。CAPの敵撃墜だけではInterceptや他Wingの達成を動かさない。
生成/経路設定の失敗は任務を0点で解除する。生成済み敵は全参加者終了/中止時に削除する。削除失敗はCAP内で参照を保持し再試行する。

## 採点・保存

両条件達成でRTB_PENDINGへ移る。既存のBLUE基地/対応空母、5knots以下10秒の帰還評価を使う。満額150、達成後事故90、未達成事故/任意中止0。共有任務でも各自満額とし、先に失敗・中止した人へ遡及加算しない。
CAP Scoreを独立し、Total/Careerと統計へ加算する。保存schemaはCAP欄を持つversion2へ拡張し、version1の既存成績はCAP=0として読み込む。他カテゴリの累計は保持する。missionとHookのcodecを同時に更新し、Hook再導入とDCS再起動が必要。実Saved Gamesの成績をテストで書き換えない。

## 検証結果と制約

2026-10-07、DCS 2.9.30.28738の専用サーバー、Ramat SOLOのCAPで脱出・墜落後もACTIVEと任務ロックが残り、個人Abortまで精算されない不具合をログで確認した。MOOSEが弱参照で保存する受信者を保持していないコード不具合をGCの模擬テストで再現し、training-4では`DynamicTrainingRuntime.eventHandler`でミッション終了まで保持する。CAP-31でIntercept→同スロット再搭乗→CAP→GC→脱出の未達成0点・ロック解放・重複精算防止を検証する。修正版の実DCS再確認（MAN-53）は未実施。詳細は [HISTORY.md](HISTORY.md#2026-10-07-受信者の寿命修正training-4) を参照する。

抽選・DDM/半径・カウント停止/再開・通知境界・30/120秒生成・二重生成拒否・達成順序・MP2・別Wing・早期事故・帰還/事故報酬・敵の観測不能・Cleanup再試行をscripts/Test-CAP.luaの31ケースで模擬検証済み。旧schema移行とCAP精算保存・次セッション復元、未知schemaの保護はscripts/Test-Persistence.luaのPERSIST-42〜44で検証済み。現ミッション（旧Syria.miz）の候補4 Zoneが存在し、各半径18,288m（約9.9NM）、円形type0であることを静的確認済み。手動確認は [TESTING.md](TESTING.md) のMAN-52〜55を使う。
敵機の識別・生存観測はInterceptと共通の`air_targets.lua`、Status本文は`mission_report.lua`に置く。生成・滞在時間・目標条件はCAPが所有する。全体の責務は [ARCHITECTURE.md](ARCHITECTURE.md) を参照する。
2026-10-06 20:17〜20:56 JST、DCS 2.9.30.28718（Windows MT）のユーザーホストで2任務を実行。両方Golan、半径9.9NM、同じDDM中心を通知。Beirut出発のrun2:CAP:1は20:30:19から24秒ごとに20%通知、65秒でSu-27×1（25,789ft）生成、120秒で時間達成、20:33:12に敵全滅達成、20:33:25のUnitLostで90点。空母出発のrun2:CAP:2は20:53:29から同じ進捗、74秒でMiG-29A×2（20,367ft）生成、120秒で時間達成、敵1機撃破後20:56:23のUnitLostで未達成0点。生成敵とプレイヤー間のミサイル発射/命中をログで確認。任務関連Luaエラーなし。
終了後のschema2 scores.datを読取検証し、run2/revision2、Total/Career/CAP各90、任務2・Primary成功1・帰還失敗1・未達成失敗1・Death2を確認。今回のログでMAN-52の進入/進捗/出現とMAN-53の時間先行/達成後事故/未達成事故を部分確認した。退出停止/再開、全空域、敵の哨戒形状、敵全滅先行、帰還150、MP2/並行、次セッションの90点復元は未確認。
今回の120秒は初期訓練値。難易度、複数wave、CAP専用template、CAP Drawing、時間切れ、敵の帰投は未実装。

# 検証・診断履歴

現在のテスト件数・実行方法は [TESTING.md](TESTING.md)、保存方式・診断方法は [PERSISTENCE.md](PERSISTENCE.md) を参照する。以下は当時の版・設定・観測結果の記録であり、途中段階の未実装・未確認・診断仮説を現在の仕様として扱わない。過去の証跡と旧ファイル名はそのまま残す。

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

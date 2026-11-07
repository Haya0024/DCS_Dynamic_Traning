# CAS AUTOLASE（training-18.1）

## 運用

CAS受注で既存ME配置の敵3両・味方3両・JTAC1両を生成する。受注後のJTACは待機し、F10 `Dynamic Training → CAS JTAC → Request laser` で照射を依頼する。依頼中は今回固定した生存RED車両だけを対象に、見通し・距離が成立する1両へ照射する。`Stop laser` で停止し、再依頼まで待機する。コードは受注時の1688 / 1687 / 1686を維持する。標準JTACとの無線チェックイン・9-lineは使わない。照射開始と失視等を短い画面通知で伝え、通常のAssignment通知と同じくログへ記録する。

MGRS味方位置・敵の特徴・待機/コード/依頼案内・目標・報酬・人数の7行ブリーフィングと同じMission Status、全3両破壊の共有達成、各自のRTB150 / 達成後事故90 / 未達成事故・Abort0は維持する。照射通知はStatusの保存本文を置き換えず、現在残数や車両別精密座標を追加しない。SRS・煙幕・独立したAutolaseメニューは追加しない。

## 責務とMOOSEとの境界

- src/jtac.lua: 原本FACの検証・コピーからの除去、コード枠予約、公開連絡表示、従来の配置診断。
- src/cas_autolase.lua: CAS専用AUTOLASEアダプター。対象の固定ID照合、単一照射、観測不能時の停止、通知、照射物と監視の寿命を所有する。
- src/cas.lua: ME実体の生成・準備検証、採点対象の生死、地域と全生成物の回収。照射の成否を任務達成・解除の条件にしない。
- MOOSE AUTOLASE: 実Constructorと設定API、距離・LOSのCanLase、固定したRecceのコードを使用する。
- MOOSE SPOT: 実LaseOnと追従処理を使用する。標準の発射側相対高さ2 m・目標位置+1 mを使う。MOOSE本体は編集しない。

AUTOLASE既定のINTEL全周検索・自律Monitor・広域メニュー・通知は使わない。CASは既に対象を固定しており、周辺の別任務へ担当を広げないためである。Constructor直後に専用CallSchedulerの初期予約を解除し、以後の選定は既存ミッションの監視から駆動する。標準CleanCurrentLasingのnilを死亡扱いする分岐も使用せず、既存Observationsの固定ID・三値観測を適用する。この接続方式は、同梱MOOSEの実Constructor / CanLase / SPOT関数を使う回帰検査で固定する。

## 状態と対象選定

1. 全実体の準備検証後はSTANDBY。任務がACTIVEでも依頼前に照射を作らない。Request laserでrequested=trueとし、即座に1回選定、その後は既存ACTIVE監視から駆動する。
2. 対象はplan.targetsの元IDとRED groundを照合する。生存・有限の座標を確認できない実体は照射しない。未知は撃破とみなさない。
3. LASING中は同じ対象を維持する。新たな高脅威を理由に飛翔中の誘導先を変更しない。
4. 対象喪失・観測不能・LOS/距離不成立・照射時間切れでは照射を停止する。次の選定では照射可能な固定対象の脅威度を優先し、同値は数値ID順にする。
5. 照射可能対象なしはWAITING。JTAC喪失でも任務を継続し、自機センサー・自機照射で達成できる。
6. Stop laserでrequested=falseに戻し、追従を無効化して照射を回収する。STANDBYでも回収失敗を再試行するが、照射対象を選ばない。再依頼は同じ地域・対象・コードを使い、任務を再生成しない。
7. PRIMARY達成、Abort、準備失敗、全員終了では永久停止のSTOPPED。新規照射と古いcallbackを拒否する。

操作メニューはACTIVEの登録済み・未精算・現在操縦中の参加者がいるグループだけへ表示する。別グループのMission Team参加者も自分のグループから操作できる。DCSのF10はグループ共有のため、押した個人の識別はできない。操作時にも任務参照・Group ID・固定参加者の機体/UCIDを再照合し、途中参加者だけが残ったグループ、別スロット、個人中止後、準備中、達成後、旧任務のcallbackを拒否する。Request/Stopの連打は状態を変えず通知を増やさない。依頼の世代番号をSPOTへ固定し、停止前の追従callbackは再依頼後も無効とする。

既定は最大距離3 NM、選定監視1秒、同一対象の照射時間300秒、短文通知10秒。距離はプレイヤー受注距離3～13 NMとは別のJTAC→目標距離。MOOSE SPOTの追従更新前にも所有権・元ID・生存・座標・距離・LOS・期限を検査する。

## 終了と障害

SPOTの作成前に所有ハンドルを保持する。IRだけ作成後にLaser作成が失敗する等の部分失敗でも両方を回収できる。停止ではまず更新を無効化し、SPOTのCallScheduler / LaseSchedulerとイベント購読を解除してから、保持しているnative IR/Laserを個別に破棄する。nilを返す正常destroyを許可し、例外・falseでは参照を保持する。回収失敗中は新たな照射を作らない。

任務終了時は照射の回収も地域・コード枠の解放条件に加え、既存Sweepで再試行する。観測/API/生成障害は当該CASだけで封じ込め、照射を止めて再観測する。ログと通知は状態が変わったときだけ出す。照射側の撃破通知を採点へ流さない。

## ME原本と検証範囲

ME原本の位置・向き・車種・経路は保存する。旧FAC_EngageGroupは原本に残したまま、動的コピーから除去し、標準FACとAUTOLASEの同時照射を防ぐ。変更するZIP entryは登録済み埋め込みLuaだけ。

自動検証では固定3両の範囲、単一照射・コード、対象維持と切替、未知/例外/ID変更、途中失敗、停止後のcallback、部分生成・削除失敗と再試行、共有精算を確認する。実際のレーザー表示・ApacheのLST・K型誘導・長時間サーバー運用はDCS内確認待ち。現在の地域01でBMP-2×2の地形レイがfalseだった履歴を維持し、導入で地形遮蔽が解決したとは扱わない。

## 実DCSのnative spot検査（2026-11-07）

DCS 2.9.31.29434 / Syriaで、14:37～14:38 JSTに隔離プロファイルの検査を実行した。実際の敵・味方・JTACを3コードで順次生成し、各コードで8秒間の監視後にnative Spot:getPointを読み取り、静止目標位置+1 mとの差0.000 mを確認。各回のCAS.Close後に回収・コード枠解放を確認し、COMPLETE spots=3 cleanup=3まで完了した。Group削除直後は消失未確認となったが、5秒後の既存再試行で3回とも解放された。検査DCSだけを終了した。

同じ実行でも2 m診断ではBMP-2×2がfalseだったが、2.5 mのCanLaseを通過したBMP-2先頭車へ実spotが作成された。端点高さで結果が変わる境界的な配置である。native spotの保持座標を確認した検査であり、ビーム経路・Apache映像・移動標的への実追従・誘導弾命中を証明していない。通常Config・Hook・成績は使わず、検査入口は通常main.luaの初期化を呼ばない。

再現用はscripts/Build-CASAutolaseCheckMission.ps1、scripts/CAS-AutolaseCheck.lua、scripts/Start-CASAutolaseCheck.ps1。最初のスクリプトがbuild内のコピーへ登録済みLuaだけをSync/Checkし、開始スクリプトが新規DCS.CASAutolaseCheck-*プロファイルを作る。起動中DCSがあれば拒否する。-Statusはログ確認、-Stopは記録した専用プロファイル・実行ファイルに一致するDCSだけを終了する。抜粋ログはbuild/CAS_Autolase_Check_20261107.log。更新ZIPはscripts/Package-CASUpdate.ps1で、検証記録のミッション/結合Luaハッシュ一致を確認してから作成・内容検証する。

training-18.1では同じ検査入口へ受注後2秒の待機、Request、Stop後2秒の待機、再Requestを追加する。新しい検査の結果は別ログへ記録し、training-18の確認を新バージョンの証明へ流用しない。

training-18.1の新規隔離実DCS検査は2026-11-07 16:46～16:47 JSTに完了。3コードすべてでSTANDBY_OK、PAUSE_OK、再依頼8秒後のSPOT_OK（目標位置+1 m、誤差0.000 m）、CLEANUP_OKを確認し、COMPLETE standby=3 pause=3 spots=3 cleanup=3となった。F10メニュー操作の実搭乗試験は含まない。検査DCSだけを終了し、ログはbuild/CAS_Autolase_Check_training18_1_20261107.logへ保存した。

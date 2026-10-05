# テスト仕様書

更新日: 2026-10-05

## 目的と対象

訓練任務の受注・生成・目標達成・帰還評価・採点・終了処理が仕様通りに動作し、別プレイヤーや別ウィングへ影響しないことを確認する。
対象は現在実装されているIntercept、SEAD、Immediate/Follow-on DEAD、ウィング共有、UCID採点、Lua結合、`.miz`同期。
動的Clientスロット、保持Siteのtimeout・明示削除・Site永続化は今回の検証対象外。成績の永続保存は対象とする。

動作の根拠は [Intercept.md](Intercept.md)、[SEAD.md](SEAD.md)、[DEAD.md](DEAD.md)、[WING.md](WING.md)、[SCORING.md](SCORING.md)。
本書はテスト条件と期待結果を記録し、実装済みの自動テストとDCS内で行う手動確認を区別する。

## テストの構成

| 区分 | 実行ファイル | 現在の件数 | 主な対象 |
|---|---|---:|---|
| INT | [Test-Intercept.lua](../scripts/Test-Intercept.lua) | 16 | 離陸待ち、生成位置、編隊、機種、全滅判定、通知重複防止 |
| SCORE | [Test-Scoring.lua](../scripts/Test-Scoring.lua) | 26 | UCID、帰還、事故、重複防止、累計 |
| WING | [Test-Wing.lua](../scripts/Test-Wing.lua) | 27 | MP2、参加者固定、共有目標、個別精算、排他 |
| PAR | [Test-ParallelWings.lua](../scripts/Test-ParallelWings.lua) | 16 | 複数ウィングの並行処理と独立性 |
| SEAD | [Test-SEAD.lua](../scripts/Test-SEAD.lua) | 62 | 受注計画、配置、TOO/PB、状態遷移、サイト管理、表示重複防止 |
| DEAD | [Test-DEAD.lua](../scripts/Test-DEAD.lua) | 86 | Primary/Site分離、Group継承、保持・予約・rollback、残存対象、nil観測・DDM、採点、ログアウトCleanup、未達成DEADからのSEAD帰還 |
| PERSIST | [Test-Persistence.lua](../scripts/Test-Persistence.lua) | 25 | schema、保存確認、再起動・遅延復元、I/O失敗、backup、run、死亡統計、別Lua環境・文字列通信 |
| SYNC | [Test-MissionSync.ps1](../scripts/Test-MissionSync.ps1) | 3確認グループ | ZIP保持、拒否時の無変更、ME相当の保存後の再同期 |
| BUILD | [Test-MissionBuild.ps1](../scripts/Test-MissionBuild.ps1) | 2確認グループ | 結合の再現性、モジュール保存後の再結合・同期 |
| INSTALL | [Test-PersistenceInstall.ps1](../scripts/Test-PersistenceInstall.ps1) | 5確認グループ | Hook導入・backup・拒否、実ファイル保存、別Luaプロセスで復元・破損復旧、ホスト設定保存・許可追加・不正設定拒否 |

Luaは合計258ケース（既存233＋PERSIST25）。1ケースの中で複数の値・方位・イベント・機種をループ検証するため、assertや試行の総数ではない。Test-PersistenceDisk.luaはINSTALLが3つの別プロセスで実行する専用fixtureであり、25ケースには含めない。
PowerShellは複数のassertをまとめたPASSグループで、Luaのケース数とは別に数える。
共通の [Intercept-TestHarness.lua](../scripts/Intercept-TestHarness.lua) は模擬環境であり、独立したテストスイートではない。

### 自動テストの前提と限界

Luaテストは `build/DynamicTraining.lua` を読み込み、本番の結合済みコードに対して操作・時刻・イベントを入力する。
DCS/MOOSEのユニット、グループ、座標、地形、障害物、F10、接続情報、Life、Radar、ログを模擬する。
採点台帳の単体確認では `src/config.lua` と `src/scoring.lua` も直接読み込む。

時刻は `s:tick(time)`、イベントは `s:event(...)`、抽選結果は `s.randomValues` で指定する。
60秒・10秒の確認は模擬ミッション時刻であり、実時間を待つテストではない。
抽選テストは選択範囲と各候補への分岐を検証する。大量試行による確率分布の統計検定は行わない。

MOOSE本体や実際のSyria地形・SAM AI・DCSのイベント配信・サーバーのUCID取得は模擬環境では検証できない。
実際の `.miz` のテンプレートやZone設定はLuaテストのfixtureと別なので、ME変更後は手動確認も必要。
自動テスト通過をゲーム内確認済みとは記録しない。

## 実行方法と合否

すべてリポジトリのルートから実行する。Lua 5.1互換の実行環境とWindows PowerShellを使用する。
最初に結合を行い、古い `build/DynamicTraining.lua` をテストしない。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-Mission.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build-PersistenceHook.ps1
```

`lua` がPATHにある場合は以下を実行する。

```text
lua scripts/Test-Intercept.lua
lua scripts/Test-Scoring.lua
lua scripts/Test-Wing.lua
lua scripts/Test-ParallelWings.lua
lua scripts/Test-SEAD.lua
lua scripts/Test-DEAD.lua
lua scripts/Test-Persistence.lua
```

DCS付属の `luae.exe` を使う場合のPowerShell実行例。インストール先が違う場合は `$luaPath` を変更する。

```powershell
$luaPath = 'C:/Program Files (x86)/Steam/steamapps/common/DCSWorld/bin/luae.exe'
$suites = @(
    'scripts/Test-Intercept.lua',
    'scripts/Test-Scoring.lua',
    'scripts/Test-Wing.lua',
    'scripts/Test-ParallelWings.lua',
    'scripts/Test-SEAD.lua',
    'scripts/Test-DEAD.lua',
    'scripts/Test-Persistence.lua'
)
foreach ($suite in $suites) {
    Get-Content -Encoding UTF8 -LiteralPath $suite | & $luaPath -
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $suite" }
}
```

ビルド・同期ツールは次の2本を順に実行する。どちらも一時ディレクトリの使い捨てミッションを使用する。
SYNCは編集元から実プロジェクトのbundleを再生成することがあるが、実際の `mission/Syria.miz` は変更しない。
BUILDはソースも一時プロジェクトへコピーして検証する。Watcherはテスト内で起動・停止し、一時ファイルを終了時に削除する。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-MissionBuild.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-MissionSync.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-PersistenceInstall.ps1
```

Luaはすべてのケースが `PASS:` となり、最後に `All N ... tests passed` が出て終了コード0なら合格。
最初のassert失敗で停止するので、その後のケースは未実行。
PowerShellは全PASSグループを出力し、例外なく終了コード0なら合格。
異常系で意図的に発生させる例外・ログも検証対象で、表示にERRORがあるかだけで合否を決めない。

Luaを変更した場合の反映確認は、自動テスト後に次を順に行う。
`-Check` は実 `.miz` の埋め込みLuaとの一致確認であり、ゲーム内動作のテストではない。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -Check
```

ドキュメントだけの変更では `.miz` の書き換えは不要。

## 自動テストケース

以下の番号は、各Luaファイルの現在の `test(...)` 掲載順に対応する。
例えば `SEAD-45` は `Test-SEAD.lua` の45番目のケース。PASS表示はソース内の英語のテスト名を使用する。
テストを追加・並べ替えた場合は、件数と対応表も更新する。
表の条件は各ケースの主要な入力、期待結果は確認すべき振る舞いを要約したもの。

### Intercept（INT）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| INT-01 | 地上受注、離陸、待機中の移動・機首変更、重複受注 | 全員の離陸検出後20秒で、その時点の位置・機首を使って1回だけ生成 |
| INT-02 | 20秒待機中に着地、再離陸 | 離陸待ちへ戻り、20秒を最初から数える |
| INT-03 | 生成前に死亡・退出・機体交換・操縦者変更 | 予約を解除し、後から敵を生成しない |
| INT-04 | プレイヤー列挙順変更、AI僚機だけの離陸 | 元の参加者を維持し、AIで開始条件を満たさない |
| INT-05 | 空中受注、達成後の再受注 | 空中なら即生成、帰還待ち中は二重受注を拒否 |
| INT-06 | Spawn・編隊設定・経路設定が失敗 | 生成済み敵を片付け、予約解除と再受注が可能 |
| INT-07 | 無人グループ、2人搭乗したMP2 | 無人では予約せず、MP2は1ウィングとして登録 |
| INT-08 | 方位0/45/90/180/270/359°、偏角−60/0/60°、距離60/70/80 NM | 距離・左右範囲・HOT機首・プレイヤー後方20 NMへの経路が一致 |
| INT-09 | 5種類の編隊をそれぞれ選ぶ、重複受注 | Openの編隊指定をControllerと経路へ適用し、既存生成を変更しない |
| INT-10 | 別ウィングで異なる編隊を選ぶ | 各生成Groupの編隊が独立 |
| INT-11 | 3テンプレートをそれぞれ選ぶ | ME由来の機種・機数を維持し、開始表示も一致 |
| INT-12 | 1機編成を死亡イベントまたはpollingで全滅 | 目標達成後、既存の帰還・事故採点へ移る |
| INT-13 | 2機編成の1機だけを破壊 | 残り1機が生存する間は未達成 |
| INT-14 | 選ばれたテンプレートが見つからない | 予約解除後に別の受注を開始可能 |
| INT-15 | 再受注と複数ウィングの受注 | 任務ごとにテンプレートを選び、他任務の抽選・敵に影響しない |
| INT-16 | 単独・MP2の地上／空中受注、両者の連打、離陸イベント、カウントダウンリセット、定期監視 | 受注は離陸待ちだけ、20秒待ち通知はカウント開始ごとに1回、詳細開始表示は1回のみ。敵も1回だけ生成、開始15秒・Status20秒を維持 |

### 採点・帰還（SCORE）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| SCORE-01 | 達成後BLUE飛行場へ着陸、停止10秒の前後 | 10秒未満は0、条件を連続10秒満たすと150 |
| SCORE-02 | 達成後のCrash/Dead/PilotDead/Ejection/UnitLost、同じ事故の重複通知 | 各事故で90を一度だけ加算 |
| SCORE-03 | 達成前の事故、Cleanupによる敵死亡イベント | 0のまま終了し、削除イベントで後から成功しない |
| SCORE-04 | 着陸確認中の事故、帰還確定後の事故 | 確認中は90、確定後は150を維持 |
| SCORE-05 | ボルター・復行・離陸 | 停止時間をリセットし、新しい着地を要求 |
| SCORE-06 | バウンドして空中へ、停止確認中の速度超過 | 連続停止時間をリセット |
| SCORE-07 | Land/RunwayTouchの重複通知 | 確認時間を不用意に再開始せず、二重加算しない |
| SCORE-08 | 移動中のBLUE空母へ着艦 | 艦との相対速度で停止判定 |
| SCORE-09 | RED・中立・FARP・不明地点・未対応艦へ着陸 | 満額を付与しない |
| SCORE-10 | 停止確認中に飛行場外へ移動、BLUE所有権喪失 | 帰還確認を解除 |
| SCORE-11 | AI僚機や他プレイヤーの着陸・事故 | 元の参加者の出撃を精算しない |
| SCORE-12 | 他プレイヤーが列挙順の先頭、メニューから受注 | 操作したグループの参加者へ任務・報酬を紐付ける |
| SCORE-13 | 同じ表示名、異なるスロットとUCID | 成績を混同しない |
| SCORE-14 | 同じUCIDで名前・スロットを変更 | セッション内累計を維持 |
| SCORE-15 | 実行時ユニットIDと静的ネットワークスロットIDが異なる | 静的スロットを照合してUCID取得 |
| SCORE-16 | 受注後に別の機体へ再スポーン | 元出撃の満額帰還として扱わない |
| SCORE-17 | 切断後、元の操縦者が元の機体へ戻る | 不在中の停止時間を加算せず、復帰後に確認可能 |
| SCORE-18 | UCIDなし、曖昧な照合、net API失敗 | 採点なしで訓練を継続し、架空の識別子を作らない |
| SCORE-19 | 名前は一致するがスロットが不一致 | 名前だけでは成績を紐付けない |
| SCORE-20 | 採点なしで開始し、途中からUCID取得可能 | 開始時に未採点の出撃へ遡って加算しない |
| SCORE-21 | 他人の中止操作、本人の任意中止 | 本人の出撃だけ中止可能、任意中止は0、Cleanupで成功しない |
| SCORE-22 | 最後の敵破壊→参加者死亡と、その逆順 | 達成が先なら90、死亡が先なら0 |
| SCORE-23 | 参加者喪失後にpollingで敵全滅を確認 | 遡ってクリア報酬を付与しない |
| SCORE-24 | 2回目の任務、旧機体の遅延イベント | 累計を加算し、旧イベントで新任務を精算しない |
| SCORE-25 | 結合済みスクリプトを再読み込み | タイマー・購読を二重登録せず、成績をリセットしない |
| SCORE-26 | 台帳への重複・矛盾した精算、満額の60%が小数になる設定 | 最初の精算を維持し、付与ポイントは切り捨て整数 |

### ウィング共有（WING）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| WING-01 | MP2の全員離陸、両者のメニューから受注 | 全員離陸後20秒、任務は1つだけ |
| WING-02 | 20秒待機中にどちらかが着地 | ウィング全体のカウントをリセット |
| WING-03 | ユニット・プレイヤー列挙順を逆にする | 機体番号を基準に長機を決める |
| WING-04 | 別基地へ別時刻に帰還 | 各自150、1人目の精算後も受注ロックを維持 |
| WING-05 | 2人の帰還確認が同じtickで完了 | 両者を一度ずつ精算し、記録を欠落させない |
| WING-06 | 1人が帰還、もう1人が達成後に事故 | 150と90を個別に加算 |
| WING-07 | 2人とも達成後に事故 | 各自90、2人目の終了でウィングを解除 |
| WING-08 | 達成前に長機が死亡、僚機が継続・達成・帰還 | 長機0、僚機150 |
| WING-09 | 達成前に全員喪失 | 全員0、Cleanupの敵死亡で達成しない |
| WING-10 | 1人だけ個人中止 | 相手の任務と受注ロックを維持 |
| WING-11 | 自分の精算後に全体中止 | 確定したポイントを維持し、未精算者だけ中止 |
| WING-12 | 生成前に1人だけ個人中止 | その人を離陸待ちの対象から外す |
| WING-13 | 先に精算した参加者が別ウィングへ移動 | 元ウィング全体の終了までUCIDの受注ロックを維持 |
| WING-14 | 参加者が別ウィングから元の出撃を個人中止 | 自分の元出撃だけ中止可能 |
| WING-15 | 空席へ途中参加、その人が事故 | 今回の参加者・報酬に追加せず、共有目標を消さない |
| WING-16 | 受注時の搭乗者を全員入れ替える | 元ウィングの任務が残る間は再受注不可 |
| WING-17 | 僚機が別機体へ再スポーンして帰還 | 元の参加者の出撃を満額精算しない |
| WING-18 | 僚機のUCID未照合、長機は照合済み | 僚機は採点なし、長機は満額を取得可能 |
| WING-19 | 生成前に登録参加者を喪失 | 予約全体を解除し、ロック解放 |
| WING-20 | 別ウィング同時受注、各自の重複受注 | 並行開始可能、各ウィングの2件目は拒否 |
| WING-21 | 2スロットに同一UCID | ロック取得前に拒否 |
| WING-22 | 2UCIDと採点なし2機を台帳で処理 | 精算記録が別々になり、混同しない |
| WING-23 | 同じ2人で2回連続の協同任務 | 各自の累計を独立して加算 |
| WING-24 | 予約取消直後に再受注 | 個人中止のcallbackを新任務用に再構成 |
| WING-25 | 古い個人中止callbackを新任務中に実行 | 新しい任務を中止しない |
| WING-26 | 目標達成より前の喪失イベントが遅れて到着 | その参加者は失敗・0、成功件数にも加算しない |
| WING-27 | 同じ表示名の2人で任務 | UCIDと機体で独立して採点・個人中止 |

### 複数ウィング（PAR）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| PAR-01 | Aは離陸待ち、Bは空中受注 | Bだけ即開始し、Aの予約を維持 |
| PAR-02 | 2つのMP2が地上受注、別時刻に全員離陸 | 独立した20秒カウント |
| PAR-03 | Aだけが待機中に着地 | Aだけカウントをリセット |
| PAR-04 | 自ウィング・他ウィングの敵破壊、相互支援 | 対象Groupを持つ任務だけ達成 |
| PAR-05 | Aが帰還・精算、Bは戦闘中 | Bの任務・敵を維持 |
| PAR-06 | 2ウィング4人が同tickで帰還確定 | 4人を独立精算 |
| PAR-07 | Aが中止、削除イベントが発生 | Bを中止・達成させない |
| PAR-08 | Aの参加者が事故 | Bの参加者を精算しない |
| PAR-09 | Aの経路設定が失敗、再受注 | Aだけ解除、新しい生成別名を使用 |
| PAR-10 | Aの地上予約を取消、Bは戦闘中 | Bの受注ロックを維持 |
| PAR-11 | 未受注ウィングのStatus・Abort操作 | 他人の任務を表示・中止しない |
| PAR-12 | 参加者のUCIDが別ウィングへ移動 | 新規受注を拒否し、その人の元出撃を参照 |
| PAR-13 | 複数の元出撃を持つ参加者が同じグループへ集合 | 個人中止は特定可能、全体中止で任意の旧任務を選ばない |
| PAR-14 | 自ウィングにも任務があり、旧任務を持つ人が参加 | 全体中止は現在の自ウィングだけに適用 |
| PAR-15 | 古い個人中止callback | 新任務・並行任務のいずれにも影響しない |
| PAR-16 | Aの監視処理に例外、Bは帰還確認中 | Bの監視・精算を継続 |

### SEAD：配置・排他（SEAD-01〜17）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| SEAD-01 | SA-6/SA-8を空中受注、計画確定、生成、中止 | 計画後に地上生成、ME相対配置を維持、戦闘・停止設定、中止で削除 |
| SEAD-02 | 乾燥・平坦な全配置範囲と、不適合な候補 | LAND・平坦条件を満たす候補だけ採用し、不合格は再抽選 |
| SEAD-03 | 内部・外周・車両位置の高低差20 mと超過 | 20 mは許可、20 m超は拒否 |
| SEAD-04 | 建物・scenery・static・unitを各車両付近へ置く | bounding boxの外接半径を含め離隔を判定 |
| SEAD-05 | 境界情報なしの障害物、離隔ちょうど200 m | 情報なしは半径50 m扱い、設定の最低離隔ちょうどなら許可 |
| SEAD-06 | 選択Zoneで50回失敗、tickごとの検査 | 1tick最大2候補、上限で解除、別Zoneに切り替えない |
| SEAD-07 | 選択Zoneが不適合、他Zoneは適合 | 50回で失敗し、他Zoneへ逃げない |
| SEAD-08 | Zoneの一部または全部が存在しない | 不在Zoneを候補から除外、全不在なら失敗解除後に再受注可能 |
| SEAD-09 | テンプレート・地形API・検索API・Spawnの失敗 | ロック解除、生成済みGroupの復旧削除 |
| SEAD-10 | 選定中・戦闘中に同ウィングが別カテゴリを受注 | Intercept/SEADで相互に二重受注拒否 |
| SEAD-11 | 地点選定中に中止・登録機喪失 | 遅延SAM生成なし |
| SEAD-12 | MP2の地点選定中に1人だけ中止 | 残る参加者の計画を継続 |
| SEAD-13 | 別ウィングがSEADとInterceptを受注 | カテゴリが異なっても並行実行可能 |
| SEAD-14 | 2SEADの候補位置が重なる | 使用中サイトを避け、Group別名も異なる |
| SEAD-15 | SA-6発射機だけ破壊、レーダーは稼働 | 未達成 |
| SEAD-16 | 先頭車両をroute起点からずらしたテンプレート | route起点を基準に全車両の相対配置を維持 |
| SEAD-17 | 利用可能Zoneから抽選 | 1Zoneを選び、設定のZone一覧を書き換えない |

### SEAD：破壊・採点・対象識別（SEAD-18〜30）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| SEAD-18 | SA-6レーダーだけ破壊、発射機は生存 | DESTROYEDで帰還待ち、SAMと受注ロックは精算まで維持 |
| SEAD-19 | SA-8へDead/Crash/UnitLost、wrapperはまだ生存表示 | イベントの対象一致で即DESTROYED |
| SEAD-20 | レーダー喪失イベントなし、または停止のみ・損傷のみ | pollingで破壊を検出、停止単独・損傷単独では成功しない |
| SEAD-21 | 達成後の各事故と重複通知、達成前の事故、中止 | 90を1回、達成前・任意中止は0 |
| SEAD-22 | 帰還停止10秒前後、帰還確定後の事故・再破壊イベント | 10秒で150、確定後のポイントを維持 |
| SEAD-23 | レーダー破壊と参加者喪失の順序を反転 | 破壊が先なら90、喪失が先なら0、pollingで遡らない |
| SEAD-24 | MP2で共有達成、1人帰還・1人事故 | 各自150/90を独立精算 |
| SEAD-25 | 達成前に1人事故、残る参加者が達成・帰還 | 先の事故0、残る人150 |
| SEAD-26 | 同一UCIDがSEADとInterceptを順に完了 | Total/Careerは累積、カテゴリ別Scoreを分離 |
| SEAD-27 | 他ウィングや前回任務のレーダーイベント | 今回の対象以外で達成しない |
| SEAD-28 | 車両順序変更、主要レーダーを複数含む | TypeNameで識別し、全主要対象の達成を要求 |
| SEAD-29 | 主要レーダーなし・追跡不能なテンプレート | 生成失敗解除、修正後に再受注可能 |
| SEAD-30 | UCID取得不可の参加者が達成・帰還 | 採点なしを維持 |

### SEAD：受注計画・情報・離陸（SEAD-31〜44）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| SEAD-31 | 両方式・両テンプレートを指定して受注 | 等幅抽選、方式・SAM・コードを保存。SA-6=108、SA-8=117 |
| SEAD-32 | TOOで受注・計画確定・開始・Mission Status | 固定のDDM捜索座標（分の小数3桁）を計画確定とStatusで表示し、機種・正確なDDM位置・PBコードは隠す |
| SEAD-33 | TOO/PBの誤差距離・方位の境界、DMS APIを使用不可にする | 実配置との水平距離がTOO 3〜5 NM、PB 1〜3 NM。計画確定・Statusの座標は同じDDM形式、分の小数3桁 |
| SEAD-34 | 地上受注、計画確定、移動、離陸、生成 | 地点・方式・テンプレート・Zone・IDを維持し、生成時に再抽選しない |
| SEAD-35 | MP2の全員離陸、待機中の着地 | 全登録者を待ち、着地で20秒をリセット |
| SEAD-36 | 離陸後の待機中に個人中止 | 残る参加者の固定計画を維持 |
| SEAD-37 | 予約中の喪失・操縦者変更・途中参加 | 予約取消条件を守り、未登録者で離陸条件を迂回しない |
| SEAD-38 | 受注時の長機とZone中心の距離40/130 NMと範囲外 | 境界を含む40〜130 NMだけ候補 |
| SEAD-39 | 機体列挙順や受注メニュー操作機が長機と異なる | 機体番号で決めた長機位置を使用 |
| SEAD-40 | 範囲内Zoneなし、選択Zone消失 | 固定したZoneを変更せず安全に解除 |
| SEAD-41 | 生成前に予定点が障害物などで不適合になる | 同地点を再検査し、移動・再抽選・生成せず解除 |
| SEAD-42 | 地上の別ウィングが同時に配置計画 | 未生成の予約点同士も離隔を確保 |
| SEAD-43 | 旧上限30回より後で適合点が出る | 現上限50回内なら計画成功 |
| SEAD-44 | 配置失敗を異なる理由で発生させる | 拒否件数・観測した高低差を表示し、TOOの秘匿情報は漏らさない |

### SEAD：状態遷移・Cleanup・表示（SEAD-45〜62）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| SEAD-45 | 両方式・両SAMで生存、開始時Life100→99、Radar OFF | OFF観測開始後59秒では未達成、60秒でSUPPRESSED。帰還150、完了後の再発信でも結果固定 |
| SEAD-46 | 無傷/開始時以上のLifeでOFF、または大損傷・追尾対象nilでON | 計測も達成もしない。追尾対象nilをOFFと誤認しない |
| SEAD-47 | 無傷で長時間OFFの後に損傷 | 無傷の時間を除外し、損傷＋OFFの観測開始から60秒 |
| SEAD-48 | 計測開始後59秒付近でON、再びOFF | ACTIVEへ戻りタイマー破棄。新しいOFFから60秒必要 |
| SEAD-49 | IsAlive/Life/Radarのnil・不正値・NaN・無限大・API例外 | lost・DESTROYEDにせず継続時間を破棄、正常観測の再開後に60秒を数え直す。IsAlive不明時のSite残数も不明 |
| SEAD-50 | 生成時Life50、後で60→49→48 | 基準50を固定。60は損傷扱いにせず、49で開始、48への追加損傷でリセットしない |
| SEAD-51 | 計測中にLifeが開始値へ戻り、再度減少 | 計測を解除し、再度の損傷＋OFFから開始 |
| SEAD-52 | SUPPRESSION_PENDING中に破壊、Life/Radar APIも失敗 | タイマーを待たずDESTROYED、達成後事故90 |
| SEAD-53 | 開始時Lifeが0・負値・文字列・無限大 | 基準を捏造せず生成失敗。Groupを削除して再受注可能 |
| SEAD-54 | 複数主要対象で個別損傷・OFF・再発信・破壊 | 個別タイマーで全対象を要求。一部だけ60秒でも確定せず、再発信を再評価 |
| SEAD-55 | 別ウィングが異なる時刻から計測 | 自ウィングの時間・結果だけ進む |
| SEAD-56 | MP2がSUPPRESSED、再発信、1人帰還・1人脱出、重複死亡 | 共有達成後は結果固定、150/90を一度ずつ加算 |
| SEAD-57 | 60秒確定前に参加者喪失、Cleanupの死亡イベント | 0、後からSUPPRESSED/DESTROYEDで報酬を得ない |
| SEAD-58 | ACTIVE→PENDING→ONでACTIVE→再計測→SUPPRESSED | Statusの4状態・経過時間が一致、完了後Life/Radar呼出しを停止 |
| SEAD-59 | ACTIVEまたはPENDINGからDESTROYED、残存車両破壊、精算 | 完了表示・終端状態が固定、追加報酬なし。精算まで保持し、Cleanup後も保持したsite参照の結果は不変 |
| SEAD-60 | MP2片方だけ精算、全員終了後の削除が2回失敗、新任務受注 | 全員終了まで削除なし。ロックは解放し、site参照を保持して再試行、新任務へ干渉せず3回目で削除 |
| SEAD-61 | 別ウィングと並行中に自任務を中止 | 自サイトだけ削除し、未達成を成功へ変えず、他サイトを維持 |
| SEAD-62 | TOO/PBを地上・空中で受注、複数tickの計画、離陸待ち・カウントダウンリセット、生成、Status再確認、表示時間60／90秒を設定 | 座標付きブリーフィングは計画確定時に自動1回だけ。受注は方式＋計画中、生成は座標・コードなし。Statusでは同じDDM座標を何度でも確認でき、設定した表示時間を両方へ適用 |

### DEAD follow-on（DEAD）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| DEAD-01 | SA-6損傷＋OFF60秒 | Site SUPPRESSED、CLEANUP標準、元assignmentで予約、Continue/Preserveを表示 |
| DEAD-02 | SA-8死亡イベント、wrapperは生存表示 | Site DESTROYED、follow-onなし、SEAD精算後Cleanup |
| DEAD-03 | 生存SA-8をSuppressしてContinue | 1両をDEAD対象、帰還でSEAD150＋DEAD150 |
| DEAD-04 | 通常SEAD、選択なしでRTB | SEAD150、従来通りSite削除 |
| DEAD-05 | Preserveのcallbackを複数回実行、RTB | 時刻・状態不変、同じ損傷GroupをRETAIN、元任務終了で予約解除 |
| DEAD-06 | 未完了SEADや未PreserveのSiteに別WingからGenerate DEAD | 候補にならず、元SEADを変更しない |
| DEAD-07 | MP2でPreserve後、片方だけ精算、別Wingが取得 | 元全員終了まで取得不可、終了後に取得可能 |
| DEAD-08 | 即DEADへ継続、Spawn/乱数APIを拒否するfixture | 同record・ID・Group・計画・Life・Radarを維持、再Acquire・再Spawn・再抽選なし |
| DEAD-09 | SEADでレーダーと1発射機を破壊後Continue | 生存2両だけsnapshot、全対象破壊でRTBへ、SEAD150＋DEAD150 |
| DEAD-10 | Immediateの全対象をイベントなしで喪失 | pollingでDEAD達成、SEAD結果を固定、SiteはCLEANUP |
| DEAD-11 | Immediate途中に5種の事故、重複通知 | SEAD90を一度だけ付与、IN_USEをCleanup、DEAD Scoreは0 |
| DEAD-12 | Immediate途中の任意Abort | SEAD0＋DEAD0を精算、Site削除 |
| DEAD-13 | Preserve後にContinue、DEAD完了・RTB | RETAIN→IN_USE→CLEANUP、保持を解除して削除 |
| DEAD-14 | 候補なしでGenerate DEAD、その後Intercept受注 | 定型通知で拒否、新規Site・Spawn・抽選なし、Wing/UCIDロックを残さない |
| DEAD-15 | 保持後Follow-on DEAD受注、Spawn APIを拒否 | 元Group・計画・損傷を継承、新ID・category DEADで予約 |
| DEAD-16 | Follow-on DEADの開始表示とStatus、DMS APIを使用不可にする、表示時間を90秒へ変更 | SITE LOCATIONに実配置点のDDM・分の小数3桁を表示、地域・種類・残数あり、内部Group/object ID・Estimated表現なし。共通設定を開始・Statusへ適用 |
| DEAD-17 | 地上MP2受注、1対象喪失、全員離陸 | 受注時snapshot維持、ARMEDで予約済み、全員離陸で即ACTIVE、20秒待ちなし。座標付き予約通知・開始表示は初期60秒 |
| DEAD-18 | 地上予約中に全対象喪失、後で離陸 | ARMED中は未達成、ACTIVEへ移ってから達成 |
| DEAD-19 | Follow-on DEAD全対象破壊・RTB | DEAD150、元SEAD150、Total/Career300、独立した2精算、Cleanup |
| DEAD-20 | Follow-on DEAD達成後の5種事故と重複通知 | DEAD90を一度だけ付与 |
| DEAD-21 | Follow-on DEAD達成前の5種事故・Abort | DEAD0、Site Cleanup |
| DEAD-22 | 地上Follow-on DEADをAbort、元機体を交換 | 予約・任務を終了し0、Site Cleanup |
| DEAD-23 | 複数RETAIN Site、受注操作機と長機の位置が異なる | 機体番号で決めた長機に最も近いSiteを取得 |
| DEAD-24 | actualSpawnPointなし、Siteまで同距離 | spawn.coordinateへfallback、Site IDで決定 |
| DEAD-25 | 1Siteを別Wingが地上待機中に二重受注 | 2件目を拒否し、最初の予約を維持 |
| DEAD-26 | 同Wingで3カテゴリの再受注、重複UCID | 既存の1Wing1任務・UCID排他を維持 |
| DEAD-27 | Missions.Acquireが拒否 | 保持Siteを消費せず、後の正常取得が可能 |
| DEAD-28 | Site予約後のsnapshot取得が例外 | Wing/UCIDとSite予約をrollbackし、RETAINへ戻す |
| DEAD-29 | 予約後のbriefing例外、配点不正 | Groupを削除せずrollback、修正後に取得可能 |
| DEAD-30 | Group内にBLUE・非ground車両を含むfixture | 生存RED groundだけを対象snapshotにする |
| DEAD-31 | DEAD開始後に車両を追加、対象外車両の死亡通知 | 固定対象を増減せず、対象外イベントで成功しない |
| DEAD-32 | 対象の生存・ID観測が例外、不正値・nil、ID不一致 | 全滅を推測せず未達成を維持、nilとID不一致をlostにしない |
| DEAD-33 | 保持Siteを外部攻撃で全滅、イベントなし | Sweepで候補除外・Cleanup、再Spawnなし |
| DEAD-34 | 保持Siteの観測が不明、後でAPI回復 | 一時的に候補除外、Siteは削除せず正常時に取得可能 |
| DEAD-35 | SEAD達成後、選択前に残存車両が全滅 | 一時メニューを除去、古いContinueを拒否 |
| DEAD-36 | 旧SEADのContinue/Preserveを新Intercept中に実行 | 閉じたSiteや新任務を変更しない |
| DEAD-37 | 別Wing・登録者入替後のContinue操作 | 元Wingの登録参加者だけが選択可能 |
| DEAD-38 | MP2の1人精算後、未精算者がImmediateへ継続 | 精算者を再登録・再採点せず、未精算者だけ進行 |
| DEAD-39 | Follow-on DEAD MP2で達成後、1人RTB・1人事故 | DEAD150/90を個別精算、全員終了までSite予約維持 |
| DEAD-40 | DEAD後のCleanupが2回失敗 | ロック解除済み、参照を保持してSweep再試行、3回目成功、追加精算なし |
| DEAD-41 | 最後のDEAD対象破壊と参加者死亡を逆順にする | 達成先ならDEAD90、死亡先なら0、pollingで遡らない |
| DEAD-42 | Follow-on DEAD達成後、移動中の空母へ着艦 | 既存の相対速度・停止10秒判定でDEAD150 |
| DEAD-43 | UCID未照合でFollow-on DEAD完了・帰還 | 採点なし、任務とCleanupは完了 |
| DEAD-44 | Follow-on DEAD受注後に途中参加者が事故 | snapshot参加者を増やさず、元任務に影響しない |
| DEAD-45 | 着陸確認中にContinue、DEAD未達成で再着陸 | 旧着陸確認を解除、新しい着地の10秒確認でSEAD150／DEAD0、Cleanup |
| DEAD-46 | 2WingのFollow-on DEADを並行実行、片方を中止 | 対象・Group・削除・採点を混同せず、他方は継続 |
| DEAD-47 | DEAD参加者と同UCIDが別Wingから受注 | UCIDロックで3カテゴリの二重受注を防ぐ |
| DEAD-48 | MP2 Follow-on DEADの達成前に長機事故、僚機が達成・帰還 | 長機のDEAD0を維持、僚機DEAD150 |
| DEAD-49 | 配点175で地上受注、待機中に設定を150へ戻す | 受注時満額175を固定して精算 |
| DEAD-50 | Preserve後のSEAD任意Abort、別DEADを完了 | SEAD0、RETAINを維持、Follow-on DEAD150 |
| DEAD-51 | 受注準備中に参加者の離陸状態APIで例外 | Wing/UCID/Site予約をrollbackし、RETAIN Groupを削除しない |
| DEAD-52 | 受注時の座標表示後は座標APIで例外、空中・地上受注 | 保存したbriefingを開始時にも使用し、ACTIVEへ正常移行 |
| DEAD-53 | SEAD精算後、保持者がログアウト・再接続 | 保持Site削除、SEAD150維持、再接続でSiteを復元しない |
| DEAD-54 | 同UCIDの観戦・別side/slot・改名・接続ID変更、同名別UCID | 接続中は保持、本人のUCID消失で削除、名前で誤照合しない |
| DEAD-55 | MP2僚機メニューからPreserve、長機精算後に再選択、個別切断 | 最初の長機を保持者に固定、僚機切断では保持、長機切断で削除 |
| DEAD-56 | 元長機事故後、生存僚機がPreserve | 現在の登録長機を保持者とし、その人のログアウトで削除 |
| DEAD-57 | Preserve後、元SEAD精算前にログアウト | Site予約だけ解除して削除、SEAD Primary/帰還評価/受注ロック維持 |
| DEAD-58 | Immediate/別WingのFollow-on DEAD使用中に元保持者切断 | IN_USE Siteを削除せず、使用中の任務を維持 |
| DEAD-59 | 接続API例外・欠落・不正/sparse一覧・情報不明・識別子なし | 切断と誤認せず保持、接続確認の正常化後はCleanup可能 |
| DEAD-60 | UCIDなしのserverエントリ、切断CleanupのDestroyが2回失敗、再接続 | serverを除外して切断確認、3回目削除成功、保持へ戻さず採点維持 |
| DEAD-61 | 2人の保持Site、一方切断直後に他方がGenerate DEAD | 定期Sweep前でも切断Siteを除外、その保持者のSiteだけ削除 |
| DEAD-62 | UCID未照合だが接続player IDは取得済み、観戦・切断 | 観戦では保持、接続IDが一覧から消えたらCleanup |
| DEAD-63 | SA-6レーダー破壊＋生存Launcher1/3両、Immediate/Follow-onを実施 | Primary DESTROYEDとSite SUPPRESSEDを分離、1/3両だけ対象、再Spawnなし、全滅後もSEAD結果維持 |
| DEAD-64 | SA-6 Suppression後、両DEAD経路でLauncherだけ破壊→レーダー破壊 | 生存4両を対象、レーダーが残る間は未達成、全滅でDEAD達成、SEAD SUPPRESSED履歴維持 |
| DEAD-65 | SA-6/SA-8全車両の死亡通知、wrapperはまだ生存表示 | 実残存0としてSite DESTROYED、継続メニューなし、保持候補なし |
| DEAD-66 | 未達成SEADの生存4両、損傷＋OFF59秒→60秒 | 完了前の継続不可、60秒達成で残存4両の継続を解放 |
| DEAD-67 | Immediate両目標達成後の5種事故と重複通知 | SEAD90＋DEAD90を一度ずつ、任務・Primary・Recovery統計は各1、Cleanup |
| DEAD-68 | Continue時DEAD報酬175/0、後で50に変更、古いcallback再実行 | 採点ID・満額固定、元record維持、帰還合計325/150、任務1 |
| DEAD-69 | MP2 Immediate達成後、1人RTB・1人脱出・重複死亡 | 各自300/180、全員終了までSite予約維持、各任務1 |
| DEAD-70 | Immediate途中に長機事故、僚機がDEAD達成・RTB | 長機SEAD90／DEAD0固定、僚機300、遡及DEAD達成なし |
| DEAD-71 | Immediate最後の対象破壊と参加者死亡を逆順にする | 対象破壊先なら180、参加者喪失先なら90、pollingで遡らない |
| DEAD-72 | DEAD達成後に、達成前の時刻を持つ事故イベントが届く | SEAD90／DEAD0、SEAD達成時刻とDEAD達成時刻を分離 |
| DEAD-73 | UCID未照合でImmediate両目標達成・RTB | 両精算は非採点・0、仮アカウントを作らずCleanup |
| DEAD-74 | Immediate両目標達成後に任意Abort | SEAD0＋DEAD0、任務1、両精算結果ABORT、Cleanup |
| DEAD-75 | Continue時の満額が負数/無限/NaN/小数/文字列 | 移行前に拒否、元SEADのRTB・150・Cleanupを維持、DEAD採点なし |
| DEAD-76 | 追加DEADの満額101を60%精算、競合結果で再精算、追加Abort | 60へ切り捨て、一度だけ累計更新、元任務統計を増やさない |
| DEAD-77 | 保持Siteの全残存車両のIsAliveがnil、受注を試みた後trueへ回復 | Site状態・Groupを保持、残数不明・観測不能・DEAD候補除外、ログ1回。正常化後に同Siteを取得・精算可能 |
| DEAD-78 | 両DEAD経路の最後の対象がnilを3tick、trueへ回復、falseで喪失 | 未達成・lost=falseを維持、Site残数不明、DEAD観測不能ログ1回。trueで不明解除、falseで達成・帰還300 |
| DEAD-79 | 両DEAD経路の対象がnil、各対象の死亡イベントが届く | 明示的死亡を優先、全対象lostで達成。nilのwrapperを再観測して完了を妨げず、帰還300・Cleanup |
| DEAD-80 | 保持GroupのGetUnitsがnil/空、正常化、false確認済みで再度nil/空 | 一覧欠落だけで全滅・削除しない。回復時は候補復帰、既知対象すべてfalse確認済みの場合は全滅・Cleanup |
| DEAD-81 | Immediate DEAD未達成でBLUE基地／移動空母へ帰還、着陸・事故重複通知 | 9秒では未精算、10秒でSEAD150／DEAD0を一度だけ付与。残敵CleanupでDEAD達成を誤認せず、任務・RTB各1 |
| DEAD-82 | MP2 Immediate途中に長機だけ帰還、僚機が後で全対象破壊・RTB | 長機150固定、僚機300。僚機終了まで同record・Site予約・受注ロック維持、遡及採点なし |
| DEAD-83 | Immediate未達成で着陸確認後Takeoff／RunwayTakeoff／空中polling | 確認解除後はDEAD_ACTIVEへ戻る。再着陸・安全帰還でSEAD150／DEAD0 |
| DEAD-84 | Immediate未達成の着陸確認9秒時にCrash、重複Dead | SEAD90／DEAD0を一度だけ付与、Recovery Failure1、Site Cleanup |
| DEAD-85 | Immediate着陸確認中にDEAD達成、そのまま停止／復行して再着陸 | タイマー維持、解除時の戻り先はRTB_PENDING、帰還成功はSEAD150＋DEAD150 |
| DEAD-86 | Follow-on DEAD未達成でRED／BLUE基地へ帰還 | 達成前の帰還評価は開始しない。目標達成後の新しい着地からDEAD150を精算 |

### 成績永続化（PERSIST）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| PERSIST-01 | 日本語・引用符を含む名前、改ざん・切断・Luaコード・不正数値 | 正常データのみ復元し、コードは実行しない |
| PERSIST-02 | 150→240を保存して再読込 | primaryは240、backupは直前の150 |
| PERSIST-03 | primary欠落／破損、backup正常／破損 | 正常backupで復旧。両方不正なら空データを作らない |
| PERSIST-04 | write失敗、読戻し不一致、Windows rename失敗 | 元150を保持し、再試行で240を保存 |
| PERSIST-05 | primary読取権限エラー | 新規ファイルと誤認せず保存停止 |
| PERSIST-06 | 150保存後、別ミッションで復元・90精算・二重初期化 | 合計240、任務2、帰還1、帰還失敗1、喪失1 |
| PERSIST-07 | 未接続で90精算後、既存150へ遅延接続 | 240へ1回だけ統合 |
| PERSIST-08 | 重複死亡・snapshot再送 | Score90・任務1・喪失1を維持 |
| PERSIST-09 | 古いrevision、別run、未来revisionの確認 | 新しい精算を誤って保存済みにしない |
| PERSIST-10 | flush／close失敗後、正常復帰 | 未保存表示を維持し、再試行成功で保存済み |
| PERSIST-11 | Hookなし、net.dostring_inなし、保存無効 | セッション内の訓練・採点を継続し未保存を明示 |
| PERSIST-12 | 非サーバー上のHook | ミッション通信・ファイル書込みなし |
| PERSIST-13 | 次frame前にSimulationStop | 最後の90を保存・確認 |
| PERSIST-14 | UCID取得不可 | 仮アカウントを保存しない |
| PERSIST-15 | 事故5種類の重複、任意Abort | 喪失は最初の精算で1回、Abortは0 |
| PERSIST-16 | Immediate SEAD＋DEADを事故精算 | 合計180、カテゴリ各90、任務・喪失は1 |
| PERSIST-17 | 次runの任務ID、旧runのsnapshot | IDを分離し、旧runの保存は拒否 |
| PERSIST-18 | primaryとbackup破損、訓練継続 | 元ファイル保持、ログを連発せず、未保存の90をメモリに保持 |
| PERSIST-19 | 復元時の数値上限超過、正常データで再試行 | 途中まで加算せず、正常復元で240 |
| PERSIST-20 | 保存済み・精算なしで一時通信障害、正常復帰 | 健全なpollで保存状態を回復し、再加算なし |
| PERSIST-21 | Hookにa_do_scriptも任務のglobalも存在しない別環境、文字列のみ返すAPI | server宛の型付き通信で初期化・90保存・確認が成立、接続ログは1回 |
| PERSIST-22 | API拒否／例外を繰り返し、許可を復旧 | エラーログ1回、接続前は保存ファイルを作らず、復旧後に未保存90を1回保存 |
| PERSIST-23 | 空・untagged・不正tag・不正数値・booleanのAPI返信 | 初期化や保存成功と誤認せず、保存ファイルを作らない |
| PERSIST-24 | mission初期化で例外、再試行、snapshotがtable、その後復旧 | 例外を文字列で通知、同runで安全に再試行、不正snapshotを保存せず、正常化後90を保存 |
| PERSIST-25 | 書込み後のAcknowledgeがfalse、その後正常化 | 保存済みと誤表示せず、正常化後に確認回復、90の再加算なし |

### ビルド・同期・導入（PowerShell）

| ID | 条件・操作 | 期待結果 |
|---|---|---|
| BUILD-01 | 一時プロジェクトで2回結合、初回同期、Check | bundleのハッシュが一致し、埋め込みLuaが結合結果と一致 |
| BUILD-02 | Watch起動後、コピーしたconfigのfullRewardを150→175へ変更 | 自動再結合し、埋め込みLuaに175が現れCheck成功 |
| SYNC-01 | 古いLua入りZIPへCheck→同期→Check→同じ内容で再同期 | 初回Checkは不一致検出のみ。同期後一致、元ZIPのバックアップあり。エントリ数・名前・時刻・非Lua内容を保持し、再同期はZIP・backupを書き換えない |
| SYNC-02 | 埋め込みLua欠落、ZIPエントリ重複、破損ZIP | 各理由で拒否し、元ファイルのハッシュを変更せずbackupも作らない |
| SYNC-03 | Watch中に古いミッションへ外部上書き保存 | ME保存相当の変更を検知し、埋め込みLuaを復元してCheck成功 |
| INSTALL-01 | 旧Hook・別Hookがある一時DCSディレクトリへ導入、再導入 | 同名旧Hookをbackup、新bundleと一致、別Hookを維持、再導入は無変更 |
| INSTALL-02 | Configを持たないディレクトリへ導入 | 拒否して書き込まない |
| INSTALL-03 | 実ファイルを使うwrite／restore／recoverを別Luaプロセスで実行 | 保存90→復元・追加180→primary破損時backup90復旧。実Saved Gamesには触れない |
| INSTALL-04 | BOMあり／なし・空のautoexec、既存DLSSとAPI許可、ConfigureHostを再実行 | 元設定・正確なbackupを維持、内容はidempotent、Lua実行で既存許可＋userhooks/serverのみを追加 |
| INSTALL-05 | 不完全・重複・不正形式の管理block、不正UTF-8 | 設定とHookを変更せず拒否 |

## DCS内の手動テスト

### 実施前提

同期済みの `mission/Syria.miz` を開き直し、ミッションを再開始する。
採点・UCID確認はマルチプレイのサーバー側で行い、静的BLUE Hornet Clientスロットを使う。
MP2は2人を受注前に搭乗させ、並行テストは別DCSグループを用意する。
機体の初期兵装が空なのは仕様なので、必要な兵装を地上で再武装する。

手動ケースは原則、別任務または新しいミッションで実施し、既存の達成・精算状態が条件を汚さないようにする。
SAM・方式・編隊はランダムなので、必要な組合せが未選択なら未実施として記録する。
テストのために設定値やテンプレートを変えた場合は、変更内容を記録し、標準設定の確認と区別する。

| ID | 手順・入力 | 合格条件 |
|---|---|---|
| MAN-01 | 各基地・SCのHornetへ搭乗し、F10とStatisticsを開く | 自グループにメニューが現れ、マルチプレイでUCIDが照合される。初期は0、採点なしならその理由を調査 |
| MAN-02 | Interceptを地上受注、離陸、別試行で待機中に着地、空中受注 | 地上は離陸検出後約20〜22秒、着地でリセット、空中は即生成 |
| MAN-03 | Interceptを繰り返し、3テンプレート・5編隊を確認 | 距離60〜80 NM、左右60°内、HOT、高度15,000〜30,000 ft。表示の機種・機数が実体と一致、AIが指定編隊へ移行 |
| MAN-04 | Interceptの2機編成を1機だけ破壊し、その後全滅 | 1機生存中は未達成、全滅で帰還指示 |
| MAN-05 | SEADを地上受注して計画を確認し、移動して全員離陸 | 離陸前はSAM実体なし。全員離陸後に同じ計画で生成。方式・表示座標・コードを再抽選しない |
| MAN-06 | SA-6/SA-8を4Zoneでそれぞれ生成し、観戦・ME等で実位置を確認 | 地面へ配置、全車両がZone内、建物等との離隔、ME相対配置、Radarの発信・交戦を確認。8組合せを個別記録 |
| MAN-07 | TOOで地上・空中受注・計画確定・開始・Statusを記録し、終了後に実位置と比較 | 座標付き自動表示は計画確定時の1回だけ。Statusで同じDDM・分の小数3桁を確認でき、捜索点が3〜5 NMずれ、機種UNKNOWN、正確位置・PBコードが表示されない |
| MAN-08 | PBで地上・空中受注、推定点・コードを受け取りHornetのHARMへ設定、開始・Statusを確認 | 座標・コードの自動表示は計画確定時の1回だけで、Statusで再確認可能。DDM・分の小数3桁、SA-6=108/SA-8=117、位置誤差1〜3 NM。実際にPB攻撃の入力・使用が可能 |
| MAN-09 | SA-6の発射機だけを破壊、別試行でレーダーを破壊。SA-8も破壊 | 発射機だけでは未達成。主要対象の破壊で即DESTROYED、`SEAD Objective Complete / Enemy radar destroyed.` |
| MAN-10 | 主要対象を無傷でRadar OFF、または損傷させたままRadar ON | どちらも成功しない。単なるLife残量や発信なしだけで達成しない |
| MAN-11 | 主要対象が生存したまま損傷し、Radar OFFを維持 | StatusがSUPPRESSION PENDING。59秒では未達成、連続60秒以上でSUPPRESSED、`Enemy radar suppressed.` |
| MAN-12 | MAN-11の計測途中でRadar ONへ戻し、再びOFFにする | ACTIVEへ戻って経過時間をリセット、次のOFFから新たに60秒必要 |
| MAN-13 | PENDING中に主要対象を破壊 | 60秒を待たずDESTROYED |
| MAN-14 | SUPPRESSED後にRadarを再開、または残存Launcherを破壊 | 結果はSUPPRESSEDのまま、追加報酬なし。精算前にサイトが自動削除されない |
| MAN-15 | 達成後BLUE飛行場へ着陸、5 knots以下で10秒停止 | 各自150を一度だけ加算。9秒まで未確定、速度超過・復行では確認リセット |
| MAN-16 | 達成後に移動中のBLUE空母へ着艦、ボルターも別試行 | 艦との相対速度で10秒確認し150。ボルターでは未確定 |
| MAN-17 | 達成後の脱出・墜落・死亡、別試行で達成前事故・任意中止 | 達成後90、達成前事故・任意中止0、重複イベントで二重加算なし |
| MAN-18 | MP2で片方だけ離陸→両者離陸、共有達成後に片方帰還・片方事故 | 全員離陸待ち、各自150/90。1人目の精算後も次の任務は拒否し、全員終了後に解放・SAM削除 |
| MAN-19 | MP2空席へ受注後に途中参加し、その人が着陸・事故 | 今回の登録参加者・報酬に追加しない。共有任務の状態を消さない |
| MAN-20 | 別ウィングがSEAD/Interceptを並行受注し、片方を中止・達成 | 敵Group・タイマー・採点・ロックを他方と共有しない |
| MAN-21 | 参加者が切断・同じ機体へ復帰、別スロットへの移動・再スポーン | 切断中の停止時間を加算しない。別機体で元出撃の満額を受け取らず、元任務のUCIDロックを維持 |
| MAN-22 | Hook導入下で複数任務を精算、保存済み表示を確認してミッション・DCSを再開始 | 同じUCIDのTotal/Career・カテゴリ別Score・任務／帰還／死亡統計を復元する。別UCIDの成績は混ざらない |
| MAN-23 | 最後の参加者が精算・中止し、残存SAMと次の受注を確認 | 残存Groupが削除され、次の受注が可能。完了時点では削除されない |
| MAN-24 | SA-6レーダーだけ破壊・Suppress、別試行でSA-8を全滅 | 残存がある場合だけContinue/Preserve。SA-8全滅では選択肢なし |
| MAN-25 | SEADからContinueし、損傷・発信状態と車両を確認、残存全滅してRTB | 同じGroupを使用、SEAD150＋DEAD150、合計300、任務1件 |
| MAN-26 | Immediate途中に事故、別試行で両目標達成後事故、全体Abort | 未達成事故SEAD90／DEAD0、達成後事故各90、Abort両方0、全員終了でCleanup |
| MAN-27 | Preserve、全員RTB・再武装、地上でGenerate DEAD、全員離陸 | 同じSiteが残り、新IDで予約。ARMED中もSAMは存在、全員離陸でACTIVE、20秒待ちなし |
| MAN-28 | Follow-on DEADの開始・Status座標確認、全残存対象破壊後RTB、別試行で事故/Abort | SITE LOCATIONは実配置点のDDM・分の小数3桁で初期60秒表示。DEAD150/90/0、SEAD Scoreを変えない、全員終了後Cleanup |
| MAN-29 | 複数保持Siteを作り、異なる長機位置から受注 | 最も近いRETAINを選び、2Wingが同Siteを二重取得できない |
| MAN-30 | MP2でPreserve後に1人だけ精算、別WingがDEAD取得を試す | 元SEAD全員終了までSiteを取得できず、終了後に取得可能 |
| MAN-31 | 2つのFollow-on DEADを並行実行し、片方だけ中止・達成 | 対象・敵・ポイント・ロック・Cleanupを混同しない |
| MAN-32 | 保持Siteを味方が外部攻撃で全滅、Generate DEAD | 全滅したSiteは候補にならず、再生成しない |
| MAN-33 | Immediate・Follow-on DEADのStatusと一時メニューを遷移ごとに確認 | disposition・予約可否・残数・DEAD Scoreが一致し、不要になったContinue/Preserveを消す |
| MAN-34 | 保持・DEAD精算後にミッション再開始 | Siteと進行中任務は復元しない。Hookで保存済みの成績だけを復元する |
| MAN-35 | Preserve時の長機がRTB後にログアウト、別試行で精算前にログアウト | 1秒監視でRETAIN Site削除、SEAD採点・任務ロックを巻き戻さない |
| MAN-36 | MP2僚機がPreserveを選び、観戦へ移動・僚機切断・長機切断 | 保持者は最初の登録長機、観戦・僚機切断では保持、長機ログアウトで削除 |
| MAN-37 | 他WingがFollow-on DEADを取得、元保持者がログアウト | IN_USE Siteを削除せず、DEAD目標・採点を継続 |
| MAN-38 | SA-6レーダーだけ破壊し、Launcherを1/3両残して両DEAD経路を実施 | Primary DESTROYED・Site SUPPRESSED・残数1/3、残存だけ対象。別試行でSuppressedレーダーを残す場合はレーダーも全滅対象 |
| MAN-39 | MP2 Immediateで両目標達成後、1人帰還・1人事故。別試行で1人をDEAD達成前に喪失 | 帰還300／達成後事故180、DEAD達成前喪失90。精算済み参加者へ追加採点せず、任務数各1 |
| MAN-40 | Hook未導入／保存無効で受注・精算 | Session only表示で訓練・採点を継続し、保存済みと表示しない |
| MAN-41 | 保存先の書込みを一時的に失敗させ、精算後に権限を復旧（テスト用コピー） | 保存未確認表示とログ、正常復帰で同じ累計を1回保存。MissionScripting.luaの変更なし |
| MAN-42 | SEAD達成→Continue、車両を残してBLUE基地／空母へRTB | 5 knots以下（空母は甲板相対）を10秒維持するとSEAD150／DEAD0、全員終了で残Site Cleanup。着陸確認中の事故はSEAD90／DEAD0 |
| MAN-43 | MP2 Immediateで1人がDEAD未達成のままRTB、もう1人が攻撃継続 | 帰還者SEAD150／DEAD0で固定。僚機終了までSite・ロック維持、僚機が達成して帰還すれば300。着陸確認中の目標達成では確認タイマーを維持 |

MAN-10〜14は、実際にLife減少とRadar ON/OFFの前提を確認できたときに実施済みとする。
HARMの命中やRWR表示だけからLife/Radar状態を推測しない。Mission Statusの状態とDCS/MOOSEの観測を併せて確認する。
AIが意図したON/OFFを起こさず再現できない場合は「未実施」または「条件未成立」と記録する。
制御用のテストスクリプトを使用する場合は、通常ミッションへ恒久的に追加せずテスト用コピーで実施する。
1秒のpollingなので、観測の間の短いON/OFF切替は今回の判定では検出できない。

## 変更時に行う検証

| 変更箇所 | 最初に確認するスイート | 追加確認 |
|---|---|---|
| Interceptの配置・編隊・テンプレート | INT | WING/PARで共有・独立性、MAN-02〜04 |
| SEAD計画・Zone・地形・情報表示 | SEAD | MAN-05〜08、MEの実設定とfixtureの整合 |
| 座標表示時間・開始通知 | INT-16 / SEAD-62 / DEAD-16/17 | MAN-02/07/08/28、SEADの計画ブリーフィングと座標付きStatusが初期60秒で表示されること |
| SEADの状態機械・Life/Radar | SEAD-45〜59 | MAN-09〜14 |
| サイト管理・Cleanup | SEAD-57〜61 / DEAD-53〜62 | MAN-18/20/23/35〜37 |
| DEAD対象・phase・保持・予約 | DEAD | MAN-24〜34、SEAD-45〜61の回帰 |
| player/missions/runtime | WING/PAR | INT/SCORE/SEAD、UCID・F10のマルチ確認 |
| scoring/recovery・採点設定 | SCORE | WING/SEAD、MAN-15〜18/21/22 |
| 成績永続化・サーバーHook | PERSIST / INSTALL | Lua全7スイート、MAN-22/34/40/41、DCSでのnet.dostring_in(server)接続・停止callback順の確認 |
| 結合・同期・Watch | BUILD/SYNC | 実 `.miz` に対する `-Check` |
| MEのスロット・テンプレート・Zone変更 | 対応するLuaスイート | 実 `.miz` 確認と該当する手動ケース。fixtureだけではME変更を検出できない |

共通モジュールの変更や機能追加の完了時は、両bundleの結合後にLua7本を実行し、既存カテゴリへの回帰を確認する。
ツール変更ではBUILD/SYNCも実行する。通過後の追加検証は、変更・失敗・未解決の懸念がある場合に行う。
表のID範囲は重点確認するケースを示す。現在、個別ケースを指定するrunnerはないので、対応するスイート全体を実行する。

## 結果の記録と仕様の維持

2026-10-04のDEAD追加前はLua145ケース、BUILDの2確認グループ、SYNCの3確認グループの通過を確認済み。
同日のPrimary Result/Site残存判定分離後はLua全211ケース（INT15、SCORE26、WING27、PAR16、SEAD61、DEAD66）、BUILDの2確認グループ、SYNCの3確認グループがすべて通過した。
同日のImmediate DEAD追加採点後はLua全221ケース（INT15、SCORE26、WING27、PAR16、SEAD61、DEAD76）、BUILDの2確認グループ、SYNCの3確認グループがすべて通過した。DCS内の追加採点確認は未実施。
同日のTOO/PB DDM表示変更後もLua全221ケースが通過し、実ミッションのLua同期・Checkが成功した。DDM表示のDCS内確認（MAN-07/08）は未実施。
同日のSite/DEAD nil観測修正・SEAD FSMのnil観測経路修正・Follow-on DEAD DDM統一後はLua全225ケース（INT15、SCORE26、WING27、PAR16、SEAD61、DEAD80）が通過した。BUILDの2確認グループ、SYNCの3確認グループも通過。DCS内のFollow-on座標確認（MAN-28）は未実施。
2026-10-05のSEADブリーフィング重複修正後はLua全226ケース（INT15、SCORE26、WING27、PAR16、SEAD62、DEAD80）が通過した。BUILDの2確認グループ、SYNCの3確認グループ、実ミッションのLua同期・Checkも成功。DCS内の自動表示回数とStatus再確認（MAN-07/08）は未実施。
同日の座標表示時間延長・Intercept受注通知整理後はLua全227ケース（INT16、SCORE26、WING27、PAR16、SEAD62、DEAD80）が通過した。表示時間の初期60秒と設定変更後90秒、Intercept開始表示1回を模擬検証。BUILDの2確認グループ、SYNCの3確認グループ、実ミッションのLua同期・Checkも成功。DCS内の表示時間・回数確認は未実施。
同日の成績永続化実装後はLua全247ケース（既存227＋PERSIST20）、BUILD2確認グループ、SYNC3確認グループ、INSTALL3確認グループが通過した。INSTALLでは実ファイル保存・別Luaプロセスでの復元・破損primaryのbackup復旧も確認。実ミッションのLua同期・Checkも成功。DCS内のHook接続・再起動復元・停止callback順は未確認。
同日のImmediate DEAD未達成からのSEAD帰還修正後はLua全253ケース（INT16、SCORE26、WING27、PAR16、SEAD62、DEAD86、PERSIST20）、BUILD2、SYNC3、INSTALL3確認グループが通過した。未達成RTBのSEAD150／DEAD0、MP2個別精算と僚機継続、復行、確認中事故、確認中DEAD達成を模擬検証。実ミッションのLua同期・Checkも成功。DCS内のMAN-42/43は未確認。
同日、ユーザー承認後に `C:\Users\hayat\Saved Games\DCS\Scripts\Hooks\DynamicTrainingPersistenceHook.lua` へ導入し、生成bundleとのハッシュ一致を確認した。DCS再起動後の実機確認は未実施。
同日の保存Hook通信修正後はLua全258ケース（既存233＋PERSIST25）、BUILD2、SYNC3、INSTALL5確認グループが通過した。Hookとミッションの別Lua環境・文字列通信・API拒否・不正返信・再接続、ホスト設定の保持・backup・idempotence・不正設定拒否を検証。実ミッションのLua同期・Checkも成功。ユーザー承認後に実Saved GamesのHookとautoexec.cfgをbackup付きで更新し、Hookハッシュ一致・既存DLSS設定維持・userhooks→server許可ブロック1件を確認した。DCS再起動後の接続・精算保存・再起動復元は未確認。
本書のLuaケース数・番号と実行ファイルの対応、READMEと本書のリンク先も確認済み。
DCS内のSEAD状態遷移・DEAD継続・サイト管理・採点の各手動ケースは個別結果の記録待ち。
過去の「ゲーム内で動いている」という報告は、未記録の手動ケースすべての合格とは扱わない。

手動・回帰確認の記録には、次の形式を使う。結果は `PASS / FAIL / 未実施 / 条件未成立` のいずれかとする。

| 実施日時 | 対象版・設定 | テストID | 結果 | 実測・証跡・備考 |
|---|---|---|---|---|
| YYYY-MM-DD HH:mm | commitまたは変更内容、DCS版、サーバー/クライアント、設定差分 | MAN-11等 | 未実施 | 任務ID、Wing、SAM/方式/Zone、開始/復帰/完了時刻、ポイント、画面・ログ |

自動テスト失敗時は、実行コマンド・終了コード・英語のケース名・stack traceを保存し、模擬ログの想定外エラーも確認する。
DCS内の不具合では任務ID・Group・時刻と、`dcs.log` の `[DynamicTraining]` 付近を記録する。

テストを追加・変更したら、本書の対応行と件数、機能仕様書の検証範囲も同じ作業で更新する。
新しい成功条件は、正常系に加え「成功してはいけない条件」、境界値、イベント順序、別ウィングへの非干渉を確認する。
仕様とfixtureが同時に誤っていても自動テストは通るため、期待結果は機能仕様書に照らして見直す。

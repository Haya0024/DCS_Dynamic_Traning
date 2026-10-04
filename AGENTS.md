# DCS Dynamic Training

## 目的

DCS World の Syria マップ上で動作する、
永続型のダイナミック訓練サンドボックスを作成する。

このプロジェクトは陣取り型キャンペーンではなく、
BVR、SEAD、DEAD、Strike、CAS、Anti-Ship などの訓練ミッションを
動的に生成することを主目的とする。

---

## 使用環境

- DCS World
- Syria マップ
- MOOSE Framework
- プレイヤー機体: F/A-18C Lot 20
- BLUE Coalition: USA
- RED Coalition: Russia

---

## BLUE プレイヤースロット

以下の Client スロットを使用する。

- `BLUE_HORNET_INCIRLIK_01`
- `BLUE_HORNET_AKROTIRI_01`
- `BLUE_HORNET_BEIRUT_01`
- `BLUE_HORNET_RAMAT_01`

プレイヤーは任意の BLUE 空港から出撃できる。

プレイヤー機の初期パイロン設定は意図的に空とする。
プレイヤーが地上で再武装を要請し、好きな兵装を搭載する運用とする。
スクリプトで兵装を固定せず、空の初期設定を不備として扱わない。

スクリプト側では特定の空港を固定せず、
現在操作中のプレイヤー機を動的に取得すること。

---

## 現在の BVR テンプレート

グループ名:

`TPL_BVR_MIG29_2`

構成:

- MiG-29A × 2
- RED / Russia
- Late Activation 有効
- Airborne Start
- CAP Task

このグループは実際の初期配置用ではなく、
動的スポーン用のテンプレートとして使用する。

---

## BVR ミッションの基本動作

プレイヤーが F10 メニューから
`Generate BVR` を選択したとき、以下の動作を行う。

### プレイヤーがすでに空中にいる場合

即座に BVR ミッションを開始する。

### プレイヤーが地上にいる場合

BVR ミッションを待機状態にする。

プレイヤーの離陸を検出したら、
20秒待ってから、その時点のプレイヤー位置・機首方向を基準に BVR ミッションを開始する。
離陸は2秒間隔で判定するため、実際の離陸から生成までは約20～22秒となる。
予約したプレイヤー機を保持し、AI 僚機の離陸では開始しない。
生成前に着地した場合は離陸待ちに戻し、プレイヤー死亡・離脱・機体変更時は予約を解除する。

### 敵機生成条件

初期仕様では以下とする。

- プレイヤー現在位置から 60～80 NM
- プレイヤー機首方向から左右60°以内の方位をランダム化
- 敵は HOT aspect（実際の生成位置からプレイヤーへ向く）
- 高度は一定範囲からランダム
- 生成には `TPL_BVR_MIG29_2` を使用する

将来的には以下を追加する。

- 方位範囲を側方・後方へ拡張
- 高度差
- 機種ランダム化
- 敵数ランダム化
- 複数編隊
- FLANK / BEAM / COLD aspect
- ECM
- 敵 AWACS
- 複数方向からの攻撃

---

## BVR ミッション終了条件

生成した敵航空機をすべて撃墜した場合、
Primary Objective Complete とする。

撃墜完了後も即座に完全終了とはせず、
BLUE 空港への RTB を追加評価対象とする。

例:

- 敵全滅: Mission Success
- BLUE 空港へ帰還: RTB Bonus
- 生還: Bonus
- ノーダメージ: Bonus

---

## 難易度システム

難易度は 1～5 の5段階とする。

例:

- Difficulty 1: Training
- Difficulty 2: Easy
- Difficulty 3: Normal
- Difficulty 4: Hard
- Difficulty 5: Expert

単純に敵数だけを増やすのではなく、
Threat Budget を使用して難易度を構成する。

例:

- MiG-21 = Threat Cost 1
- MiG-29 = Threat Cost 2
- Su-27 = Threat Cost 3
- Su-30 = Threat Cost 4

Difficulty ごとに使用可能な Threat Budget を決め、
その範囲内で敵編成を生成する。

難易度には以下も影響させる。

- 敵数
- 機種
- AI Skill
- 初期距離
- 高度差
- 敵編隊数
- Aspect
- ECM
- AWACS 支援
- 情報量

---

## ポイントシステム

各ミッションに Score を設定する。

基本報酬は Threat Budget や Difficulty を基準に算出する。

評価対象の例:

- Primary Objective 完了
- RTB 成功
- 生還
- ノーダメージ
- Optional Objective 完了
- Friendly Loss
- Friendly Fire
- Mission Abort
- Player Death

単純な撃墜数だけではなく、
安全に帰還することも高く評価する。

---

## Career Points

各ミッションの Score とは別に、
永続的な Career Points を持つ。

Career Points はサーバー再起動後も保存する。

将来的には以下の情報を保存する。

- Total Score
- Career Points
- Mission Count
- Success Count
- Failed Count
- Abort Count
- Death Count
- RTB Count
- A/A Kill Count
- Ground Kill Count

---

## カテゴリ別レーティング

将来的にミッションカテゴリごとの成績を保存する。

例:

### Air-to-Air

- BVR
- ACM
- Intercept

### Air-to-Ground

- SEAD
- DEAD
- Strike
- CAS

### Naval

- Anti-Ship
- Carrier Operations

例:

BVR: 1820
SEAD: 1640
Strike: 1050
CAS: 720

---

## Persistence

永続化対象は、
戦線や陣地所有権ではなくプレイヤー進行状況を中心とする。

保存候補:

- Career Points
- Total Score
- 各カテゴリ Rating
- Mission Statistics
- Success / Failure
- Death
- RTB
- Kill Statistics
- 推奨 Difficulty

保存形式は後で決定する。

---

## 将来追加するミッション

以下を順次追加する。

- BVR
- Intercept
- ACM
- SEAD
- DEAD
- Strike
- CAS
- Anti-Ship
- Escort
- Navigation
- Carrier Case I
- Carrier Case III

---

## F10 メニュー構成

将来的には以下のような構造を目指す。

Dynamic Training
- Generate Mission
  - Air-to-Air
    - BVR
    - Intercept
    - ACM
  - Air-to-Ground
    - SEAD
    - DEAD
    - Strike
    - CAS
  - Naval
    - Anti-Ship
- Difficulty
  - 1 Training
  - 2 Easy
  - 3 Normal
  - 4 Hard
  - 5 Expert
- Mission Status
- Abort Mission
- Player Statistics

---

## コーディング方針

以下のルールを守ること。

- gameplay ロジックをモジュール分割する
- プレイヤー空港をハードコードしない
- 現在操作中のプレイヤーを動的に検出する
- プレイヤー向け表示は NM / ft / knots を基本とする
- 設定値とロジックを分離する
- BVR、SEAD、Strike などを独立モジュール化する
- ミッション状態を一箇所で管理する
- 同一ミッションを二重生成しない
- Debug 用メッセージを明確にする
- エラー時にはゲームを止めず、可能な限りログと画面表示を残す
- `.miz` のミッション設定・トリガー・リソース対応表を直接編集しない。例外として、登録済みの埋め込み Lua は `scripts/Sync-Mission.ps1` による同期を許可する
- Mission Editor で設定したテンプレート名を勝手に変更しない
- MOOSE の API を優先して使用する
- DCS 標準 Lua API と MOOSE API を混在させる場合は理由をコメントする

---

## ファイル構成

初期構成:

DCS-Dynamic-Training/
- AGENTS.md
- README.md
- docs/
  - DESIGN.md
- src/
  - main.lua
  - bvr.lua
  - config.lua
- mission/
  - DynamicTraining_Syria.miz
- vendor/
  - MOOSE/
    - Moose.lua

将来的に以下を追加する。

- difficulty.lua
- scoring.lua
- persistence.lua
- player.lua
- sead.lua
- strike.lua
- cas.lua
- antiship.lua

---

## 開発ルール

機能追加は一度に大きく進めず、
小さい単位で実装・確認する。

### 機能別仕様書

- 機能単位の仕様書を `docs/<機能名>.md` に作成する。BVR は `docs/BVR.md` を参照する。
- 仕様書では、現在の実装・既知の制約・将来仕様を区別する。
- 機能の動作や設定値を変更したら、対応する仕様書も同じ作業で更新する。
- コードに実装済みであることと、DCS 内で動作確認済みであることを区別して記録する。

### Lua と .miz の同期

- `src/DynamicTraining.lua` と `vendor/MOOSE/Moose.lua` を編集元とする。
- Codex は上記 Lua を変更したら、作業完了前に必ず以下を順に実行し、`mission/Syria.miz` も更新する。
  1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1`
  2. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Sync-Mission.ps1 -Check`
- 同期・確認に失敗した場合は、反映済みと報告せず理由を伝える。
- 同期は既存の埋め込み Lua の置換に限定する。その他の ZIP エントリの内容が変わらないことを検証し、置換前の `.miz.bak` を残す。
- 新しい Lua モジュールの登録や読み込み順の変更は Mission Editor で行う。未登録のファイルを自動追加しない。
- ユーザー自身が編集する場合の自動同期は `-Watch` または VS Code の `DCS: Watch mission Lua` タスクを使用する。
- 同期後に ME から実行する場合は `.miz` を開き直す。実行中のミッションへの反映には再開始が必要。

現在の優先順位:

1. MOOSE 読み込み
2. F10 メニュー表示
3. プレイヤー取得
4. 地上 / 空中判定
5. 離陸検出
6. BVR 敵機スポーン
7. 敵ルート設定
8. 敵全滅判定
9. Mission Complete
10. Difficulty
11. Score
12. Persistence
13. 他ミッション追加

各段階で動作確認してから次へ進むこと。

---

## 現在の状態

以下はすでに確認済み。

- MOOSE 読み込み成功
- `DynamicTraining.lua` 読み込み成功
- F10 `Dynamic Training` メニュー表示成功
- `Generate BVR` コマンド表示成功
- BLUE 側 F/A-18C Client slot を4空港に配置済み
- RED 側 MiG-29A ×2 の BVR template 作成済み

次の DCS 内での動作確認対象:

`Generate BVR` 選択時に、

- 空中なら即 BVR Spawn
- 地上なら離陸待ち
- 離陸検出から20秒後に BVR Spawn（生成時点の位置・機首方向を使用）

上記処理は `src/DynamicTraining.lua` に実装済み。今回修正した前方位置・経路の計算も含め、ゲーム内で段階的に確認する。

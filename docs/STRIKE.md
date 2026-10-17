# Strike（固定施設のTOO捜索・攻撃）

実装仕様: 2026-10-17 / training-11。DCS内での生成・捜索・実射・精算は確認待ち。

## 受注と抽選

`Task: Strike` は受注時の登録参加者の長機位置を基準とする。MP2では機体番号が最小の操縦中機を長機とし、途中参加者・AIを加えない。既存のWing/UCIDロックを生成前に取得する。

対象はMEに配置したSITE01～06の独立施設。各司令部（TPL_CMD_SITE##_01）の配置点までの水平距離で並べ、近い2施設に限定する。使用可能な施設から等確率で1つ選び、下記3種類の攻撃対象を各1/3で抽選する。1施設だけ使用中ならもう一方を使い、両方使用不可なら採点なしで解除する。3番目へ回さない。距離の上下限・空港所有権による選別は行わず、受注後の移動・離陸・長機交代では再抽選しない。同距離はSite ID順とする。

| 攻撃対象 | 対象となる物体 | 達成条件 |
|---|---|---|
| 倉庫（コンテナ群） | 番号02～05の20 ftコンテナ4個 | 任意の2個を破壊。2個の再抽選・固定指定はしない |
| 司令部 | 番号01のCommand Center | 1個を破壊 |
| トラック | 番号06・07のUral-375 | 両方を破壊 |

## MEテンプレートと生成

各Siteに次の7個を用意する。グループ名はSITE01～06で同じ規則。実ユニット名は末尾`-1`の有無が混在しているため、MOOSEの登録済みStaticName（MEグループ名）から実名を解決する。ME側の名前を変更しない。

| MEグループ名の例 | 実TypeName | 個数 |
|---|---|---:|
| TPL_CMD_SITE01_01 | .Command Center | 1 |
| TPL_CONT_SITE01_02～05 | container_20ft | 4 |
| TPL_TRUCK_SITE01_06～07 | Ural-375 | 2 |

位置・向き・種類はMEだけを正とし、Luaに座標を複製しない。起動時に42個のテンプレートを取得して原本をイベントなしで除去する。原本除去が確認できるまでその施設は使用しない。欠落・重複グループ名・不正Type・非RED・死亡済みの構成はそのSiteを無効とし、取得済みの他原本は除去する。他カテゴリを停止しない。司令部の座標が取得できる無効Siteは距離順にも残すため、近い2施設の不備で遠い施設へ黙って回さない。司令部自体が欠落し座標不明なら距離順には含められない。

受注時に選んだ施設の7個すべてを、同位置・同方向にSPAWNSTATICで生成する。抽選した攻撃対象以外は周辺設備であり、その破壊は達成条件を進めない。生成物は任務別の一意な名前・新規IDを使い、元テンプレート名を変更しない。地形への再配置やLife補正はしない。生成途中の失敗でも生成済み参照を保持して削除を再試行する。トラックもStaticであり、移動・暖機・エンジン稼働を指示しない。

## 状態・達成・終了

受注準備 → ACTIVE（地上でも即生成）→ 必要数の破壊でRTB_PENDING → 全参加者精算で終了。離陸待ち・20秒生成待ちは設けない。達成前にRTBしても任務は継続する。

`plan.targets`は選んだ種類の全候補（4/1/2個）、`plan.requiredCount`は必要破壊数（2/1/2個）。コンテナの1個破壊や同じ物体の重複死亡イベントでは達成しない。Lifeが残る損傷を破壊扱いしない。対象の明示死亡イベントまたは同一実体の死亡観測を使い、nil・例外・不正値・別IDを破壊根拠にしない。観測不能が残っていても別の2コンテナの破壊が確定すれば達成。第三者による指定対象の破壊も数える。

Missions.strikeSitesへSite ID単位で使用予約し、異なるWingによる同じ施設への同時生成を防ぐ。全員終了までは予約と残存物を維持する。終了後は周辺設備を含む7個すべてを削除し、失敗時は予約を維持して5秒ごとに再試行する。削除完了後に予約解除。達成直後には残存物を削除せず、保持・次Sortie継続は設けない。

各自の帰還150、達成後事故90、達成前事故・Abort0。共有達成・個人精算・帰還条件は既存任務と同じ。Strike Score・Total/Career・既存統計を更新する。保存はAir Interdictionを含むschema4を使い、Strikeの採点規則は維持する。mission/Hookを同時更新する。進行中任務・予約・生成物は再起動後に復元しない。

## 表示

受注通知10秒、その後の座標ブリーフィングは共通coordinateBriefingSeconds（初期60秒）で1回。施設をTOOで捜索し、ポッド等で識別・照準する。施設の司令部を共通案内点としてDDM（度＋小数分、分の小数3桁）を1組だけ表示する。COORDINATE:ToStringLLDDMへLL_Accuracy=3を明示し、全体設定に依存させない。座標へのランダムな誤差追加はしないが、個々の目標のPP用DMS・標高は表示しない。CAP/SEAD/DEADの座標仕様は変更しない。

```text
Strike mission accepted.
```

```text
STRIKE MISSION
TARGET AREA: <施設基準点のDDM、分の小数3桁>
OBJECTIVE: Destroy any 2 of the 4 storage containers; then RTB.
Reward per pilot: 150 points.
Registered pilots: 1.
```

司令部は `Destroy the command center`、トラックは `Destroy both trucks` に置き換える。見出し・AREA・OBJECTIVE・報酬・人数の5行。達成通知は次の本文を20秒表示する。

```text
Strike Objective Complete
Assigned targets destroyed.
Each pilot: return to a BLUE airfield or carrier.
Reward per pilot: 150 points; recovery failure: 90 points.
```

近い2施設が使用不可なら `No available Strike targets among the two nearest sites. Try again later.` を20秒表示してWing/UCIDロックを解除する。準備失敗は従来のERROR通知とrollbackを使う。

Mission Statusは公開済み本文だけを再表示し、現在残数・内部予約・抽選候補・未選択目標を追加しない。達成後は座標を外し、公開済み達成・帰還通知だけを20秒表示する。全員終了後はIdle。

## 任意の目標スモーク

StrikeがACTIVEで、受注Wingに操縦中・未精算の登録参加者がいる場合だけF10へ `Mark Strike Target` を表示する。選択時に共通の施設案内点の北50 mの地表へ赤煙を1本出し、約120秒後に停止する。攻撃対象の種類で点煙位置を変えない。座標・抽選・目標・採点は変更せず、自動点煙はしない。色・北オフセット・時間はConfig.strike.smokeで管理する。煙は他プレイヤーからも見える。各F10ページは9コマンド＋Moreを上限とする。

成功通知は `Strike target marked with RED smoke.` と次行 `Smoke is 50 m north of the target; lasts 120 seconds.` を10秒表示する。この通知のtargetは案内点を指す。停止前の連打は `Strike target already marked. Try again later.` を10秒表示し追加しない。停止後は再要求可能。点煙通知はMission Statusを上書きしない。

達成時と全員終了時にも停止する。古いcallbackは任務・状態・Wing・操縦中登録者を再照合し、無効なら `Strike target marking is no longer available.` を10秒表示する。煙API失敗は `ERROR: Strike target smoke failed. See DCS log; retry later.` を15秒表示し、任務・得点を維持する。停止失敗は施設予約・目標削除とは独立に5秒ごと再試行し、帰還精算や施設解放を妨げない。

## 検証

scripts/Test-Strike.luaと、実.mizの42テンプレート・全18種類の生成を使うscripts/Test-StrikeMission.ps1で模擬検証する。実DCSではTOO捜索・司令部の破壊に必要な兵装と信管・コンテナ任意2個・トラック2両・3D配置・スモーク・MP2精算・並行Wing・再受注を確認する。画像表示機能はこの変更には含めない。

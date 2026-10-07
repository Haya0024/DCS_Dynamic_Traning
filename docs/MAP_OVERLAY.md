# BLUE Airbase F10 Drawing

更新日: 2026-10-06。実装・模擬検証済み、DCS内での表示確認は未実施。

BLUE所属の陸上AirbaseはF10上に青色Drawingで表示する。表示対象はruntimeでcoalitionから自動取得する。
目的は味方基地の視認性だけであり、任務・採点・帰還判定・F10メニュー・基地所有・Allies Only・Fog of Warを変更しない。

## 現在の実装

- `src/map_overlay.lua` が列挙・Drawing・ID管理を担当する。
- `AIRBASE.GetAllAirbases()` で同梱MOOSEのruntime Airbase databaseを列挙し、各基地の現在の `GetCoalition() == coalition.side.BLUE` を確認する。空港名の固定リストを使用しない。
- `GetAirbaseCategory() == Airbase.Category.AIRDROME` のみ採用し、`isHelipad` / `isShip` も除外する。RED / Neutral / Carrier / Ship / FARP / Helipadは表示しない。
- 同梱MOOSEの `AIRBASE:Register` はDCSのCategory誤判定を補正する。滑走路なし・ヘリ用駐機のみのheliportはHELIPADへ補正するため、`IsAirdrome()`だけで対象を決めない。基地名による除外は行わない。
- MOOSE `GetVec2()` の滑走路中心を `COORDINATE:NewFromVec2():GetVec3()` へ変換する。DCSの生の位置は滑走路端になる場合があるため使用しない。
- `trigger.action.circleToAll` と `trigger.action.textToAll` へBLUE（2）を明示する。双方readOnly=trueで、通常Marker入力やF10任務メニューを追加・変更しない。
- Circleは半径2,500 m、青い輪郭（alpha 0.65）、非常に薄い青の塗り（alpha 0.04）、実線。
- Textは基地中心から南へ1,000 mに `BLUE AIRBASE\n<runtime airbase name>`、明るい青、透明背景、fontSize=16。通常の基地名との重なりを避けるため、Circleと別の座標で描画する。
- `mapOverlay.textOffsetSouthMeters` で文字の南方向の移動量を調整する（0で中心）。北が上のF10 Mapでは下方向となる。画面pixelではなく地理的な距離なので、ズーム・地図回転によって見え方は変わる。
- 表示値は `src/config.lua` の `mapOverlay` に集約する。Recoveryの基地半径設定と独立する。

## APIとID

Drawingの引数は現在同梱の `vendor/MOOSE/Moose.lua` の `COORDINATE:CircleToAll` / `TextToAll` と照合済み。
直接DCS APIを呼ぶ理由は、部分的な生成失敗でも事前確保したIDを追跡・削除できるようにするため。RGBAを直接渡し、MOOSE wrapperによる設定色のalpha書き換えも避ける。

```lua
trigger.action.circleToAll(side, id, vec3, radius, rgba, fillRGBA, lineType, readOnly, message)
trigger.action.textToAll(side, id, vec3, rgba, fillRGBA, fontSize, readOnly, text)
```

全Circle/TextにMOOSE共通の `UTILS.GetMarkID()` で一意なIDを割り当てる。
1基地あたりCircle1＋青Text1の2 ID。黒文字の重ね描きは行わない。
開始時の下限は1,000,000で、既存allocatorの値がそれ以上なら巻き戻さない。以後のMOOSE/DT Drawingも同じallocatorを使い、独立した固定IDを持たないこと。
ME・ユーザーMarkerが通常使用する低いIDとの衝突を避ける下限であり、外部スクリプトが同じIDを決め打ちする場合の競合までは防げない。

`DynamicTrainingMapOverlayState` は所有IDと最大使用IDだけを保持する。任務・Site・成績には接続せず、永続保存もしない。他のDrawingやMarkerを削除しない。

## Lifecycleとエラー

`MapOverlay.RefreshFriendlyAirbases()` を `src/main.lua` の初期化時に1回だけ呼ぶ。周期更新・captureイベント購読・追加タイマーは設けない。
再呼び出しは現在のcoalitionを再列挙し、旧Overlayを削除して再作成する。module再初期化でも所有IDを保持し、重複を防ぐ。
将来coalitionが変化した際はこの関数を明示的に呼び出せる。今回の初期表示は、後からcaptureが起きても自動更新しない。

列挙失敗は旧Drawingを維持し、個別観測失敗はその基地だけ除外する。
生成失敗は該当基地のCircle/Textをrollbackする。削除失敗はIDを保持して次回Refreshで再試行し、削除できるまで新Drawingを生成しない。
API欠落・例外はDCSログの `[DynamicTraining] MapOverlay: [ERROR]` へ記録し、既存ミッションの初期化・進行を止めない。成功時は描画数と基地名をログへ記録する。

## ミッション設定と検証範囲

2026-10-06に作業ツリーの `mission/Syria.miz`（現在は `mission/Persistent_and_Dynamic_FA-18C_Training.miz`）の `warehouses.airports` を読み取り、BLUEのIDは6 / 16 / 30 / 44であることを確認した。
DCS Syria `radio.lua` のairfield ID、MEの出撃route、同梱MOOSEのSyria名称を照合した結果は以下。

| ID | BLUE陸上基地 |
|---:|---|
| 6 | Beirut-Rafic Hariri |
| 16 | Incirlik |
| 30 | Ramat David |
| 44 | Akrotiri |

これは静的アーカイブ検査であり、DCS runtimeでの描画確認結果ではない。コードの対象リストではなく、現在設定の記録。
Tiyas（ID39）のBLUE化も名前リストの修正なしで対象となる。変更はMission Editorで行う。
現在の4基地をアーカイブ設定から入力する追加模擬確認では、基地ごとにCircle/Textが生成され合計8 Drawingとなった。

`scripts/Test-MapOverlay.lua` は18ケースでBLUE/RED/Neutral、Ship/FARP、複数ID、MOOSE allocator、再実行、所属変更、部分失敗、削除再試行、bundle初期化1回と周期非描画、青色と南1,000 mの文字オフセットを検証する。
既存7 Luaスイートは変更せず回帰確認する。BUILD/SYNCで結合と既存ZIP entry保持も確認する。
実行方法・DCS手動確認（MAN-48/49）は [TESTING.md](TESTING.md) を参照。
Lua全293ケース、BUILD2、SYNC3が通過。Build・実ミッションSync・Checkも成功し、同期前backupとの比較でDynamicTraining.lua以外の7 ZIP entryを保持した。DCS内確認は未実施。

ユーザー提供のIncirlikのスクリーンショットではDrawing文字と通常基地名が重なることを確認し、南1,000 mオフセットで修正した。その後ユーザーから見やすくなったとの報告あり（対象版・地図倍率は未記録）。
黒文字8枚を重ねる疑似縁取りを試したが、ユーザー提供のBeirutのDCS画像で黒文字が分離して表示されることを確認し、ユーザー指示で撤回した。現在はオフセット付き青文字1枚に戻している。全DCS手動ケースの合格とは扱わない。

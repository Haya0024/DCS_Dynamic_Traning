# ミッション同梱ニーボード

`BLUE_AIRFIELDS_AND_CARRIER_SYRIA.png` が現在の採用画像。空港と空母を別表にし、空母の座標・LINK 4・下部の説明文は載せない。`BLUE_AIRFIELDS_SYRIA.png` と `BLUE_AIRFIELDS_SYRIA_2x.png` は空港だけの旧版で、ミッションには同梱しない。

実ミッション `mission/Persistent_and_Dynamic_FA-18C_Training.miz` 内の `KNEEBOARD/IMAGES/01_BLUE_AIRFIELDS_AND_CARRIER_SYRIA.png` に同じPNGを格納する。ミッション同梱のため参加者ごとのSaved Gamesへの配置は不要。更新後はMEでファイルを開き直し、実行中のミッションには再開始で反映する。

2026-10-12、ユーザーの明示依頼により画像を追加。既存のmission設定・トリガー・リソース対応表・埋め込みLua・その他ZIPエントリは変更しない。画像の追加前を `.miz.kneeboard.bak` に保存する。`Sync-Mission.ps1` は既存Lua以外を維持するので、画像の更新はLua同期とは別に行う。

空港座標は[pydcsのSyria空港基準点](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/airports.py)と[投影定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/projection.py)からDDMへ換算。ATC・TACAN・VORはこのPCのDCS Syriaの `radio.lua` / `beacons.lua`、空母の無線・TACAN・ICLSは実.mizから確認した。画像は静的な参照資料であり、MEで設定を変更した場合は画像も合わせて更新する。

同梱先の形式は[OpenKneeboardのDCS連携仕様](https://openkneeboard.com/features/dcs/#the-dcs-mission-tab)を参照。DCS内の実表示は確認待ち。

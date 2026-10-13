# ミッション同梱ニーボード

`BLUE_AIRFIELDS_AND_CARRIER_SYRIA.png` が現在の採用画像。空港・空母・給油機の3表に分け、空母と給油機の座標・LINK 4・下部の説明文は載せない。`BLUE_AIRFIELDS_SYRIA.png` と `BLUE_AIRFIELDS_SYRIA_2x.png` は空港だけの旧版で、ミッションには同梱しない。

給油機の表は `BLUE_TANKER_NORTH` のTexaco 1-1（251.10 MHz AM・31Y/TEX）と `BLUE_TANKER_SOUTH` のArco 1-1（251.20 MHz AM・32Y/ARC）。列は給油機・無線周波数・TACANの3つで、高度・速度はユーザー指定により掲載しない。両機とも実.mizのKC-135 MPRSから表示値を確認した。

実ミッション `mission/Persistent_and_Dynamic_FA-18C_Training.miz` 内の `KNEEBOARD/IMAGES/01_BLUE_AIRFIELDS_AND_CARRIER_SYRIA.png` に同じPNGを格納する。ミッション同梱のため参加者ごとのSaved Gamesへの配置は不要。更新後はMEでファイルを開き直し、実行中のミッションには再開始で反映する。

MEを開いたまま外部から.mizを更新した場合は、次の保存前に更新版を開き直す。整合性確認では `Sync-Mission.ps1 -Check` に加え、同梱PNGと編集元の一致、ZIP CRC、SOLO/MP2・テンプレート・Zone・支援機設定を確認する。給油機追加時の画像更新直前は `.miz.kneeboard-update.bak` に保存し、画像以外のZIPエントリを維持する。

2026-10-12、ユーザーの明示依頼により画像を追加。既存のmission設定・トリガー・リソース対応表・埋め込みLua・その他ZIPエントリは変更しない。画像の追加前を `.miz.kneeboard.bak` に保存する。`Sync-Mission.ps1` は既存Lua以外を維持するので、画像の更新はLua同期とは別に行う。

空港座標は[pydcsのSyria空港基準点](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/airports.py)と[投影定義](https://github.com/pydcs/dcs/blob/master/dcs/terrain/syria/projection.py)からDDMへ換算。ATC・TACAN・VORはこのPCのDCS Syriaの `radio.lua` / `beacons.lua`、空母と給油機の無線・航法・飛行設定は実.mizから確認した。画像は静的な参照資料であり、MEで設定を変更した場合は画像も合わせて更新する。

同梱先の形式は[OpenKneeboardのDCS連携仕様](https://openkneeboard.com/features/dcs/#the-dcs-mission-tab)を参照。DCS内の実表示は確認待ち。

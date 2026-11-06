# BVE調査の根拠と制限

## 最終集計

最終メタデータ台帳は路線69件・車両68件です。各カテゴリ内のアーカイブSHA-256重複はなく、カテゴリ間で10アーカイブが重複するため、全体のユニークアーカイブハッシュ数は127です。100件ずつの目標に対して路線31件・車両32件不足しています。[CSV](BVE/inventory_final.csv)、[JSON](BVE/inventory_final.json)、[集計JSON](BVE/summary_final.json)に台帳とハッシュを記録し、63路線・58車両だった更新前の基準データは[履歴スナップショット](BVE/additional/inventory_baseline_63_58.csv)に保管しています。

直近2ラウンドで路線6件・車両10件、計16カテゴリレコード（13アーカイブ）を追加しました。追加分の8レコードは非商用ライセンスまたは非商用条件です。残りも許諾が作者オリジナルの一部・特定フォルダ・設定テキストに限られる、または第三者素材の条件が別途必要です。いずれもアプリ収録許可とはみなしません。全ての条件・出典は[最終報告](BVE/additional/report.md)と[個別台帳](BVE/inventory_final.csv)を確認してください。

## 形式仕様と権利判断の一次資料

- [BVE Map形式](http://bvets.net/en/edit/formats/route/map.html)と[Station形式](http://bvets.net/en/edit/formats/route/station.html)
- [openBVE CSV路線形式](https://openbve-project.net/documentation/HTML/route_csv.html)、[train.dat](https://openbve-project.net/documentation/HTML/train_train_dat.html)、[train sound.cfg](https://openbve-project.net/documentation/HTML/train_sound_cfg.html)
- [BVE制作・公開ガイドライン](https://bvets.net/jp/edit/guidelines/) — 他者データ利用時に作者への連絡・許可を案内しています。
- 最新の候補別の記録は[Round 3許諾・範囲メモ](BVE/additional/source_screening_round3.md)と[Round 4除外記録](BVE/additional/source_screening_round4.md)を参照してください。

明示ライセンスがある場合でも、アーカイブ内の全音声・画像・プラグイン・モデルや第三者依存物に適用されるとは限りません。CC BY-NCや非商用条件のデータは販売予定アプリへ利用できず、CC BYやMIT等も作者の指定した範囲に限られる場合があります。ラベルを見てパッケージ全体の再利用許可を推定しないでください。

## 取得・調査範囲の限界

新規13アーカイブから541個の路線・車両テキスト設定をメモリ上で静的に読みました。設定本文は保存していません。Random Map路線は該当297ファイル中250ファイルをサンプル検査しました。README・利用条件を先に確認し、許諾の対象とされた設定のみを読むよう範囲を限定しています。

[SGTrainsの3候補](https://sgtrains.com/bve-ccl-acw.html)等は公開OneDriveリンクがHTTP 403で取得できず、検査・件数登録していません。[Osaka Metro Tanimachi Line](https://tetsudo-1998.jimdofree.com/bve5/bve5%E8%B7%AF%E7%B7%9A%E3%83%87%E3%83%BC%E3%82%BF/)は同梱READMEに「BVE以外の目的での利用は禁止」とあるため、READMEとファイル一覧メタデータ以外を確認せず、設定本文を読まず、一時アーカイブを削除して除外しました。詳細は[Round 4記録](BVE/additional/source_screening_round4.md)にあります。

今回の範囲では、BVEスクリプト、マクロ、プラグイン、実行ファイル、バイナリを読まず・実行せず、音声を再生・読取りせず、画像・テクスチャ・3Dモデルも開いていません。元の配布アーカイブやその素材をアプリへコピーしていません。元アーカイブは配布ZIPにも含めていません。

**別手順の音声レビュー監査注記:** 以前の音声サンプルレビューでは独立した手順逸脱が報告されています。この追加調査は別の手順・対象であり、そのレビューの逸脱を是正・再検証・認証するものではありません。今回の541件の設定テキスト確認で音声を読んだり再生したりしていません。

これらの資料はBVE互換実装や再利用許可ではなく、独立した架空iOSシミュレーターのデータ設計に関する調査記録です。BVEデータ・素材・コードはアプリへ組み込みません。

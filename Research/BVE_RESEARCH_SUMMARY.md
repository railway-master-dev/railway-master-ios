# BVE路線・車両データ調査の結論

## 確定した在庫は69路線・68車両

最終のメタデータ台帳は、路線69パッケージ、車両68パッケージです。カテゴリ内のアーカイブSHA-256重複はなく、カテゴリ間では同じアーカイブが10組あり、全体のユニークアーカイブハッシュ数は127です。100件ずつの目標まで、路線31件・車両32件足りません。

直近2ラウンドでは、以前の63路線・58車両の台帳に路線6件・車両10件を追加しました。カテゴリ別16レコードは13アーカイブに対応します。候補調査を終え、条件不明・アクセス拒否・用途禁止の作品を数へ足さず、この件数で確定しています。[最終CSV](BVE/inventory_final.csv)、[JSON台帳](BVE/inventory_final.json)、[集計JSON](BVE/summary_final.json)を参照してください。63/58の基準台帳も[履歴スナップショット](BVE/additional/inventory_baseline_63_58.csv)として残しています。

## 追加分の出典と権利範囲

- [HKTSS LRT-705](https://github.com/HKTSS/LRT-705-OpenBVE)の路線1件と[LRV P3](https://github.com/HKTSS/LRV-P3)、[LRV P4](https://github.com/HKTSS/LRV-P4)の車両2件。CC BY-NC-SA 4.0 / CC BY-NC 4.0で非商用の参照のみ。LRT-705内のOpenStreetMap関連物や素材は別条件未確認のため除外。
- [CRH1A-A](https://github.com/xiangao0904/openbve-crh1a-a)、[MTR M-train](https://github.com/soumasandesu/openbve-hk-mtr-m)、[C751C](https://github.com/seetowsh/C751C)の車両3件。CRH1A-Aは非商用条件、C751CはCC BY-NC 4.0。M-trainはCC BY 4.0表記がありますが、WAVは開かず、アプリへの収録許可とも扱っていません。
- [Chuo Rapid Line](https://github.com/aoisupersix/bve5-chuorapidline)と[Shiomi Line](https://github.com/masonzeng702550/bve5-shiomi-line)の路線2件。CC BY-NC 4.0の範囲内で非商用の参照のみ。借用素材は別条件です。
- [Gensokyo Railway](https://github.com/NewSapporoNingyo/BVE-Gensokyo-Railway)の路線1件と同梱E127系車両データ1件。MITは作者オリジナルの路線内容に限られ、多数の借用素材は再配布禁止。E127系はCC BY-NC 2.1 JPで、いずれも商用アプリへ転用できる根拠とはしません。
- [bve-random-map](https://github.com/magicant/bve-random-map)と[bve-autopilot-scenario](https://github.com/magicant/bve-autopilot-scenario)の路線2件・試験車両2件。CC BY 4.0表記の対象となる設定テキストだけを調べました。DLL、パネル、音声、画像、外部依存は読まず、実行もしていません。
- [BveDcTrainPack](https://github.com/mikangogo/BveDcTrainPack)と[p4ken empty](https://github.com/p4ken/empty)の車両設定2件。前者は`Vehicle/*`内の自由な複製・頒布許可に範囲を限定し、Notch/Panel/Plugin/Sound等は除外。後者は設定テンプレートの自由利用条件がありますが、標準ライセンスがなく、アプリ利用は未承認です。

新規16レコードのうち8件は非商用ライセンスまたは非商用条件です。残りも許可が特定の作者作成部分・フォルダ・設定に限られ、第三者素材・外部依存の権利までまとめて解決するものではありません。調査したBVEパッケージをアプリへ収録する承認はありません。BVEデータやアセットはアプリへコピーせず、プロジェクト内には調査用メタデータだけを保持します。

## 除外した候補と静的確認の境界

[SGTrains Circle Line](https://sgtrains.com/bve-ccl-acw.html)、[C830](https://www.sgtrains.com/bve-c830.html)、[C830C](https://www.sgtrains.com/bve-c830c.html)は配布リンクが3件ともHTTP 403で、第三者素材の条件も確認できず、件数から除外しました。[Osaka Metro Tanimachi Line](https://tetsudo-1998.jimdofree.com/bve5/bve5%E8%B7%AF%E7%B7%9A%E3%83%87%E3%83%BC%E3%82%BF/)はREADMEがBVE外利用を禁止しています。READMEとファイル一覧メタデータ以外は確認せず、設定本文を読まず、取得した一時アーカイブは削除しました。詳しい理由は[Round 4除外記録](BVE/additional/source_screening_round4.md)にあります。

新規13アーカイブから541個のテキスト設定をメモリ上で静的に確認しました。本文は保存せず、Random Map路線は該当297件中250件をサンプル検査しています。BVEのコード、スクリプト、マクロ、プラグイン、実行ファイルは読まず・実行せず、音声・画像・テクスチャ・3Dモデルも開いていません。[追加調査報告](BVE/additional/report.md)、[Round 3の条件・範囲メモ](BVE/additional/source_screening_round3.md)、[設定検査メタデータ](BVE/additional/text_config_inspection_round3.json)に記録しています。

**監査注記:** 以前の音声サンプルレビューは別の手順で行われ、独立した手順逸脱が報告されています。今回の台帳更新はその別レビューを是正・再検証・認証するものではありません。今回の設定テキスト調査では音声を読まず、再生していません。

## 関連資料

- [出典・権利・調査限界](BVE_RESEARCH_SOURCES_AND_LIMITATIONS.md)
- [最終CSV台帳](BVE/inventory_final.csv) / [JSON台帳](BVE/inventory_final.json) / [集計](BVE/summary_final.json)
- [最終調査報告](BVE/additional/report.md)
- [更新CSVの基準63/58スナップショット](BVE/additional/inventory_baseline_63_58.csv)
- [除外候補記録](BVE/additional/source_screening_round4.md)

BVEの配布アーカイブ、実行コード、プラグイン、音声、画像、テクスチャ、3Dモデルは同梱していません。これらの調査はデータ再利用の許諾やアプリへの組込み許可を意味しません。

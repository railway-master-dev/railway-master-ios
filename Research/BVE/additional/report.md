# BVE路線・車両の参照調査：更新結果

## 結論

現行の許諾・取得・カテゴリ別SHA-256確認済み台帳は**路線69/100、車両68/100**です。目標まで路線31件・車両32件不足しています。直近2ラウンドで、基準の63路線・58車両に対して**新たに路線6件・車両10件**を追加しました。アクセス拒否・用途禁止・条件不明の候補は数に加えていません。

同一アーカイブが路線と車両の両方を含む場合は、SHA-256重複をカテゴリごとに排除して各カテゴリに1件ずつ計上しています。今回追加した16カテゴリ記録は13アーカイブに対応します。追加候補の調査で条件を満たす候補を確認できなかったため、今回は**69路線・68車両で打ち切り**、不足分を許諾不明や取得不可の作品で埋めていません。

## 新規追加したデータ

| 配布元 | 追加 | 条件の要点 |
|---|---:|---|
| [HKTSS LRT-705](https://github.com/HKTSS/LRT-705-OpenBVE)、[LRV P3](https://github.com/HKTSS/LRV-P3)、[LRV P4](https://github.com/HKTSS/LRV-P4) | 路線1・車両2 | CC BY-NC-SA 4.0 / CC BY-NC 4.0。参照は非商用に限られ、販売アプリには不適合。LRT-705のOpenStreetMap関連物は別条件未確認のため除外。 |
| [CRH1A-A](https://github.com/xiangao0904/openbve-crh1a-a)、[MTR M-train](https://github.com/soumasandesu/openbve-hk-mtr-m)、[C751C](https://github.com/seetowsh/C751C) | 車両3 | CRH1A-Aは非商用条件、C751CはCC BY-NC 4.0。MTR M-trainはCC BY 4.0ですが、音声素材は確認せず、アプリ収録許可とも扱っていません。 |
| [Chuo Rapid Line](https://github.com/aoisupersix/bve5-chuorapidline)、[Shiomi Line](https://github.com/masonzeng702550/bve5-shiomi-line) | 路線2 | CC BY-NC 4.0。非商用の参照のみ。借用素材は別条件。 |
| [Gensokyo Railway](https://github.com/NewSapporoNingyo/BVE-Gensokyo-Railway) | 路線1・車両1 | MITは作者オリジナルの路線内容に限られます。利用者ガイドは多くの借用素材について再配布禁止と明記するため除外。同梱E127系データはCC BY-NC 2.1 JPで商用利用不可。 |
| [bve-random-map](https://github.com/magicant/bve-random-map)、[bve-autopilot-scenario](https://github.com/magicant/bve-autopilot-scenario) | 路線2・試験車両2 | CC BY 4.0の表記を確認。ATS/自動運転DLL・外部依存物は読まず実行せず、別条件の素材も除外。 |
| [BveDcTrainPack](https://github.com/mikangogo/BveDcTrainPack)、[p4ken empty](https://github.com/p4ken/empty) | 車両2 | BveDcTrainPackは`Vehicle/*`の自由な複製・頒布許可に限定し、Notch/Panel/Plugin/Sound等は除外。p4ken emptyは設定テンプレートで、READMEに自由な使用・改変・頒布許可がありますが、標準ライセンスが確認できないためアプリ収録は未承認です。 |

追加16記録のうち8件は非商用ライセンス／条件で、販売アプリには使えません。残る8件も許諾は作者の特定部分・フォルダ等に限られ、第三者素材や外部依存を一括でクリアするものではありません。今回の調査でアプリへの収録を承認したパッケージはありません。

## 追加探索で除外した候補

[SGTrains Circle Line](https://sgtrains.com/bve-ccl-acw.html)、[C830](https://www.sgtrains.com/bve-c830.html)、[C830C](https://sgtrains.com/bve-c830c.html)はCC BY-ND 3.0 Singaporeの表記を確認しましたが、公開OneDriveリンクが3件ともHTTP 403でした。改変物の再配布には使えず、第三者素材の権利もページだけでは確認できません。アーカイブの取得可能性を確認できないため、検査・件数登録をしていません。

[Osaka Metro Tanimachi Line](https://tetsudo-1998.jimdofree.com/bve5/bve5%E8%B7%AF%E7%B7%9A%E3%83%87%E3%83%BC%E3%82%BF/)は配布ページに限定的なOpenBVE検証例外があり、アーカイブ自体も取得可能でした。しかし同梱READMEは「BVE以外の目的での利用は禁止」と明記しています。外部研究に使う許可とは扱えないため、READMEとファイル一覧メタデータ以外は見ず、設定本文の検査を止め、取得アーカイブを削除して件数から除外しました。

先行調査では、BVEStationの路線・車両ページ125件を含む配布ページ142件を確認し、個別条件を確認できたのは3件でした。配布カタログへの掲載だけでは作者の許可と見なせず、第三者素材の条件が不明な作品も除外しています。[BVE公式ガイドライン](https://bvets.net/jp/edit/guidelines/)も他者データ利用時に作者への連絡・許可を案内しています。大阪地下鉄の一部候補は、許可がゲーム内検証・デバッグに限定されており、外部参照には含めていません。

## 静的検査と安全境界

新規13アーカイブから、**541個の路線・車両テキスト設定**をメモリ上で静的に読みました。設定本文は保存していません。Random Map路線は該当297ファイル中250ファイルをサンプル検査しました。アーカイブのREADME・条件を先に確認し、許諾の対象となる設定だけに検査範囲を限定しています。

BVE側のスクリプト、マクロ、プラグイン、実行ファイル、バイナリは実行も読取りもしていません。音声は再生・読取りなし、画像・テクスチャ・モデルも開いていません。BVEの設定・素材をアプリへコピーせず、アプリや他の作業領域も変更していません。

## ファイル

- [更新台帳CSV（69路線・68車両、カテゴリ別SHA-256重複排除）](inventory_updated.csv)
- [更新前の基準台帳スナップショット（63路線・58車両）](inventory_baseline_63_58.csv)
- [追加分の許諾・範囲メモ](source_screening_round3.md)
- [アクセス拒否・用途禁止による除外記録](source_screening_round4.md)
- [Round 3の静的設定検査JSON](text_config_inspection_round3.json)
- [Round 2の車両設定検査JSON](vehicle_config_inspection_round2.json)
- [HKTSS LRT-705の前処理・路線検査記録](hktss_lrt705_preflight.json)


## 独立した音声レビューの監査注記

以前の音声サンプルレビューは本件とは別の手順で実施され、独立した手順逸脱が報告されています。この更新はその別レビューを是正・再検証・認証するものではありません。今回のテキスト設定調査では音声を読まず、再生していません。

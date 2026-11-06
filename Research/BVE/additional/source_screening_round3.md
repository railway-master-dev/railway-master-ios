# BVE追加候補：Round 2–3の許諾・範囲メモ

## 結果

当時の基準台帳（63路線・58車両）に対し、直近2ラウンドで**新規6路線・10車両データ**を追加できる候補を確認しました。新規アーカイブは13件、カテゴリ別レコードは16件です（路線と車両を同梱するアーカイブは、各カテゴリで1件ずつ数えています）。カテゴリ内SHA-256重複はなく、更新後の合計は**69路線・68車両**。100件まで路線31件・車両32件不足です。

新規分では、**541個の路線・車両テキスト設定**をメモリ上で静的に読み、本文は保存していません。Random Map路線は該当297ファイル中、上限250ファイルをサンプル検査しました。

## 新規に追加したデータと許諾範囲

| データ | 条件と参照範囲 | 静的検査 |
|---|---|---:|
| [HKTSS MTR Light Rail 705](https://github.com/HKTSS/LRT-705-OpenBVE) 路線 | READMEにCC BY-NC-SA 4.0。非商用の参照のみ。OpenStreetMap関連フォルダ等は別条件未確認のため除外。 | 路線CSV 1 |
| [HKTSS LRV P3](https://github.com/HKTSS/LRV-P3) 車両 | READMEのCC BY-NC 4.0。非商用の参照のみ。 | 車両設定16 |
| [HKTSS LRV P4](https://github.com/HKTSS/LRV-P4) 車両 | READMEのCC BY-NC 4.0。非商用の参照のみ。 | 車両設定10 |
| [OpenBVE CRH1A-A](https://github.com/xiangao0904/openbve-crh1a-a) 車両 | READMEは改変・再公開を非商用に限る。`train.dat`と走行音には第三者クレジットあり。 | 車両設定4 |
| [Hong Kong MTR M-train](https://github.com/soumasandesu/openbve-hk-mtr-m) 車両 | ルートLICENSEはCC BY 4.0。WAVは再生・読取りせず、アプリ収録には使わない。 | 車両設定2 |
| [C751C](https://github.com/seetowsh/C751C) 車両 | ルートLICENSE.mdのCC BY-NC 4.0。非商用の参照のみ。 | 車両設定5 |
| [BVE5 Chuo Rapid Line](https://github.com/aoisupersix/bve5-chuorapidline) 路線 | CC BY-NC 4.0。非商用の参照のみ。 | 路線設定6 |
| [Gensokyo Railway](https://github.com/NewSapporoNingyo/BVE-Gensokyo-Railway) 路線 | MITは作者のオリジナル路線内容に限る。利用者ガイドは、多数の借用素材について再配布禁止と明記するため、第三者素材は全て除外。 | 路線設定91 |
| 同リポジトリのE127系データ | README記載のCC BY-NC 2.1 JP。BVE Workshop由来・改変と記載されるため、非商用の参照のみ。 | 車両設定16 |
| [Shiomi Line](https://github.com/masonzeng702550/bve5-shiomi-line) 路線 | 作者のオリジナル部分はCC BY-NC 4.0。借用素材は別条件。非商用の参照のみ。 | 路線設定27 |
| [bve-random-map](https://github.com/magicant/bve-random-map) 路線・clearcar2車両 | CC BY 4.0表記。ATS DLL、パネルその他の素材・外部依存は除外。各カテゴリで同じアーカイブSHAを別々に管理。 | 路線250/297、車両15 |
| [BveDcTrainPack](https://github.com/mikangogo/BveDcTrainPack) 車両集 | LICENSE.mdは`Vehicle/*`の自由な複製・頒布を許可。他のNotch/Panel/Plugin/Sound等は別条件で参照専用・制限あり。検査はVehicle内の設定のみ。 | 車両設定20 |
| [bve-autopilot-scenario](https://github.com/magicant/bve-autopilot-scenario) 路線・clearcar車両 | CC BY 4.0表記。プラグインDLLやNagoya_Common/Keisei等の外部依存は除外。各カテゴリで同じアーカイブSHAを別々に管理。 | 路線設定60、車両設定12 |
| [p4ken empty](https://github.com/p4ken/empty) 車両設定テンプレート | READMEは自由な使用・改変・複製・頒布を許可するが、標準ライセンスファイルは確認できず、商用アプリ利用は未承認扱い。完全なモデル・音声車両パッケージではない。 | 設定6 |

## 商用アプリとの境界

CC BY-NCまたは非商用条件の新規データは、販売予定のアプリには収録できず、参照専用です。CC BY、MIT、自由頒布条件のデータも、ライセンスがカバーする作者オリジナル部分に限られ、第三者素材や依存物の権利まで一括で許可するものではありません。今回の作業指示に従い、アプリへのBVE設定・音声・モデル・画像等のコピーは一切していません。

ZIPの構成・README・ライセンスを先に確認し、許諾範囲内のテキスト設定だけを静的に読取りました。BVE側のスクリプト、マクロ、プラグイン、実行ファイル、バイナリは実行も読取りもしておらず、音声は再生・読取りなし、画像・テクスチャ・モデルも開いていません。設定本文を保存したりアプリや別作業領域を変更したりしていません。

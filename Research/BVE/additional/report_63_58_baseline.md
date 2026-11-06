# BVE追加調査：許諾を確認できたパッケージの結果

## 結論

既存の51路線・57車両に、静的確認できた**路線12件・車両1件**を追加しました。更新後は**路線63/100、車両58/100**で、目標までは路線37件・車両42件不足しています。SHA-256でカテゴリ別に重複排除し、路線・車両の両方に該当する既存アーカイブ7件を含めた全体のユニーク数は**114アーカイブ**です。

## 追加したパッケージ

| 配布元 | 路線 | 車両 | 条件の要点 |
|---|---:|---:|---|
| [Hamatetsu](https://gitlab.com/hamatetsu_train/bvescenarios/-/blob/main/README.md) | 4 | 0 | READMEに参照利用の許可があります。ただし、借用ストラクチャや共通素材は別権利のため再利用していません。しぞーか本線 [S01](https://gitlab.com/hamatetsu_train/bvescenarios/-/tree/S01_Tokaido)、身延線 [S03](https://gitlab.com/hamatetsu_train/bvescenarios/-/tree/S03_Minobu)、沼津港線 [S98](https://gitlab.com/hamatetsu_train/bvescenarios/-/tree/S98_Numazu)、清水港線 [S99](https://gitlab.com/hamatetsu_train/bvescenarios/-/tree/S99_Shimizu)。 |
| [shtr-m](https://shtr-m.net/bve/read_me.html) | 6 | 0 | MapのInclude・公開と一部素材の参照に限った条件で、パッケージ全体の再利用許可ではありません。確認したのは[銀座線2系統](https://shtr-m.net/bve/ginza.html)、[銀座線6系統](https://shtr-m.net/bve/ginza6.html)、[半蔵門線](https://shtr-m.net/bve/hanzomon.html)、[副都心線](https://shtr-m.net/bve/fukutoshin.html)、[東京モノレール](https://shtr-m.net/bve/tmk.html)、[広島電鉄宮島線](https://shtr-m.net/bve/hrd.html)です。 |
| [BVEStation](https://www.bvestation.com/) | 2 | 1 | [NYCTA G Line](https://www.bvestation.com/download/5/)、[FIRR](https://www.bvestation.com/download/52/)、[R46](https://www.bvestation.com/download/17/)のページ／同梱説明に[CC BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/)の条件があります。非営利・表示・継承等の条件に加え、路線の一部オブジェクトは別著作権、他所での再ホスト／再梱包禁止とされています。R46はアーカイブSHA-256が配布ページ記載値と一致しました。 |
| **追加合計** | **12** | **1** | 内部参照の静的調査のみ。アプリへの収録許可とは扱っていません。 |

## 100件に届かない理由

BVEStationの142配布ページを調べ、路線・車両の対象125ページのうち、パッケージ単位の明示条件を確認できたのは3件でした。残りは許諾が見当たらない、カタログ自体のライセンスがアドオン本体に及ばない、第三者素材の条件が混在するなどの理由で除外しています。[BVE公式の公開ガイドライン](https://bvets.net/jp/edit/guidelines/)も、公開作品で他者データを使う際は作者への事前連絡・許可を案内しています。

[SGTrainsのCircle Line路線](https://www.sgtrains.com/bve-ccl-acw.html)、[C830](https://www.sgtrains.com/bve-c830.html)、[C830C](https://sgtrains.com/bve-c830c.html)は、ページ上のCC BY-ND 3.0 SG条件を確認しましたが、配布先のOneDrive共有リンクが3件ともHTTP 403となり、取得・検査できず件数に含めていません。大阪地下鉄7路線の候補は条件がOpenBVE内の検証・デバッグに限られており、今回の外部静的参照の許可とはみなしませんでした。shtr-mの京王競馬場線はページから直接アーカイブを確認できませんでした。

## 静的確認の範囲

追加13アーカイブを取得しSHA-256を照合したうえで、路線12件のMap/CSV定義164ファイルと、R46車両の設定22ファイルを静的に読みました。Readmeや条件を先に確認し、設定テキストの本文は保存していません。音声・画像・テクスチャ・3Dモデル・実行ファイル・プラグイン等の内容は開かず、実行・再生・コピーもしていません（SHA-256算出ではアーカイブ全体のバイト列を読み取りました）。設定特徴の集計はコマンド語の存在を示すもので、実行時の挙動検証ではありません。アプリや他の作業領域は変更していません。

## ファイル

全121行（既存108件＋追加13件）のSHA-256付き更新台帳は[更新インベントリCSV](inventory_updated.csv)です。取得状況・Readme確認の詳細は[パッケージ前処理JSON](package_preflight.json)、静的設定の検査結果は[テキスト設定検査JSON](text_config_inspection.json)、候補と除外根拠は[候補マニフェスト](candidate_manifest.json)にあります。

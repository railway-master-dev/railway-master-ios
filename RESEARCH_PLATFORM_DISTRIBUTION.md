# iOS App Store配信・日本向け価格の調査メモ

**確認日:** 2026-11-06（JST）

## App Storeでの配信

- Appleの[ベータ配信・リリース案内](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)では、登録端末、TestFlight、App Storeへの配信にApple Developer Programが必要で、Xcodeでアーカイブ・署名・アップロードを行う手順を案内しています。
- Apple Developer Programの[特典・会費案内](https://developer.apple.com/programs/whats-included/)は、年会費USD 99（利用可能な地域では現地通貨）を掲載しています。登録・本人確認等が必要です。
- Appleは[日本向けiOS変更](https://www.apple.com/newsroom/2025/12/apple-announces-changes-to-ios-in-japan/)を2025-12-17に発表し、新しい配信・決済機能をiOS 26.2から提供すると説明しています。

## 日本向けApp Storeの価格・手数料

Appleの[日本向けApp Store配信・ビジネス条件](https://developer.apple.com/support/app-distribution-in-japan/)には、次の料率が掲載されています。

- App Storeの販売手数料は、Small Business Program等の対象プログラム参加者の対象取引で**10%**、それ以外のデジタル商品・サービス販売で**21%**と記載されています。実際の適用区分・契約条件は、公開前にApp Store Connectで確認してください。
- Appleの別個の**5%決済処理料**は、同ページ上「Apple In-App Purchaseで処理される支払い」に適用される条件です。有料アプリのダウンロードにも一律で加算されると推定せず、商品・決済経路の該当契約を確認してください。
- Appleの[JPY価格ポイント表](https://www.apple.com/newsroom/pdfs/App-Store-Pricing-Update.pdf)には**¥5,000**が選択可能な価格点として含まれます。これは同表の¥500価格ステップ（掲載範囲¥400〜¥49,800）に含まれます。ストアフロントごとの表示や実際に選べる価格は、App Store Connectの最新選択肢に従ってください。
- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)は、既存開発者の前年の収益条件、新規開発者の資格、関連アカウントの合算・申告、登録手順を説明しています。参加・承認を確認せず10%が適用されるとは扱いません。

ここでは手取り、税、為替、返金、その他調整を含む収益計算や利益予測は行っていません。料率や契約は参加資格、取引種類、決済経路、税務、リリース時点のApple契約により異なり得るため、公開直前にApp Store Connectと有効な契約を確認してください。

## このプロジェクトのリリース確認境界

この環境にはXcode、iOS SDK、Apple署名・配信機能がなく、Xcode型チェック、iOSビルド、XCTest実行、Simulator/実機試験、発熱・性能計測、署名・App Store提出は未実施です。静的検査はこれらの代替ではありません。Apple Developer Programへの登録、価格設定、アプリ提出、購入・決済はこの調査では行っていません。

Google Playは過去に比較対象として調査されましたが、2026-11-05時点でこのプロジェクトはiOS継続方針です。Google Playの登録要件やAndroidターゲット条件は、本リリースの完了条件ではありません。

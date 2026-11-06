# 近鉄京都線・京都—大和西大寺 実路線参照データ

国土交通省の2025年度「国土数値情報（鉄道）N02-25」から、近鉄京都線の京都—大和西大寺間を別置きの調査用データとして抽出しました。52個の路線リンク線をつなぎ、26駅の公開駅線形を添えています。結合した地図上の参照線は約35.141 kmです。

**これは実際のレール中心線を測量したデータでも、運転シミュレーター用の完成路線でもありません。**公開された一般化線形の頂点間距離からローカルな参照chainageを計算したもので、線路長・営業キロ程・駅中心位置とは異なります。曲線半径、勾配、カント、速度制限、信号、閉そく、ホーム、分岐器、構造物、時刻表など、元データにない運転情報はすべて `UNKNOWN` です。

## ファイル

- `Data/route-package.json` — 出典ID・状態・確信度とUNKNOWN項目を含む機械可読パッケージ
- `Data/route_geometry.geojson` — 連続した参照線、各頂点の推定ローカルchainage、元の駅線形
- `Data/route_segments.geojson` — 抽出した52区間を順序付きで保持し、元データのレコード番号を記録
- `Data/source_manifest.json` — 取得日、URL、ライセンス、CRS、処理方法、データのハッシュ
- `QUALITY_REPORT.md` — 結果・精度上の注意・検証結果
- `LICENSES.md` — 必要な出典表示
- `Tools/build_route_package.py` — 固定ハッシュを確認してパッケージを再生成
- `Tools/validate_route_package.py` — データ品質と不明項目を自動検証
- `Tests/validation-report.json` — 実行済み検証の機械可読結果

## 再生成・検証

Python 3があれば、ビルド時に国交省のアーカイブを一時取得して抽出します。アーカイブのSHA-256が記録値と一致しない場合は中止します。

```bash
python3 Tools/build_route_package.py
python3 Tools/validate_route_package.py
```

元アーカイブは配布サイズを抑えるため同梱していません。ビルドスクリプトは一時領域へ公式ファイルを取得し、SHA-256を確認します。この参照データと検証資料は本プロジェクトの`Research/RealRouteExpansion/`に同梱しますが、iOSアプリ、既存70 km `PLACEHOLDER`路線、物理・信号・運行には接続しません。

[品質レポート](QUALITY_REPORT.md)と[出典・ライセンス](LICENSES.md)を参照してください。

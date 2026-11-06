# iOSへの安全な統合条件

## 現在できること

`Data/route-package.json` は既存 `RailwayRouteData.RoutePackage` を想定したJSONです。対象featureは16頂点の公開route-line 1件と、駅線形2件です。ルート表示は地図上の参照線としてのみ扱えます。座標をiOSの地図・ローカル座標系へ変換する場合は、入力の **JGD2011 / (B,L)** と変換方法を保持してください。

既存モデルによる読み込み例：

```swift
let package = try RoutePackageLoader.load(from: routePackageURL)
let report = RouteValidator.validate(package)
guard report.isStructurallyValid else {
    throw RouteDataError.invalid(report)
}
```

`Package.swift` と `Tests/RealRoutePackageTests.swift` は既存 `RailwayRouteData` をローカル依存としてテストする補助用です。アプリ本体のリソース、コード、既存workstreamは変更していません。

## 実線路・物理・運転設備には接続しない

`Track` は現在のroute-packageスキーマに線形を格納するための互換コンテナです。`trackID` に個別の物理線路があると確認した意味はなく、収録線形もレール中心線ではありません。したがって、現状のJSONを `TrainPhysics`、線路断面のレンダラー、速度・停止採点、信号・閉そく判定の入力にしないでください。

アプリ側では、以下のガードを守ってください。

- `route.extensions["org.cue.railway.dataCompleteness"].safeForPhysicsOrSignalling == false` の間は、走行物理・速度制限・信号・ホーム停車シミュレーションを無効のままにする。
- `speedRestrictions`, `signals`, `blocks` が空なのは「制限なし」「信号なし」ではなく「未調査」です。デフォルト速度や架空の信号で埋めない。
- 曲線半径・カント・勾配・軌間・線路本数・駅中心・ホーム寸法・停止位置が `UNKNOWN` のままなら、既存のplaceholder/default値を実データとして流用しない。
- route-lineの粗い頂点間隔（最大約230.8 m）から、曲線半径・平滑化した線路・複線間隔・レール高を推定しない。
- 高架化事業の存在だけから個々の橋梁・桁・橋脚の位置や寸法を生成しない。

## 物理統合を開く前に必要な追加データ

運転可能な実データへ進む場合は、少なくとも個別線路とそのchainage基準、測量された線形、縦断勾配・レール標高、カント、速度制限と適用方向、分岐器、閉そく・信号・ATS、駅のホーム・停止位置、構造物と有効範囲を、権利条件が確認できる一次資料から別途収集してください。各値の `VERIFIED` / `MEASURED` / `ESTIMATED` / `UNKNOWN`、confidence、誤差、出典、取得日を値単位で保存し、物理統合はその後に別レビューしてください。

# 鉄道シミュレーター向け3D/PBR素材 — 商用利用とライセンス条件

## 先に結論

無料で使える候補では、**Kenney Train Kit** の汎用線路モデルと **ambientCG Rails 001** の狭軌レール表面材が鉄道シーンに直接役立ちます。どちらも公式ページで **CC0 1.0** が確認でき、商用利用・改変・アプリ同梱が可能で、クレジットは必須ではありません。ただし、日本の狭軌 **1,067 mm** や特定車両・運転台に合う寸法・形状は確認できていません。実線路・車両の再現データとしては扱わず、独自の形状と実物資料で合わせる必要があります。

今回は素材を購入・ダウンロード・アプリへ同梱していません。許諾未確認のBVE素材や第三者モデルのコピーもしていません。**フォトリアル化や実機動作が達成されたという意味ではありません。**

## 無償で試せる候補

### 1. Kenney Train Kit — 汎用線路モデル

[公式資産ページ](https://kenney.nl/assets/train-kit) は3DのTrain Kitとして線路パーツを掲載し、v1.1でtracksを追加したと案内しています。ファイル形式や軌間、寸法はページで確認できないため、取得前に配布ZIP内の形式と実寸スケールを調べ、ゲーム側に取り込めるかを確認してください。日本の狭軌や日本型車両に適合するとの記載はありません。

**ライセンス：CC0 1.0 Universal。** Kenneyの[サポートページ](https://kenney.nl/support)はゲーム素材がCC0で、商用プロジェクトを含め利用できること、クレジット不要であることを明記しています。CC0 1.0は著作権等を可能な範囲で放棄し、それが有効でない範囲では無償で幅広い利用を認める許諾を補います。商用利用、改変、アプリへの同梱・配布が可能で、表示・継承条件はありません。CC0が商標や別の第三者権利まで処理するわけではなく、保証もありません。Kenneyのロゴを素材の出所表示に流用したり、Kenneyの推薦を受けたように見せたりしないでください。

**位置づけ：** 無料の線路形状の土台として推奨。日本型の軌道へ使うなら軌間・寸法・分岐器等を確認し、必要に応じて調整すること。車両や運転台は含みません。

### 2. ambientCG Rails 001 — 狭軌レールの表面材

[公式資産ページ](https://ambientcg.com/view?id=Rails001) は “The rails of a narrow gauge railway.” と説明するPBR表面素材です。表面材の寸法は約1.25m × 1.25mと掲載されています。狭軌を題材にする線路表面へ使えますが、レールの断面・軌間・線路ジオメトリは提供しません。また日本の特定規格や実車との一致は確認できていません。

**ライセンス：CC0 1.0 Universal。** [ambientCG公式ライセンス](https://docs.ambientcg.com/license/)は全資産がCC0で、商用利用、改変、配布、ゲーム等への元ファイル同梱が許され、許可申請やクレジットは不要と明記しています。改変物をCC0にする義務もありません。CC0は商標・特許等を許諾せず、権利状態の包括的保証もしない点に注意してください。任意クレジット例は、公式例に沿って「Created using Rails 001 from ambientCG.com, licensed under the Creative Commons CC0 1.0 Universal License.」です。

ページは1K/2K/4K/8KのJPG・PNG ZIPを案内しています。8K PNG一式はページ表示で850MBなので、そのままアプリへ入れるのではなく必要なマップと解像度に絞ってください。iOS向けの形式変換・圧縮、色空間、法線マップの向き、メモリ量は利用するシェーダーと実機で確認が必要です。

**位置づけ：** 狭軌レール表面の無料候補として推奨。線路形状は独自の手続き生成メッシュまたは別途権利確認済みモデルで用意してください。

### 3. Poly Haven Gravel Embedded Concrete — ホーム・舗装用の汎用材

[公式資産ページ](https://polyhaven.com/a/gravel_embedded_concrete) の “Gravel Embedded Concrete” は砂利が埋め込まれたコンクリートのPBR素材で、ホームや線路脇の硬化面、舗装に利用できます。2m幅の表面素材で、砕石バラストや線路・車両モデルではありません。作者はCharlotte Baglioniです。

**ライセンス：CC0 1.0 Universal。** [Poly Haven公式ライセンス](https://polyhaven.com/license)は全アセットをCC0としており、商用利用・改変・再配布・アプリ同梱が可能、クレジットは不要としています。改変物にCC0を適用する義務やソース公開義務もありません。任意表示例：「Gravel Embedded Concrete — Charlotte Baglioni / Poly Haven（CC0）」。CC0の対象外となる第三者の権利まで保証されるわけではありません。

資産ページは複数のPBRマップと1K/2K/4K/8Kを掲載しています。必要な解像度・マップに絞って、iOS用テクスチャ圧縮と実機メモリを確認してください。

**位置づけ：** 汎用のコンクリート面には推奨。鉄道固有の形状の代替にはなりません。

## 有料または条件の重いモデル

### 4. Sketchfab “Steam Locomotive Train Engine” — CC BY 4.0

[モデルページ](https://sketchfab.com/3d-models/steam-locomotive-train-engine-faf1af6759174e0f984872ef317a181d) の作者はucagariで、ページはダウンロード可能・“CC Attribution” と表示しています。Sketchfabの[ライセンス案内](https://sketchfab.com/licenses)および[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)を照合すると、商用利用と改変は可能ですが、**作品名・作者・作品ページへのリンク・ライセンスへのリンク**を示し、変更した場合は変更を明示する必要があります。例：「Steam Locomotive Train Engine — ucagari（Sketchfab）／CC BY 4.0。モデルを軽量化し、スケールを調整。原作品：[モデルページ](https://sketchfab.com/3d-models/steam-locomotive-train-engine-faf1af6759174e0f984872ef317a181d) ／[ライセンス](https://creativecommons.org/licenses/by/4.0/)」。改変してもCC BYのクレジット条件は残ります。

ページ表示は約1.3M triangles・672.7k verticesで、iPhone向けには重い規模です。日本の狭軌・日本型車両・運転台の再現は確認できず、蒸気機関車の汎用背景モデル候補にとどまります。CC BYは再利用を許すため、アプリの規約や技術的保護でCC BY素材の再利用権を妨げない配布方法になっているか確認が必要です。対象権利は著作権等であり、第三者の商標等を別途許諾するものではありません。

**位置づけ：** 商用利用は可能ですが、車両の用途適合・ポリゴン数・クレジットと再利用権の扱いから、今回の主役車両としては推奨しません。

### 5. TurboSquid “Japan Train subway Jr series” — 有料Standard License

[商品ページ](https://www.turbosquid.com/3d-models/japan-train-subway-jr-series-model-1896854) は Product ID 1896854、表示価格$35、Standard Licenseの日本の地下鉄風モデルを掲載します。[公式ライセンス](https://www.turbosquid.com/licensing)のStandard Licenseは、購入者に対して非独占・全世界・永続の利用許諾を与え、ゲーム・シミュレーション等のCreationでの商用利用を認めます。一般の有償購入について作者クレジットは必須とはされていません。作者本人が作成したと誤認させる表示は禁止です。

**配布制限：** モデルを単体または抽出可能な状態で配布・販売・サブライセンスできません。アプリに含める場合、インタラクティブな作品内に組み込み、汎用の3Dソフトで開けず、合理的な業界標準のアクセス防止措置で抽出を防ぐ必要があります。生のFBX/OBJ等や容易に開けるアーカイブとして配ることはできません。改変しても制限は残ります。

商品説明は日本のJR系地下鉄風とするものの、特定形式・軌間・運転台の適合は確認できていません。さらに、TurboSquidライセンスは車体の第三者商標・トレードドレス等を許諾するものではないとされています。JRの標章や実車由来の識別可能な意匠を商用利用するなら権利者の別途許諾を確認し、未取得なら識別表示・塗装を架空化して法務確認してください。

商品ページ記載ではBlender/FBX/OBJ/DAE等、256,327 polygons、テクスチャ入りRARです。iOS向けには軽量化・マテリアル整理・形式変換が必要で、ページ上にUSDZやRealityKit対応、狭軌保証はありません。

**位置づけ：** 有料・未購入。今回は購入していません。高精細な日本型主役車両として採用する前に、権利、形式、車両寸法、運転台の有無を個別確認してください。

## 2026-11-06 オリジナル沿線表面

ambientCG、Poly Haven、Kenney は上の調査どおり CC0 として記録されていますが、この回でもファイルはダウンロードしていません。沿線に載せた `scenery_*.png` は `Scripts/build_original_scenery_textures.py` が生成したオリジナル画素です。ライセンス文は `Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/Resources/ORIGINAL_SURFACE_LICENSE.md` にあります。運転台の参考写真、BVE画像、ストリートビューは使っていません。

## 手続き生成シーンの更新

`Packages/RailwaySceneFidelity`をXcode app/test targetへ追加し、既存の架空ルートサンプルをchainage付き中心線に変換しました。アプリの高品質選択時だけ、線路・枕木・架線・終端ホーム・一般化した沿線要素を生成し、走行位置に応じた表示範囲を更新します。これはアプリ内の既存スタイライズ生成器とは別経路です。Entity名には合成プレースホルダー由来を残します。3D素材の購入・取得・コピーはありません。

`Packages/RailwayRendering`の`EnvironmentRenderState.surfaceWetnessBlend`と`snowSurfaceCoverageBlend`は、従来の線路・地面生成材へ渡す0〜1の視覚ヒントです。新しいSceneFidelityの材質へはまだ接続していません。新規高品質シーンはPBRテクスチャ、濡れ・積雪の物理、写真測量、実地形、フォトリアルな車両/運転台を追加せず、iPhoneでの表示・性能も未検証です。関連XCTestはソースに含みますが未実行です。

## 実路線参照データのライセンスと適用範囲

`Research/RealRouteReference/`には、国土交通省の国土数値情報「鉄道データ」N02-25から抽出した、近鉄京都線・京都—東寺間に相当する路線線形と駅線形を参考データとして同梱しています。データはCC BY 4.0です。出典、加工内容、利用条件は[`Research/RealRouteReference/LICENSES.md`](Research/RealRouteReference/LICENSES.md)と`Data/route-package.json`に記載しています。入力アーカイブそのものは同梱していません。

16頂点の測地線合計801.5 mは一般化された公開線形から計算した`ESTIMATED`値で、測量線路長や営業キロではありません。線路数、軌間、縦断勾配、カント、信号、閉そく、駅ホーム、停止位置は`UNKNOWN`です。このため、実データはアプリの選択路線・描画・物理・信号に接続せず、参考資料にとどめています。距離の定義と欠落値は[`Research/RealRouteReference/QUALITY_REPORT.md`](Research/RealRouteReference/QUALITY_REPORT.md)を参照してください。

## 検証上の注意

3D素材の購入、取得、アプリ同梱は行っていません。CC BY 4.0の実路線参照データは別の研究フォルダに、出典表示・加工説明・品質限界とともに収録し、アプリの運転路線から切り離しています。Swift/Xcode/iOS SDKが利用できないため、追加したSwiftテスト、iOSビルド、Xcodeの画面確認、iPhoneの見た目・性能・発熱は未検証です。商用公開前には候補素材の実ファイル内ライセンスや依存権利を再確認し、対象端末で視覚・性能試験をしてください。

## 公式出典

- Poly Haven: [Gravel Embedded Concrete](https://polyhaven.com/a/gravel_embedded_concrete) · [License](https://polyhaven.com/license) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode.en)
- ambientCG: [Rails 001](https://ambientcg.com/view?id=Rails001) · [License](https://docs.ambientcg.com/license/) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode)
- Kenney: [Train Kit](https://kenney.nl/assets/train-kit) · [Support / license](https://kenney.nl/support) · [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/legalcode.en)
- Sketchfab: [Steam Locomotive Train Engine](https://sketchfab.com/3d-models/steam-locomotive-train-engine-faf1af6759174e0f984872ef317a181d) · [Sketchfab licenses](https://sketchfab.com/licenses) · [CC BY 4.0 legal code](https://creativecommons.org/licenses/by/4.0/legalcode)
- TurboSquid: [Japan Train subway Jr series](https://www.turbosquid.com/3d-models/japan-train-subway-jr-series-model-1896854) · [Standard license](https://www.turbosquid.com/licensing)


## 独自制作の手続きアセット案

無償で権利条件を確認できた候補には、日本の特定車両や運転台をそのまま再現できる資産はありません。代替として、**軌間を設定値にしたオリジナルの線路メッシュ**（レール断面、枕木・締結具、バラスト、ホームとの接続）を自動生成し、選択する路線仕様に合わせてゲージや部材寸法を入力する方法があります。1067mmを対象にする場合も、実際の路線・仕様を別途確認して値を設定してください。モデル、テクスチャ、設計式を独自制作すれば、第三者のBVEモデルや未許諾資産を再配布せずに済みます。

車両・運転台は、特定事業者のロゴや識別可能な実車の外観を避けた**架空の日本風通勤車・オリジナル運転台**から始め、表示器・計器・操作器・窓枠を独自設計できます。実在車両の寸法や実物写真・図面を参考にする場合は、参照資料の利用条件、商標・意匠・著作権等を別途確認してください。既存BVEアセットをトレース・転用する方法は採らないでください。

手続き生成は商用利用しやすい選択肢ですが、**それだけでフォトリアルになるわけではありません**。高品質PBR表面材、精緻な法線・粗さ、共有メッシュ、距離別LOD、実機上の照明・見え方調整が別に必要です。SceneFidelityは線路・枕木・架線・簡易ホーム・沿線の架空形状を生成しますが、車両/運転台の高精細資産や実地形は生成せず、実機性能も未評価です。

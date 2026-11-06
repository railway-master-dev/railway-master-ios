# 検証メモ

1. `swift test` をXcode/Swift 5.9+とiOS 17 SDKのある環境で実行する。
2. `python3 Scripts/validate_scene_fidelity.py` でPackageの静的な機能契約・ラベル・依存境界を確認する。
3. テスト路線の制御点を増やして、直線・左右曲線・勾配・カントの接線連続性を目視する。
4. 線路レール、締結装置、架線、枕木、ホーム、道路車両、人物、建物、植生の表示と陰影をRealityKitで確認する。
5. 代表的なiPhoneでXcode Instrumentsを使い、GPU/CPUフレーム時間・最大Entity/mesh数・メモリ・熱状態を長時間測る。

現SandboxではPython静的チェック以外を実行できません。静的チェックが通っても、Swiftコンパイル、XCTest、RealityKitの描画、実機性能を確認したことにはなりません。

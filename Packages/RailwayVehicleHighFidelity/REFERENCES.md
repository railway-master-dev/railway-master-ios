# References

## Apple RealityKit materials

The prototype uses RealityKit's `PhysicallyBasedMaterial` for scalar/color PBR properties (base color, roughness, metallic, emissive color/intensity) and a transparent blending material for tinted glazing. These APIs describe rendering features; they do not guarantee photoreal output without authored geometry, textures, lighting, and device review.

- [Apple: PhysicallyBasedMaterial](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial) — material structure and PBR properties, including base color, roughness, metallic, emissive color and intensity.
- [Apple: PhysicallyBasedMaterial.Blending.transparent(opacity:)](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/blending-swift.enum/transparent(opacity:)) — transparent blending case and its opacity parameter.
- [Apple: PhysicallyBasedMaterial.Opacity](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/opacity) — opacity value type and `init(floatLiteral:)`.

## User-provided visual requirements

The implementation scope was checked against `/home/ubuntu/upload/pasted_content_iNZVCVpskgPQw55APPPcyk.txt` (Ultimate Railway Visual Fidelity Directive), `/home/ubuntu/upload/Pasted_content_01.txt`, and the user-provided visual reference screenshots in `/home/ubuntu/upload/IMG_4292.png`–`IMG_4300.jpeg`. Those materials remain outside this package; their pixels and third-party assets are not embedded, traced, or redistributed here. They specify the target, not evidence that this procedural prototype meets it.

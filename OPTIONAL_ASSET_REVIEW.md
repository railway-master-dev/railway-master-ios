# Optional railway asset review

## Candidate

[Japanese Railway Starter Kit by kimuj5090](https://kimuj5090.itch.io/japanese-railway-starter-kit) is a free author-published pack described as 12 GLB models plus editable Blender models, including 1067 mm track sections, four bridge forms, and cutaway tunnel pieces. The creator's page says the assets are representative approximations, not surveyed replicas, and use solid-color materials.

The product page states that personal and commercial project use and modification are permitted with attribution, while standalone redistribution or resale of the original or modified assets is prohibited. Its requested credit is `Japanese Railway Starter Kit by kimuj5090 — https://kimuj5090.itch.io/`.

## Decision: not included

The current app builds its route scenery from RealityKit primitives and has no runtime GLB importer. The sandbox has no Blender, USDZ converter, Xcode, or USD/glTF conversion libraries, so a GLB-to-USDZ conversion and iOS RealityKit import could not be validated here. The public download endpoint was not directly accessible from the non-interactive environment. Because the kit is optional and its full bundled `LICENSE.txt` could not be inspected, no archive or model was downloaded, copied, modified, or bundled, and no in-app attribution is required for this build. Reconsider only after a Mac/Xcode conversion and in-app validation path is available and the complete included license has been reviewed.

This decision avoids redistributing standalone assets and makes no claim of photorealistic or surveyed fidelity.

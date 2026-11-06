# Procedural PBR — original commuter-car surface-art prototype

This directory contains a standalone, reproducible surface-art experiment for a fictional Japanese commuter train. All pixels are generated from scratch by the included Python script using only NumPy and Pillow; there are no external images, downloaded assets, real-vehicle data, brands, logos, or vehicle numbers.

**This is a separate prototype and is not integrated into the app (the current model has no UV/texture loader). It does not demonstrate photorealism.** These are deliberately stylized material studies, not production-ready or physically calibrated scans.

## Included materials

Each material has one 512 × 512 PNG for each map type:

| Material | Intended visual role | Maps |
|---|---|---|
| `pearl_painted_metal` | Soft cool pearl-painted exterior panel | `albedo`, `roughness`, `normal` |
| `teal_painted_band` | Original teal accent band | `albedo`, `roughness`, `normal` |
| `dark_steel` | Dark metal trim or underframe detail | `albedo`, `roughness`, `normal` |
| `smoked_glass` | Subdued smoked glazing study | `albedo`, `roughness`, `normal` |

Albedo and normal files are RGB; roughness files are single-channel grayscale (`L`). All are opaque, lossless PNGs. Roughness follows the common convention that darker is smoother and brighter is rougher. Normal maps use tangent-space RGB encoding with approximately `(128, 128, 255)` as flat; renderer-specific green-channel conventions may need adjustment.

## Rebuild and inspect

From this directory, with Python 3, Pillow, and NumPy installed:

```sh
python3 build_pbr_textures.py
python3 check_pbr_textures.py
```

The generator uses fixed per-material seeds and wrap-around filtering for every stochastic field; rerunning it with the default settings produces the same maps. An alternate output folder can be selected with `--output PATH`. The checker accepts an alternate folder with `--input PATH`.

## Seam and file checks

The checker opens each expected file and validates its 512 × 512 dimensions, expected RGB/L mode, and absence of alpha/transparency. For tile continuity it measures absolute pixel differences across the left/right and top/bottom opposite edges, then compares these wrap-boundary differences with ordinary adjacent-pixel differences inside the image. It passes when seam mean is no more than `1.8 × interior mean + 1.5` and seam 99th percentile is no more than `2.0 × interior 99th percentile + 3` (8-bit levels). This quantitative guard catches conspicuous hard borders; it is not a renderer-based visual approval or proof of perfect seamlessness under every filtering/mipmap implementation.

## Notes and limitations

- Surfaces are original procedural art, intentionally abstract and low-contrast; they do not reproduce any actual train or supplier finish.
- No UV layout, shader/material setup, mipmaps, ambient-occlusion map, metallic map, or application integration is included.
- The simple tangent-space normal output is generated from small synthetic height variation. If used in another renderer, confirm texture color-space, normal-Y direction, wrapping, and roughness conventions there first.
- PNG output is deterministic for a given script, seed, and NumPy/Pillow environment; byte-for-byte encoding details may vary across library versions even where pixel values do not.

#!/usr/bin/env python3
"""Original 256px tileable scenery albedos with per-material patterns.

No photographs and no external images: every pixel is procedural, drawn
in-repo. All drawing wraps at the tile edges (shapes are repeated at
+/- SIZE offsets), so each texture tiles seamlessly. Base colors are the
same fictional palette as the previous 128px generation.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZE = 256
OUT = Path(__file__).resolve().parents[1] / "Packages/RailwaySceneFidelity/Sources/RailwaySceneFidelity/Resources"


def noise(seed: int, rolls: int = 3) -> np.ndarray:
    """Tileable smoothed random field in [0, 1] (rolls wrap, so it tiles)."""
    rng = np.random.default_rng(seed)
    field = rng.random((SIZE, SIZE), dtype=np.float32)
    for _ in range(rolls):
        field = 0.5 * field + 0.25 * np.roll(field, 1, 0) + 0.25 * np.roll(field, 1, 1)
    field -= field.min()
    field /= max(float(field.max()), 1e-6)
    return field


def base_image(base: tuple[int, int, int], seed: int, contrast: float) -> Image.Image:
    field = noise(seed)
    rgb = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    for channel, value in enumerate(base):
        rgb[:, :, channel] = np.clip(value + (field - 0.5) * contrast, 0, 255).astype(np.uint8)
    return Image.fromarray(rgb, mode="RGB")


def shade(color: tuple[int, int, int], factor: float) -> tuple[int, int, int]:
    return tuple(max(0, min(255, int(round(c * factor)))) for c in color)


def wrapped(draw_fn, x: float, y: float) -> None:
    """Run draw_fn(dx, dy) for the 9 wrapped copies of point (x, y)."""
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            draw_fn(x + ox, y + oy)


# --- per-material pattern painters -----------------------------------------
# Each painter receives (image, rng, base) and draws its pattern on top of
# the noise base. All shapes go through `wrapped` so the tile stays seamless.

def paint_ballast(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Many small multitone stone ellipses."""
    d = ImageDraw.Draw(img)
    tones = [shade(base, f) for f in (0.72, 0.85, 0.97, 1.1, 1.24, 1.38)]
    for _ in range(900):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        w, h = float(rng.uniform(4, 11)), float(rng.uniform(3, 8))
        tone = tones[int(rng.integers(0, len(tones)))]
        wrapped(lambda cx, cy, w=w, h=h, tone=tone: d.ellipse([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], fill=tone), x, y)


def paint_concrete(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Slab joints every 64px plus fine speckle."""
    d = ImageDraw.Draw(img)
    joint = shade(base, 0.68)
    for pos in (0, 64, 128, 192):
        d.line([(pos, 0), (pos, SIZE)], fill=joint, width=2)
        d.line([(0, pos), (SIZE, pos)], fill=joint, width=2)
    for _ in range(2600):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        tone = shade(base, float(rng.uniform(0.78, 1.18)))
        wrapped(lambda cx, cy, tone=tone: d.point((cx, cy), fill=tone), x, y)
    for _ in range(26):  # faint stains
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        r = float(rng.uniform(6, 18))
        tone = shade(base, 0.9)
        wrapped(lambda cx, cy, r=r, tone=tone: d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tone), x, y)


def paint_grass(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Two-tone patches plus short blade strokes."""
    d = ImageDraw.Draw(img)
    for _ in range(60):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        r = float(rng.uniform(10, 30))
        tone = shade(base, float(rng.uniform(0.82, 1.12)))
        wrapped(lambda cx, cy, r=r, tone=tone: d.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=tone), x, y)
    for _ in range(1500):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        ln = float(rng.uniform(3, 7))
        tilt = float(rng.uniform(-2, 2))
        tone = shade(base, float(rng.uniform(0.85, 1.45)))
        wrapped(lambda cx, cy, ln=ln, tilt=tilt, tone=tone: d.line([(cx, cy), (cx + tilt, cy - ln)], fill=tone, width=1), x, y)


def paint_foliage(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Overlapping light/dark leaf clusters."""
    d = ImageDraw.Draw(img)
    for _ in range(420):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        r = float(rng.uniform(4, 13))
        tone = shade(base, float(rng.uniform(0.62, 1.55)))
        wrapped(lambda cx, cy, r=r, tone=tone: d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tone), x, y)
    for _ in range(300):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        r = float(rng.uniform(1.5, 3.5))
        tone = shade(base, float(rng.uniform(1.3, 1.8)))
        wrapped(lambda cx, cy, r=r, tone=tone: d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tone), x, y)


def paint_asphalt(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Dense light/dark aggregate speckle."""
    d = ImageDraw.Draw(img)
    for _ in range(5200):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        tone = shade(base, float(rng.uniform(0.75, 1.7)))
        wrapped(lambda cx, cy, tone=tone: d.point((cx, cy), fill=tone), x, y)
    for _ in range(300):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        tone = shade(base, float(rng.uniform(1.1, 1.5)))
        wrapped(lambda cx, cy, tone=tone: d.ellipse([cx - 1.5, cy - 1.5, cx + 1.5, cy + 1.5], fill=tone), x, y)


def _paint_brick(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Running-bond brick courses with mortar joints, offset per row.

    The pattern period is 64px horizontally and 32px vertically, both of
    which divide SIZE, so the courses tile seamlessly.
    """
    d = ImageDraw.Draw(img)
    mortar = shade(base, 1.28)
    d.rectangle([0, 0, SIZE, SIZE], fill=mortar)
    brick_w, brick_h, joint = 62, 14, 2
    row_h = brick_h + joint
    for row, y in enumerate(range(0, SIZE, row_h)):
        offset = 32 if row % 2 else 0
        for x in range(-brick_w, SIZE + brick_w, brick_w + joint):
            tone = shade(base, float(rng.uniform(0.88, 1.1)))
            d.rectangle([x + offset, y, x + offset + brick_w, y + brick_h], fill=tone)
    for _ in range(700):  # surface speckle over bricks and mortar
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        tone = shade(base, float(rng.uniform(0.8, 1.25)))
        d.point((x, y), fill=tone)


def paint_steel(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Horizontal brushed streaks plus sparse rust-toned speckle."""
    d = ImageDraw.Draw(img)
    for _ in range(210):
        y = float(rng.uniform(0, SIZE))
        x0 = float(rng.uniform(-40, SIZE))
        ln = float(rng.uniform(30, 130))
        tone = shade(base, float(rng.uniform(0.82, 1.3)))
        # Streaks are horizontal and the field is periodic in y only through
        # the row position; wrap vertically so rows near edges still tile.
        for oy in (-SIZE, 0, SIZE):
            d.line([(x0, y + oy), (x0 + ln, y + oy)], fill=tone, width=1)
    for _ in range(120):
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        tone = (max(0, base[0] + 28), max(0, base[1] - 6), max(0, base[2] - 22))
        wrapped(lambda cx, cy, tone=tone: d.point((cx, cy), fill=tone), x, y)


def paint_timber(img: Image.Image, rng: np.random.Generator, base) -> None:
    """Vertical plank joints plus long grain streaks."""
    d = ImageDraw.Draw(img)
    joint = shade(base, 0.6)
    for x in range(0, SIZE, 52):  # plank width ~52px; last plank wraps
        d.line([(x, 0), (x, SIZE)], fill=joint, width=2)
    for plank in range(5):
        x0 = plank * 52
        for _ in range(46):
            gx = x0 + float(rng.uniform(3, 49))
            y0 = float(rng.uniform(-30, SIZE))
            ln = float(rng.uniform(24, 90))
            tone = shade(base, float(rng.uniform(0.78, 1.3)))
            for ox in (-SIZE, 0, SIZE):
                d.line([(gx + ox, y0), (gx + ox, y0 + ln)], fill=tone, width=1)
    for _ in range(12):  # knots
        x, y = float(rng.uniform(0, SIZE)), float(rng.uniform(0, SIZE))
        tone = shade(base, 0.66)
        wrapped(lambda cx, cy, tone=tone: d.ellipse([cx - 2.5, cy - 2.5, cx + 2.5, cy + 2.5], fill=tone), x, y)


PAINTERS = {
    "scenery_ballast": paint_ballast,
    "scenery_concrete": paint_concrete,
    "scenery_grass": paint_grass,
    "scenery_foliage": paint_foliage,
    "scenery_asphalt": paint_asphalt,
    "scenery_brick_warm": _paint_brick,
    "scenery_brick_cool": _paint_brick,
    "scenery_steel": paint_steel,
    "scenery_timber": paint_timber,
}


def save(name: str, base: tuple[int, int, int], seed: int, contrast: float) -> None:
    img = base_image(base, seed, contrast)
    rng = np.random.default_rng(seed * 1000 + 7)
    PAINTERS[name](img, rng, base)
    img.save(OUT / f"{name}.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save("scenery_ballast", (118, 116, 108), 11, 46)
    save("scenery_concrete", (168, 166, 158), 22, 28)
    save("scenery_grass", (78, 118, 62), 33, 40)
    save("scenery_foliage", (46, 92, 48), 44, 36)
    save("scenery_asphalt", (58, 60, 62), 55, 22)
    save("scenery_brick_warm", (168, 112, 78), 66, 34)
    save("scenery_brick_cool", (132, 142, 146), 77, 30)
    save("scenery_steel", (92, 98, 102), 88, 24)
    save("scenery_timber", (112, 78, 48), 99, 32)
    print(f"wrote {len(list(OUT.glob('scenery_*.png')))} textures ({SIZE}x{SIZE}) to {OUT}")


if __name__ == "__main__":
    main()

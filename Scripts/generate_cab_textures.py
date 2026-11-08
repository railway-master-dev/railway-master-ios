#!/usr/bin/env python3
"""Generate the cab instrument textures for RailwayVehicleCab.

Draws three analog gauge faces (speedometer, main-reservoir/brake-pipe
pressure, brake-cylinder pressure), a notch quadrant plate and a subtle
desk grain, as 512x512 PNGs. Faces are black with white markings, in the
style of Japanese cab instruments. Angles: value 0 sits at 135 degrees
of sweep start (measuring clockwise from the 7:30 position), full scale
at +270 degrees of sweep. The Swift side uses the same convention:
angle(forFraction:) = -(135 + 270 * fraction) degrees about +Z when the
face normal points toward the driver (+Z in car space).
"""
from PIL import Image, ImageDraw, ImageFont
import math
import os
import random

OUT = os.path.join(os.path.dirname(__file__), "..",
                   "Packages", "RailwayVehicleCab", "Sources",
                   "RailwayVehicleCab", "Resources")
SIZE = 512
CENTER = SIZE // 2


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def base_face():
    img = Image.new("RGB", (SIZE, SIZE), (12, 12, 14))
    d = ImageDraw.Draw(img)
    d.ellipse([6, 6, SIZE - 6, SIZE - 6], outline=(190, 190, 195), width=6)
    d.ellipse([26, 26, SIZE - 26, SIZE - 26], outline=(70, 70, 76), width=2)
    return img, d


def point(fraction, radius):
    # Viewer coords (x right, y up): zero at 225 degrees (lower-left),
    # sweeping clockwise 270 degrees to full scale at -45 degrees
    # (lower-right), passing 90 degrees (top) at half scale.
    theta = math.radians(225 - 270 * fraction)
    return (CENTER + radius * math.cos(theta),
            CENTER - radius * math.sin(theta))


def draw_ticks(d, max_value, major_step, minor_step, label_every,
               red_from=None, fmt="{:g}"):
    # minor ticks
    v = 0.0
    while v <= max_value + 1e-9:
        f = v / max_value
        x1, y1 = point(f, 196)
        x2, y2 = point(f, 214)
        d.line([x1, y1, x2, y2], fill=(200, 200, 205), width=3)
        v += minor_step
    # major ticks + labels
    v = 0.0
    while v <= max_value + 1e-9:
        f = v / max_value
        x1, y1 = point(f, 186)
        x2, y2 = point(f, 216)
        d.line([x1, y1, x2, y2], fill=(240, 240, 245), width=6)
        if v % label_every == 0:
            tx, ty = point(f, 148)
            text = fmt.format(v)
            d.text((tx, ty), text, fill=(240, 240, 245),
                   font=font(44), anchor="mm")
        v += major_step
    if red_from is not None:
        steps = 60
        for i in range(steps):
            f = red_from + (1 - red_from) * i / steps
            x1, y1 = point(f, 220)
            x2, y2 = point(f, 232)
            d.line([x1, y1, x2, y2], fill=(215, 40, 32), width=7)


def speedometer():
    img, d = base_face()
    draw_ticks(d, 120, 10, 2, 20, red_from=110 / 120)
    d.text((CENTER, CENTER + 88), "km/h", fill=(200, 200, 205),
           font=font(40), anchor="mm")
    d.text((CENTER, CENTER + 140), "SPEED", fill=(140, 140, 148),
           font=font(28), anchor="mm")
    img.save(os.path.join(OUT, "cab_gauge_speed.png"))


def pressure_gauge(name, title, subtitle, max_value=1000):
    img, d = base_face()
    draw_ticks(d, max_value, 100, 50, 200)
    d.text((CENTER, CENTER + 88), "kPa", fill=(200, 200, 205),
           font=font(40), anchor="mm")
    d.text((CENTER, CENTER + 140), title, fill=(140, 140, 148),
           font=font(28), anchor="mm")
    d.text((CENTER, CENTER - 120), subtitle, fill=(200, 200, 205),
           font=font(30), anchor="mm")
    img.save(os.path.join(OUT, name))


def notch_plate():
    img = Image.new("RGB", (SIZE, 256), (24, 24, 27))
    d = ImageDraw.Draw(img)
    labels = ["B7", "B5", "B3", "B1", "N", "P1", "P3", "P5"]
    n = len(labels)
    for i, label in enumerate(labels):
        x = 40 + (SIZE - 80) * i / (n - 1)
        color = (240, 240, 245) if label == "N" else (190, 190, 196)
        if label.startswith("B"):
            color = (240, 180, 90)
        d.line([x, 30, x, 76], fill=color, width=5)
        d.text((x, 118), label, fill=color, font=font(40), anchor="mm")
    d.rectangle([8, 8, SIZE - 8, 248], outline=(90, 90, 98), width=3)
    img.save(os.path.join(OUT, "cab_notch_plate.png"))


def desk_grain():
    random.seed(7)
    img = Image.new("RGB", (SIZE, SIZE), (38, 40, 44))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = random.randint(-7, 7)
            px[x, y] = (38 + n, 40 + n, 44 + n)
    img.save(os.path.join(OUT, "cab_desk_grain.png"))


# --- E231 early-type (analog) cab set: white gauge faces -------------

def white_face():
    img = Image.new("RGB", (SIZE, SIZE), (232, 230, 222))
    d = ImageDraw.Draw(img)
    d.ellipse([6, 6, SIZE - 6, SIZE - 6], outline=(30, 30, 32), width=8)
    d.ellipse([26, 26, SIZE - 26, SIZE - 26], outline=(150, 148, 140), width=2)
    return img, d


def draw_ticks_ink(d, max_value, major_step, minor_step, label_every,
                   red_from=None, ink=(20, 20, 22), fmt="{:g}"):
    v = 0.0
    while v <= max_value + 1e-9:
        f = v / max_value
        x1, y1 = point(f, 196)
        x2, y2 = point(f, 214)
        d.line([x1, y1, x2, y2], fill=ink, width=3)
        v += minor_step
    v = 0.0
    while v <= max_value + 1e-9:
        f = v / max_value
        x1, y1 = point(f, 186)
        x2, y2 = point(f, 216)
        d.line([x1, y1, x2, y2], fill=ink, width=6)
        if v % label_every == 0:
            tx, ty = point(f, 148)
            d.text((tx, ty), fmt.format(v), fill=ink, font=font(44),
                   anchor="mm")
        v += major_step
    if red_from is not None:
        for i in range(60):
            f = red_from + (1 - red_from) * i / 60
            x1, y1 = point(f, 220)
            x2, y2 = point(f, 232)
            d.line([x1, y1, x2, y2], fill=(200, 32, 26), width=7)


def e231_speedometer():
    img, d = white_face()
    draw_ticks_ink(d, 120, 10, 2, 20, red_from=110 / 120)
    d.text((CENTER, CENTER + 88), "km/h", fill=(20, 20, 22),
           font=font(40), anchor="mm")
    img.save(os.path.join(OUT, "cab_gauge_speed_e231.png"))


def e231_pressure():
    img, d = white_face()
    draw_ticks_ink(d, 1000, 100, 50, 200)
    d.text((CENTER, CENTER + 88), "kPa", fill=(20, 20, 22),
           font=font(40), anchor="mm")
    d.text((CENTER, CENTER + 140), "MR / BC", fill=(90, 88, 82),
           font=font(30), anchor="mm")
    img.save(os.path.join(OUT, "cab_gauge_pressure_e231.png"))


def e231_tims_screen():
    w, h = 640, 448
    img = Image.new("RGB", (w, h), (16, 32, 56))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 52], fill=(24, 52, 92))
    d.text((18, 26), "TIMS", fill=(230, 238, 250), font=font(30),
           anchor="lm")
    d.text((w - 18, 26), "E231", fill=(160, 190, 230), font=font(26),
           anchor="rm")
    # status blocks, drawn abstractly like a train-information page
    blocks = [(18, 74, 300, 160), (322, 74, 622, 160),
              (18, 182, 300, 268), (322, 182, 622, 268)]
    for (x1, y1, x2, y2) in blocks:
        d.rectangle([x1, y1, x2, y2], outline=(90, 130, 180), width=2)
    d.text((34, 96), "SPEED", fill=(150, 190, 240), font=font(24),
           anchor="lm")
    d.text((34, 182 + 22), "NEXT STOP", fill=(150, 190, 240),
           font=font(24), anchor="lm")
    d.text((338, 96), "ATS-P", fill=(150, 190, 240), font=font(24),
           anchor="lm")
    d.text((338, 182 + 22), "DOORS", fill=(150, 190, 240), font=font(24),
           anchor="lm")
    # a simple formation bar along the bottom
    d.rectangle([18, 300, 622, 348], outline=(90, 130, 180), width=2)
    for i in range(8):
        x = 30 + i * 72
        d.rectangle([x, 312, x + 58, 336], outline=(120, 165, 215),
                    width=2)
    d.rectangle([18, 380, 622, 428], outline=(60, 90, 130), width=2)
    d.text((34, 404), "TRAIN INFORMATION", fill=(110, 145, 190),
           font=font(22), anchor="lm")
    img.save(os.path.join(OUT, "cab_tims_screen.png"))


def e231_lamp_panel():
    w, h = 384, 320
    img = Image.new("RGB", (w, h), (26, 27, 30))
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, w - 6, h - 6], outline=(90, 90, 98), width=3)
    colors = [(46, 160, 80), (52, 58, 60), (200, 160, 40), (52, 58, 60),
              (52, 58, 60), (190, 48, 40), (52, 58, 60), (46, 160, 80),
              (52, 58, 60), (52, 58, 60), (46, 160, 80), (52, 58, 60),
              (200, 160, 40), (52, 58, 60), (52, 58, 60), (190, 48, 40)]
    for i, color in enumerate(colors):
        col, row = i % 4, i // 4
        x1 = 28 + col * 88
        y1 = 30 + row * 72
        d.rectangle([x1, y1, x1 + 58, y1 + 42], fill=color,
                    outline=(120, 120, 128), width=2)
    img.save(os.path.join(OUT, "cab_lamp_panel.png"))


def e231_notch_plate():
    w, h = 256, 512
    img = Image.new("RGB", (w, h), (30, 30, 34))
    d = ImageDraw.Draw(img)
    d.rectangle([8, 8, w - 8, h - 8], outline=(100, 100, 108), width=3)
    labels = ["P5", "P4", "P3", "P2", "P1", "N",
              "B1", "B3", "B5", "B7", "EMG"]
    n = len(labels)
    for i, label in enumerate(labels):
        y = 36 + (h - 72) * i / (n - 1)
        if label == "N":
            color = (245, 245, 248)
        elif label.startswith("B") or label == "EMG":
            color = (245, 180, 90)
        else:
            color = (200, 200, 206)
        if label == "EMG":
            color = (240, 70, 55)
        d.line([30, y, 74, y], fill=color, width=5)
        d.text((150, y), label, fill=color, font=font(38), anchor="mm")
    img.save(os.path.join(OUT, "cab_notch_plate_e231.png"))


def desk_grain_light():
    random.seed(11)
    img = Image.new("RGB", (SIZE, SIZE), (158, 160, 163))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            n = random.randint(-6, 6)
            px[x, y] = (158 + n, 160 + n, 163 + n)
    img.save(os.path.join(OUT, "cab_desk_grain_light.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    speedometer()
    pressure_gauge("cab_gauge_pressure_mr.png", "MR / BP", "MAIN RESERVOIR")
    pressure_gauge("cab_gauge_pressure_bc.png", "BC", "BRAKE CYLINDER",
                   max_value=600)
    notch_plate()
    desk_grain()
    e231_speedometer()
    e231_pressure()
    e231_tims_screen()
    e231_lamp_panel()
    e231_notch_plate()
    desk_grain_light()
    print("wrote", sorted(os.listdir(OUT)))

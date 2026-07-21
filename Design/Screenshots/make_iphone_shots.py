#!/usr/bin/env python3
"""Compose iPhone App Store screenshots (1320x2868, iPhone 6.9" portrait):
vertical gray-blue gradient background, white New York serif caption on top,
black iPhone device frame (with Dynamic Island pill) around the screenshot.

Usage:  python3 make_iphone_shots.py [source-folder]

Source folder (default ~/Temp) must contain raw 1320x2868 simulator/device
screenshots named iPhone_1.png .. iPhone_8.png, in the order of the CAPTIONS
table below. Output goes to Design/Screenshots/iPhone/PictureFramer_NN.png.
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Temp")
OUT = os.path.join(HERE, "iPhone")
os.makedirs(OUT, exist_ok=True)

W, H = 1320, 2868
TOP_RGB = (103, 110, 121)
BOT_RGB = (79, 86, 95)
FONT_PATH = "/System/Library/Fonts/NewYork.ttf"
FONT_SIZE = 105
TITLE_CENTER_Y = 228
LINE_GAP = 22

# Device frame geometry, measured from the original hand-made composites.
BEZEL = 29
DEV_TOP = 461
DEV_BOTTOM = 2699
INNER_RADIUS = 99
ISLAND_W, ISLAND_H, ISLAND_TOP_GAP = 260, 75, 25

CAPTIONS = [
    "Museum photos,\nperfected",
    "The frame is found\nfor you",
    "Straight — with real\nwall around it",
    "Full resolution, back\nin your library",
    "Glare on the glass?",
    "Mark it — zoom in\nfor fine work",
    "AI restores the\nartwork underneath",
    "Your AI provider,\nyour key",
]


def background():
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        r = round(TOP_RGB[0] + (BOT_RGB[0] - TOP_RGB[0]) * t)
        g = round(TOP_RGB[1] + (BOT_RGB[1] - TOP_RGB[1]) * t)
        b = round(TOP_RGB[2] + (BOT_RGB[2] - TOP_RGB[2]) * t)
        for x in range(W):
            px[x, y] = (r, g, b)
    return im


def draw_title(im, text):
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    font.set_variation_by_name("Semibold")
    lines = text.split("\n")
    heights = []
    for ln in lines:
        l, t, r, b = draw.textbbox((0, 0), ln, font=font)
        heights.append(b - t)
    line_h = max(heights)
    total = line_h * len(lines) + LINE_GAP * (len(lines) - 1)
    y = TITLE_CENTER_Y - total // 2
    for ln in lines:
        draw.text((W // 2, y), ln, font=font, fill=(255, 255, 255), anchor="ma")
        y += line_h + LINE_GAP


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def add_shadow(bg, box, radius, blur=45, alpha=110, offset=(0, 20)):
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]],
        radius=radius, fill=(0, 0, 0, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    bg.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), layer)


def compose_device(bg, shot):
    inner_h = DEV_BOTTOM - DEV_TOP - 2 * BEZEL
    inner_w = round(inner_h * shot.width / shot.height)
    outer_w, outer_h = inner_w + 2 * BEZEL, inner_h + 2 * BEZEL
    x0 = (W - outer_w) // 2
    y0 = DEV_TOP
    outer_r = INNER_RADIUS + BEZEL

    add_shadow(bg, (x0, y0, x0 + outer_w, y0 + outer_h), outer_r)

    frame = Image.new("RGB", (outer_w, outer_h), (16, 16, 18))
    bg.paste(frame, (x0, y0), rounded_mask((outer_w, outer_h), outer_r))

    scr = shot.resize((inner_w, inner_h), Image.LANCZOS)
    bg.paste(scr, (x0 + BEZEL, y0 + BEZEL), rounded_mask((inner_w, inner_h), INNER_RADIUS))

    # Dynamic Island pill (simulator screenshots leave this area empty)
    ix0 = x0 + (outer_w - ISLAND_W) // 2
    iy0 = y0 + BEZEL + ISLAND_TOP_GAP
    ImageDraw.Draw(bg).rounded_rectangle(
        [ix0, iy0, ix0 + ISLAND_W, iy0 + ISLAND_H],
        radius=ISLAND_H // 2, fill=(10, 10, 10))


def main():
    for i, caption in enumerate(CAPTIONS, start=1):
        src = os.path.join(SRC, f"iPhone_{i}.png")
        if not os.path.exists(src):
            print("skip (missing):", src)
            continue
        shot = Image.open(src).convert("RGB")
        bg = background()
        draw_title(bg, caption)
        compose_device(bg, shot)
        out = os.path.join(OUT, f"PictureFramer_{i:02d}.png")
        bg.save(out)
        print("wrote", out, bg.size)


if __name__ == "__main__":
    main()

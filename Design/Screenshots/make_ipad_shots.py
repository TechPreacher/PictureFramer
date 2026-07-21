#!/usr/bin/env python3
"""Compose iPad App Store screenshots in the style of the iPhone set:
vertical gray-blue gradient background, white New York serif caption on top,
black iPad device frame with the screenshot inside. Canvas 2064x2752
(iPad Pro 13" portrait).

Usage:  python3 make_ipad_shots.py [source-folder]

Source folder (default ~/Temp) must contain raw 2064x2752 screenshots named
iPad_1.png .. iPad_8.png, in the order of the SHOTS table below. Entries with
mode "plain" (e.g. an exported artwork rather than an app screenshot) are
shown directly on the background without a device frame. Output goes to
Design/Screenshots/iPad/PictureFramer_NN.png.
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Temp")
OUT = os.path.join(HERE, "iPad")
os.makedirs(OUT, exist_ok=True)

W, H = 2064, 2752
TOP_RGB = (103, 110, 121)
BOT_RGB = (79, 86, 95)
FONT_PATH = "/System/Library/Fonts/NewYork.ttf"
FONT_SIZE = 150
TITLE_CENTER_Y = 215  # vertical center of the caption block
LINE_GAP = 30

BEZEL = 34
DEV_TOP = 440
DEV_BOTTOM = H - 110
INNER_RADIUS = 80

SHOTS = [
    ("iPad_1.png", "Museum photos,\nperfected", "device"),
    ("iPad_2.png", "The frame is found\nfor you", "device"),
    ("iPad_3.png", "Straight — with real\nwall around it", "device"),
    ("iPad_4.png", "Full resolution, back\nin your library", "device"),
    ("iPad_5.png", "Glare on the glass?", "device"),
    ("iPad_6.png", "Mark it — zoom in\nfor fine work", "device"),
    ("iPad_7.png", "AI restores the\nartwork underneath", "device"),
    ("iPad_8.png", "Your AI provider,\nyour key", "device"),
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


def title_font():
    f = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    f.set_variation_by_name("Semibold")
    return f


def draw_title(im, text):
    draw = ImageDraw.Draw(im)
    font = title_font()
    lines = text.split("\n")
    heights, widths = [], []
    for ln in lines:
        l, t, r, b = draw.textbbox((0, 0), ln, font=font)
        widths.append(r - l)
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


def add_shadow(bg, box, radius, blur=60, alpha=110, offset=(0, 28)):
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


def compose_plain(bg, shot):
    # exported artwork shown directly, no device frame
    avail_w, avail_h = W - 300, DEV_BOTTOM - DEV_TOP - 60
    scale = min(avail_w / shot.width, avail_h / shot.height)
    nw, nh = round(shot.width * scale), round(shot.height * scale)
    x0 = (W - nw) // 2
    y0 = DEV_TOP + (DEV_BOTTOM - DEV_TOP - nh) // 2
    add_shadow(bg, (x0, y0, x0 + nw, y0 + nh), 24)
    scr = shot.resize((nw, nh), Image.LANCZOS)
    bg.paste(scr, (x0, y0), rounded_mask((nw, nh), 24))


def main():
    for i, (src_name, caption, mode) in enumerate(SHOTS, start=1):
        src = os.path.join(SRC, src_name)
        if not os.path.exists(src):
            print("skip (missing):", src)
            continue
        shot = Image.open(src).convert("RGB")
        bg = background()
        draw_title(bg, caption)
        if mode == "device":
            compose_device(bg, shot)
        else:
            compose_plain(bg, shot)
        out = os.path.join(OUT, f"PictureFramer_{i:02d}.png")
        bg.save(out)
        print("wrote", out, bg.size)


if __name__ == "__main__":
    main()

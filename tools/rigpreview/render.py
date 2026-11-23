"""Front / side / back views of a block rig (from export.luau), flat-shaded.
   python3 tools/rigpreview/render.py rig.json out.png "Title"
"""
import json, sys
from PIL import Image, ImageDraw, ImageFont

parts = json.load(open(sys.argv[1]))
title = sys.argv[3] if len(sys.argv) > 3 else ""
S = 38  # pixels per stud
W, H = 460, 520
views = [("FRONT", 0), ("LEFT SIDE", 1), ("BACK", 2)]
img = Image.new("RGB", (W * len(views), H + 70), (236, 238, 242))
d = ImageDraw.Draw(img)
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
except OSError:
    f = ImageFont.load_default()

def shade(color, k):
    return tuple(max(0, min(255, int(c * k))) for c in color)

for i, (name, mode) in enumerate(views):
    ox, oy = i * W + W // 2, H - 50  # ground (y = -3) near the bottom
    def to_px(u, y):
        return ox + u * S, oy - (y + 3) * S
    items = []
    for p in parts:
        if mode == 0:   # front: the viewer stands at -Z (the face) looking +Z
            u, du, depth = -p["x"], p["sx"] / 2, p["z"]
        elif mode == 1: # left side: the viewer stands at -X; the face points left
            u, du, depth = p["z"], p["sz"] / 2, p["x"]
        else:           # back: the viewer stands at +Z
            u, du, depth = p["x"], p["sx"] / 2, -p["z"]
        items.append((depth, u, du, p))
    items.sort(key=lambda t: -t[0])  # far (large depth) first
    for depth, u, du, p in items:
        x0, y0 = to_px(u - du, p["y"] + p["sy"] / 2)
        x1, y1 = to_px(u + du, p["y"] - p["sy"] / 2)
        col = tuple(p["color"])
        d.rectangle([x0, y0, x1, y1], fill=shade(col, 1.0), outline=shade(col, 0.6), width=2)
        if p["neon"]:
            d.rectangle([x0 - 2, y0 - 2, x1 + 2, y1 + 2], outline=shade(col, 1.2), width=2)
    gx0, _ = to_px(-6, -3)
    gx1, gy = to_px(6, -3)
    d.line([gx0, gy, gx1, gy], fill=(160, 160, 170), width=2)
    tw = d.textlength(name, font=f)
    d.text((i * W + (W - tw) / 2, H + 20), name, font=f, fill=(40, 40, 50))
if title:
    d.text((16, 12), title, font=f, fill=(40, 40, 50))
img.save(sys.argv[2])

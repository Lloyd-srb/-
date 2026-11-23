"""
Draws the role icons (exported by export.luau) the way the game builds them:
rounded frames on a 100x100 grid, clipped to a circle, with a faction ring.

  python3 tools/roleicons/render.py icons.json docs/role_icons.png [docs/role_roll_mock.png [docs/tutorial_pages.png [docs/monster_page.png]]]

The second image is a mock-up of the intro screen (the reel stopped on one role),
the third the lobby's how-to-play pages.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

SS = 4  # supersampling


def shape_layer(shape, unit):
    w = max(1, round(shape["w"] * unit))
    h = max(1, round(shape["h"] * unit))
    pad = 0
    stroke = shape.get("stroke")
    if stroke:
        pad = max(1, round(stroke["width"] * unit))
    layer = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    radius = shape["r"] * min(w, h)
    alpha = round(255 * (1 - shape["t"]))
    if stroke:
        draw.rounded_rectangle([0, 0, w + pad * 2 - 1, h + pad * 2 - 1], radius=radius + pad, fill=tuple(stroke["color"]) + (255,))
    draw.rounded_rectangle([pad, pad, pad + w - 1, pad + h - 1], radius=radius, fill=tuple(shape["color"]) + (alpha,))
    if shape["rot"]:
        layer = layer.rotate(-shape["rot"], resample=Image.BICUBIC, expand=True)
    return layer


def icon(shapes, ring, size):
    big = size * SS
    unit = big / 100
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    for shape in shapes:
        layer = shape_layer(shape, unit)
        cx, cy = shape["x"] * unit, shape["y"] * unit
        canvas.alpha_composite(layer, (round(cx - layer.width / 2), round(cy - layer.height / 2)))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, big - 1, big - 1], fill=255)
    clipped = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    clipped.paste(canvas, (0, 0), mask)
    ring_w = max(2, round(big * 0.04))
    out = Image.new("RGBA", (big + ring_w * 2, big + ring_w * 2), (0, 0, 0, 0))
    ImageDraw.Draw(out).ellipse([0, 0, out.width - 1, out.height - 1], fill=tuple(ring) + (255,))
    out.alpha_composite(clipped, (ring_w, ring_w))
    final = out.resize((size + 2 * round(ring_w / SS), size + 2 * round(ring_w / SS)), Image.LANCZOS)
    return final


def font(size, bold=True):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/" + name, size)
    except OSError:
        return ImageFont.load_default()


def sheet(data, path):
    size, cols, gap = 180, 4, 40
    order = data["order"]
    rows = (len(order) + cols - 1) // cols
    width = cols * (size + gap) + gap
    height = rows * (size + gap + 40) + gap
    img = Image.new("RGBA", (width, height), (24, 26, 38, 255))
    draw = ImageDraw.Draw(img)
    label_font = font(22)
    for index, role in enumerate(order):
        col, row = index % cols, index // cols
        x = gap + col * (size + gap)
        y = gap + row * (size + gap + 40)
        ic = icon(data["icons"][role], data["rings"][role], size)
        img.alpha_composite(ic, (x + (size - ic.width) // 2, y + (size - ic.height) // 2))
        name = data["names"][role]["en"]
        tw = draw.textlength(name, font=label_font)
        draw.text((x + (size - tw) / 2, y + size + 8), name, font=label_font, fill=(255, 255, 255, 255))
    img.convert("RGB").save(path)


def mock(data, path, role="Sheriff"):
    width, height = 1280, 720
    img = Image.new("RGBA", (width, height), (70, 120, 70, 255))
    draw = ImageDraw.Draw(img)
    # a dimmed game view behind
    draw.rectangle([0, 0, width, height], fill=(30, 40, 35, 255))
    panel_w, panel_h = 760, 330
    px, py = (width - panel_w) // 2, (height - panel_h) // 2 - 20
    draw.rounded_rectangle([px, py, px + panel_w, py + panel_h], radius=24, fill=(24, 26, 38, 235))
    size, step = 128, 156
    centre_x, centre_y = width // 2, py + 120
    window = [px + 20, centre_y - size // 2 - 14, px + panel_w - 20, centre_y + size // 2 + 14]
    draw.rounded_rectangle(window, radius=18, fill=(14, 15, 24, 255))
    reel = ["Doctor", "Wolf", "Fool", "Seer", role, "Engineer", "Chief"]
    strip = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for i, rid in enumerate(reel):
        offset = (i - 4) * step
        ic = icon(data["icons"][rid], data["rings"][rid], size)
        if rid != role or offset != 0:
            ic.putalpha(ic.getchannel("A").point(lambda a: int(a * 0.45)))
        strip.alpha_composite(ic, (centre_x + offset - ic.width // 2, centre_y - ic.height // 2))
    clip = Image.new("L", (width, height), 0)
    ImageDraw.Draw(clip).rounded_rectangle(window, radius=18, fill=255)
    img.paste(strip, (0, 0), Image.composite(strip.getchannel("A"), Image.new("L", (width, height), 0), clip))
    # the marker around the chosen icon
    r = size // 2 + 12
    draw.ellipse([centre_x - r, centre_y - r, centre_x + r, centre_y + r], outline=(255, 205, 60, 255), width=6)
    title = "You are " + data["names"][role]["en"] + "!"
    f = font(48)
    tw = draw.textlength(title, font=f)
    draw.text(((width - tw) / 2, py + 222), title, font=f, fill=(255, 255, 255, 255))
    sub = "Stun gun: 1 shot per day and 1 per night."
    f2 = font(22, False)
    sw = draw.textlength(sub, font=f2)
    draw.text(((width - sw) / 2, py + 284), sub, font=f2, fill=(200, 205, 220, 255))
    img.convert("RGB").save(path)


def wrap(draw, text, fnt, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def tutorial(data, path):
    """All how-to-play pages side by side (lobby TutorialUI)."""
    pages = data["tutorial"]
    pw, ph, gap, cols = 560, 400, 24, 3
    rows = (len(pages) + cols - 1) // cols
    img = Image.new("RGBA", (cols * (pw + gap) + gap, rows * (ph + gap) + gap), (40, 60, 45, 255))
    draw = ImageDraw.Draw(img)
    title_font, body_font, small = font(30), font(17, False), font(15, False)
    for index, page in enumerate(pages):
        x = gap + (index % cols) * (pw + gap)
        y = gap + (index // cols) * (ph + gap)
        draw.rounded_rectangle([x, y, x + pw, y + ph], radius=20, fill=(24, 26, 38, 255))
        pic = [x + 16, y + 16, x + pw - 16, y + 16 + int(ph * 0.36)]
        draw.rounded_rectangle(pic, radius=14, fill=(44, 48, 68, 255))
        icons = page["icons"]
        by_width = (pic[2] - pic[0] - 24 - (len(icons) - 1) * 12) / len(icons)
        size = int(min((pic[3] - pic[1]) * 0.72, by_width))
        total = len(icons) * size + (len(icons) - 1) * 12
        ix = (pic[0] + pic[2]) // 2 - total // 2
        for role in icons:
            ic = icon(data["icons"][role], data["rings"][role], size)
            img.alpha_composite(ic, (ix, (pic[1] + pic[3]) // 2 - ic.height // 2))
            ix += size + 12
        tw = draw.textlength(page["title"], font=title_font)
        draw.text((x + (pw - tw) / 2, pic[3] + 10), page["title"], font=title_font, fill=(255, 255, 255, 255))
        ty = pic[3] + 56
        for line in wrap(draw, page["body"], body_font, pw - 60):
            lw = draw.textlength(line, font=body_font)
            draw.text((x + (pw - lw) / 2, ty), line, font=body_font, fill=(200, 205, 220, 255))
            ty += 24
        draw.text((x + 20, y + ph - 36), f"{index + 1} / {len(pages)}", font=small, fill=(200, 205, 220, 255))
        label = data["buttons"]["done"] if index == len(pages) - 1 else data["buttons"]["nextText"]
        bx = [x + pw - 170, y + ph - 58, x + pw - 16, y + ph - 16]
        draw.rounded_rectangle(bx, radius=12, fill=(90, 200, 110, 255))
        bw = draw.textlength(label, font=font(20))
        draw.text(((bx[0] + bx[2] - bw) / 2, bx[1] + 9), label, font=font(20), fill=(255, 255, 255, 255))
    img.convert("RGB").save(path)


def monster_page(data, path):
    """The lobby's Monster window (BuildLobbyUI MonsterWindow), first skin worn."""
    m = data["monster"]
    W, H = 960, 640
    img = Image.new("RGBA", (W + 80, H + 80), (40, 60, 45, 255))
    draw = ImageDraw.Draw(img)
    ox, oy = 40, 40
    panel, light, gold, sub = (24, 26, 38, 255), (44, 48, 68, 255), (255, 210, 90, 255), (200, 205, 220, 255)
    draw.rounded_rectangle([ox, oy, ox + W, oy + H], radius=18, fill=panel)
    # banner + X
    bw = W // 2
    bx = ox + (W - bw) // 2
    draw.rounded_rectangle([bx, oy + 10, bx + bw, oy + 56], radius=14, fill=(120, 36, 48, 255), outline=gold, width=2)
    f = font(30)
    tw = draw.textlength(m["name"], font=f)
    draw.text((bx + (bw - tw) / 2, oy + 16), m["name"], font=f, fill=(255, 255, 255, 255))
    draw.rounded_rectangle([ox + W - 54, oy + 10, ox + W - 10, oy + 54], radius=12, fill=(200, 60, 70, 255))
    draw.text((ox + W - 41, oy + 16), "X", font=font(26), fill=(255, 255, 255, 255))
    bottom = 112
    cx, cy = ox + 14, oy + 64
    cw, ch = W - 28, H - 66 - bottom
    lw = int(cw * 0.38) - 6
    # portrait
    draw.rounded_rectangle([cx, cy, cx + lw - 10, cy + 200], radius=14, fill=light)
    ic = icon(m["skins"][0]["shapes"], m["ring"], 180)
    img.alpha_composite(ic, (cx + (lw - 10 - ic.width) // 2, cy + (200 - ic.height) // 2))
    # skins
    sy = cy + 208
    draw.rounded_rectangle([cx, sy, cx + lw - 10, sy + 196], radius=14, fill=light)
    draw.text((cx + 10, sy + 6), m["labels"]["skins"], font=font(20), fill=gold)
    for i, skin in enumerate(m["skins"]):
        x = cx + 8 + i * 80
        if x + 72 > cx + lw - 10:
            break
        draw.rounded_rectangle([x, sy + 38, x + 72, sy + 110], radius=12, fill=panel, outline=gold if i == 0 else None, width=3)
        s_ic = icon(skin["shapes"], m["ring"], 60)
        if i > 1:
            s_ic.putalpha(s_ic.getchannel("A").point(lambda a: int(a * 0.5)))
        img.alpha_composite(s_ic, (x + (72 - s_ic.width) // 2, sy + 38 + (72 - s_ic.height) // 2))
        if i == 0:
            draw.ellipse([x + 52, sy + 34, x + 76, sy + 58], fill=(90, 200, 110, 255))
            draw.text((x + 57, sy + 35), "✓", font=font(17), fill=(255, 255, 255, 255))
    draw.text((cx + 10, sy + 118), m["skins"][0]["name"] + ("  ·  Equipped" if len(m["skins"]) > 1 else ""), font=font(16, False), fill=sub)
    draw.rounded_rectangle([cx + 8, sy + 144, cx + 128, sy + 188], radius=12, fill=(80, 160, 255, 140))
    draw.text((cx + 26, sy + 155), "Equipped", font=font(18), fill=(255, 255, 255, 255))
    # right column
    rx, rw = cx + lw + 12, cw - lw - 12
    y = cy
    draw.rounded_rectangle([rx, y, rx + rw - 10, y + 160], radius=12, fill=light)
    draw.text((rx + 10, y + 6), m["labels"]["stats"], font=font(20), fill=gold)
    for i, (name, value) in enumerate(m["stats"]):
        ry = y + 6 + (i + 1) * 30
        draw.text((rx + 10, ry + 2), name, font=font(17, False), fill=(255, 255, 255, 255))
        pw = (rw - 30) * 0.55
        px = rx + rw - 20 - pw
        for p in range(5):
            dx = px + p * (pw / 5)
            draw.rounded_rectangle([dx, ry + 6, dx + pw / 5 - 4, ry + 20], radius=5, fill=gold if p < value else panel)
    y += 168
    body = font(15, False)
    for i, (title, text) in enumerate(m["boxes"]):
        lines = wrap(draw, text, body, rw - 40)
        h = 40 + len(lines) * 20
        fill = (70, 56, 44, 255) if i == 3 else light
        if y + h > cy + ch:
            draw.text((rx + 10, y), "(scrolls)", font=font(14, False), fill=sub)
            break
        draw.rounded_rectangle([rx, y, rx + rw - 10, y + h], radius=12, fill=fill)
        draw.text((rx + 10, y + 8), title, font=font(19), fill=gold)
        for j, line in enumerate(lines):
            draw.text((rx + 10, y + 34 + j * 20), line, font=body, fill=(240, 225, 200, 255) if i == 3 else sub)
        y += h + 8
    # carousel + Select
    ky = oy + H - 8 - 96
    x = ox + 14 - 98
    for index, shapes in enumerate(m.get("carousel") or [m["skins"][0]["shapes"]], start=1):
        x += 98
        current = index == m.get("current", 1)
        draw.rounded_rectangle([x, ky + 4, x + 88, ky + 92], radius=12, fill=light, outline=gold if current else None, width=3)
        c_ic = icon(shapes, m["ring"], 76)
        img.alpha_composite(c_ic, (x + (88 - c_ic.width) // 2, ky + 4 + (88 - c_ic.height) // 2))
    for k in range(m["locked"]):
        x += 98
        draw.rounded_rectangle([x, ky + 4, x + 88, ky + 92], radius=12, fill=light)
        draw.text((x + 30, ky + 18), "?", font=font(50), fill=sub)
    sx = ox + W - 14 - 160
    draw.rounded_rectangle([sx, oy + H - 26 - 54, sx + 160, oy + H - 26], radius=12, fill=(90, 200, 110, 140))
    label = m["labels"]["select"]
    tw = draw.textlength(label, font=font(24))
    draw.text((sx + (160 - tw) / 2, oy + H - 26 - 42), label, font=font(24), fill=(255, 255, 255, 255))
    img.convert("RGB").save(path)


if __name__ == "__main__":
    data = json.load(open(sys.argv[1]))
    sheet(data, sys.argv[2])
    if len(sys.argv) > 3:
        mock(data, sys.argv[3])
    if len(sys.argv) > 4 and data.get("tutorial"):
        tutorial(data, sys.argv[4])
    if len(sys.argv) > 5 and data.get("monster"):
        monster_page(data, sys.argv[5])

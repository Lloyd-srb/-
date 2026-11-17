"""
Draws the role icons (exported by export.luau) the way the game builds them:
rounded frames on a 100x100 grid, clipped to a circle, with a faction ring.

  python3 tools/roleicons/render.py icons.json docs/role_icons.png [docs/role_roll_mock.png]

The second image is a mock-up of the intro screen (the reel stopped on one role).
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


if __name__ == "__main__":
    data = json.load(open(sys.argv[1]))
    sheet(data, sys.argv[2])
    if len(sys.argv) > 3:
        mock(data, sys.argv[3])

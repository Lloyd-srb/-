"""
Top-down picture of the Match map from out/parts.csv (written by
tools/build_place.luau). North (-Z) is up, east (+X) is right.

  python3 tools/maprender/render.py out/parts.csv docs/map_topdown.png

Each part is drawn as its footprint seen from above, lowest first, so roofs
and treetops cover what is under them. Invisible parts are skipped.
"""
import csv
import math
import sys

from PIL import Image, ImageDraw, ImageFont

SIZE = 1800  # pixels
HALF = 215  # studs from the centre shown in each direction
LEGEND = 520  # pixels for the legend on the right
SS = 2  # supersampling

HOUSE_COUNT, HOUSE_RING = 12, 64
FENCE, FOREST = 96, 200
RIVER_ANGLE, PIER_RADIUS = math.radians(45), 128 + 15


def font(size, bold=True):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/" + name, size)
    except OSError:
        return ImageFont.load_default()


def thai_font(size):
    for path in (
        "/usr/share/fonts/truetype/noto/NotoSansThai-Bold.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansThai-Bold.ttf",
        "/usr/share/fonts/truetype/tlwg/Garuda-Bold.ttf",
        "/usr/share/fonts/truetype/tlwg/Loma-Bold.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return None


def load(path):
    parts = []
    with open(path, newline="") as handle:
        for row in csv.reader(handle):
            name = row[0]
            x, y, z, sx, sy, sz, lx, lz, ux, uy = map(float, row[2:12])
            r, g, b = map(int, row[12:15])
            transparency = float(row[15])
            parts.append((name, x, y, z, sx, sy, sz, lx, lz, uy, (r, g, b), transparency))
    return parts


def main(src, out):
    parts = load(src)
    big = SIZE * SS
    scale = big / (HALF * 2)

    def px(x, z):
        return ((x + HALF) * scale, (z + HALF) * scale)

    img = Image.new("RGBA", (big, big), (32, 52, 34, 255))
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    def top(part):
        name, x, y, z, sx, sy, sz, lx, lz, uy, color, t = part
        # A standing cylinder is turned on its side: its height is along X.
        return y + (sy / 2 if uy > 0.5 else sx / 2)

    for part in sorted(parts, key=top):
        name, x, y, z, sx, sy, sz, lx, lz, uy, color, t = part
        if t >= 0.95 or name in ("Markers",):
            continue
        # Light with height so stacked things read apart.
        shade = max(0.75, min(1.25, 0.9 + top(part) / 60))
        rgb = tuple(max(0, min(255, int(c * shade))) for c in color)
        alpha = int(255 * (1 - t))
        if uy < 0.5:  # a cylinder standing up (ground discs, table, bell)
            radius = max(sy, sz) / 2 * scale
            cx, cy = px(x, z)
            draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=rgb + (alpha,))
            continue
        # Footprint: local X along the right vector, local Z along -look.
        rx, rz = -lz, lx
        hx, hz = sx / 2, sz / 2
        corners = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            cx = x + rx * a * hx + lx * b * hz
            cz = z + rz * a * hx + lz * b * hz
            corners.append(px(cx, cz))
        draw.polygon(corners, fill=rgb + (alpha,))
    img.alpha_composite(layer)

    # Outlines and labels.
    ann = ImageDraw.Draw(img)
    cx0, cy0 = px(0, 0)
    # River: a huge circle (see build/BuildVillage.luau buildRiver).
    river_c = (math.sin(RIVER_ANGLE) * (128 + 333), -math.cos(RIVER_ANGLE) * (128 + 333))

    def wet(x, z):
        return math.hypot(x - river_c[0], z - river_c[1]) < 333

    for radius, color, width in ((FENCE, (255, 255, 255, 150), 3), (FOREST, (255, 80, 80, 200), 4)):
        steps = 720
        for i in range(steps):
            a1, a2 = i / steps * math.tau, (i + 1) / steps * math.tau
            p1 = (math.sin(a1) * radius, -math.cos(a1) * radius)
            p2 = (math.sin(a2) * radius, -math.cos(a2) * radius)
            if not wet(*p1) and not wet(*p2):
                ann.line([px(*p1), px(*p2)], fill=color, width=width * SS)

    label = font(26 * SS)
    small = font(20 * SS)
    for house in range(1, HOUSE_COUNT + 1):
        angle = (house - 1) / HOUSE_COUNT * math.pi * 2
        hx, hz = math.sin(angle) * HOUSE_RING, -math.cos(angle) * HOUSE_RING
        x, y = px(hx, hz)
        text = str(house)
        r = 20 * SS
        ann.ellipse([x - r, y - r, x + r, y + r], fill=(20, 24, 36, 220), outline=(255, 210, 90, 255), width=2 * SS)
        w = ann.textlength(text, font=label)
        ann.text((x - w / 2, y - 16 * SS), text, font=label, fill=(255, 255, 255, 255))

    def tag(text, x, z, fill=(255, 255, 255, 255), back=(20, 24, 36, 210)):
        tx, ty = px(x, z)
        w = ann.textlength(text, font=small)
        pad = 8 * SS
        ann.rounded_rectangle([tx - w / 2 - pad, ty - 14 * SS - pad / 2, tx + w / 2 + pad, ty + 14 * SS + pad / 2], radius=8 * SS, fill=back)
        ann.text((tx - w / 2, ty - 12 * SS), text, font=small, fill=fill)

    tag("Plaza + meeting table", 0, 18)
    sx, sz = math.sin(RIVER_ANGLE) * PIER_RADIUS, -math.cos(RIVER_ANGLE) * PIER_RADIUS
    tag("Pier (fetch water / fishing)", sx - 46, sz - 22, fill=(255, 225, 170, 255))
    tag("River", 150, -150, fill=(200, 235, 255, 255), back=(20, 60, 110, 210))
    tag("Village (inside the fence)", 0, -FENCE + 12)
    tag("Forest (glows red for the wolf at night)", 0, -FENCE - 40, fill=(255, 170, 170, 255))
    tag("Invisible wall", -150, 150, fill=(255, 120, 120, 255))
    # Compass.
    ax, ay = 70 * SS, 70 * SS
    ann.polygon([(ax, ay - 40 * SS), (ax - 18 * SS, ay + 10 * SS), (ax + 18 * SS, ay + 10 * SS)], fill=(255, 255, 255, 230))
    ann.text((ax - 12 * SS, ay + 14 * SS), "N", font=label, fill=(255, 255, 255, 255))

    final = img.resize((SIZE, SIZE), Image.LANCZOS)

    # Legend panel.
    sheet = Image.new("RGBA", (SIZE + LEGEND, SIZE), (24, 26, 38, 255))
    sheet.alpha_composite(final, (0, 0))
    d = ImageDraw.Draw(sheet)
    title, body = font(34), font(22, False)
    d.text((SIZE + 30, 30), "Wolf Village - map", font=title, fill=(255, 255, 255, 255))
    d.text((SIZE + 30, 76), "Top-down, north (-Z) up", font=body, fill=(200, 205, 220, 255))
    th = thai_font(24)
    if th:
        d.text((SIZE + 30, 108), "มุมมองจากด้านบน ทิศเหนืออยู่ด้านบน", font=th, fill=(200, 205, 220, 255))
    rows = [
        ((226, 202, 158), "Plaza (r 30): meeting table"),
        ((126, 196, 96), "Village grass (r 96)"),
        ((255, 255, 255), "Fence = village / forest line"),
        ((240, 160, 70), "12 houses (coloured roofs, r 64)"),
        ((110, 80, 50), "Carrot plots behind the houses"),
        ((110, 210, 120), "Task trees (44) in the forest"),
        ((150, 150, 160), "Rocks / bushes"),
        ((90, 160, 210), "River (top right) + pier"),
        ((214, 196, 150), "Beach along the river"),
        ((255, 80, 80), "Invisible wall (r 200)"),
        ((25, 60, 30), "Dark outer forest (scenery)"),
    ]
    y = 160
    for color, text in rows:
        d.rounded_rectangle([SIZE + 30, y, SIZE + 62, y + 32], radius=6, fill=color + (255,))
        d.text((SIZE + 78, y + 2), text, font=body, fill=(230, 232, 240, 255))
        y += 48
    notes = [
        "Scale: 1 grid unit = 1 stud;",
        "the whole image is 430 x 430 studs.",
        "Walk from the plaza to the pier end:",
        "about 155 studs (~10 s at speed 16).",
        "The river cannot be entered;",
        "only the pier goes out over it.",
    ]
    y += 20
    for line in notes:
        d.text((SIZE + 30, y), line, font=body, fill=(200, 205, 220, 255))
        y += 32
    sheet.convert("RGB").save(out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

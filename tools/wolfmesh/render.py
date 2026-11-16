"""
Offline preview: skins the imported wolf mesh with bone matrices solved by the
game's BoneRetarget code (tools/wolfmesh/poses.luau) and draws front / side
views of each pose. Used to check that the model does not tear when animated.

Usage: python3 tools/wolfmesh/render.py <skin.json> <poses.json> <out_dir>
(skin.json is exported from the FBX; it is not kept in the repo.)
"""
import json, math, sys
import numpy as np
from PIL import Image, ImageDraw

skin = json.load(open(sys.argv[1]))
poses = json.load(open(sys.argv[2]))
out_dir = sys.argv[3]

yaw = poses['yaw']
turn = np.eye(4)
turn[:3, :3] = [[math.cos(yaw), 0, math.sin(yaw)], [0, 1, 0], [-math.sin(yaw), 0, math.cos(yaw)]]

verts = np.array(skin['verts'])
verts_h = np.c_[verts, np.ones(len(verts))] @ turn.T  # rig space
tris = np.array(skin['tris'])
names = skin['bones']
inverse_bind = {name: np.linalg.inv(turn @ np.array(m)) for name, m in skin['bind'].items()}

def matrix(components):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = components
    return np.array([[r00, r01, r02, x], [r10, r11, r12, y], [r20, r21, r22, z], [0, 0, 0, 1]])

def skinned(shot):
    result = np.zeros((len(verts), 3))
    per_bone = {}
    for name, inv in inverse_bind.items():
        per_bone[name] = (matrix(shot[name]) @ inv)
    for index, influences in enumerate(skin['influences']):
        v = verts_h[index]
        total = sum(w for _, w in influences)
        for bone, weight in influences:
            result[index] += (per_bone[names[bone]] @ v)[:3] * (weight / total)
    return result

def draw(points, view, size=420, extent=1.75):
    # view "front": camera in front of the model (it faces -Z); "side": from its left.
    if view == 'front':
        sx, depth = -points[:, 0], -points[:, 2]
    else:
        sx, depth = -points[:, 2], -points[:, 0]
    sy = points[:, 1]
    image = Image.new('RGB', (size, size), (24, 26, 34))
    canvas = ImageDraw.Draw(image)
    scale = size / (2 * extent)
    px = (sx + extent) * scale
    py = size - (sy + 0.25) * scale
    ground = size - 0.25 * scale
    canvas.line([(0, ground), (size, ground)], fill=(70, 80, 70))
    a, b, c = points[tris[:, 0]], points[tris[:, 1]], points[tris[:, 2]]
    normals = np.cross(b - a, c - a)
    lengths = np.linalg.norm(normals, axis=1)
    normals = normals / np.maximum(lengths, 1e-9)[:, None]
    light = np.array([0.35, 0.6, -0.72]) if view == 'front' else np.array([-0.72, 0.6, -0.35])
    shade = np.abs(normals @ light) * 0.75 + 0.25
    order = np.argsort(depth[tris].mean(axis=1))
    for t in order:
        i, j, k = tris[t]
        g = int(60 + 170 * shade[t])
        canvas.polygon([(px[i], py[i]), (px[j], py[j]), (px[k], py[k])], fill=(g, g, min(255, g + 12)))
    return image

report = {}
rest = skinned(poses['shots']['TPose'])
report['tpose_error'] = float(np.abs(rest - verts_h[:, :3]).max())
for name in poses['order']:
    points = skinned(poses['shots'][name])
    sheet = Image.new('RGB', (840, 440), (24, 26, 34))
    sheet.paste(draw(points, 'front'), (0, 20))
    sheet.paste(draw(points, 'side'), (420, 20))
    ImageDraw.Draw(sheet).text((8, 4), name + '   (front view | side view)', fill=(230, 230, 230))
    sheet.save(f'{out_dir}/{name}.png')
    # Stretch check: how much do triangle edges grow compared with the rest pose?
    def edges(p):
        return np.r_[np.linalg.norm(p[tris[:, 0]] - p[tris[:, 1]], axis=1), np.linalg.norm(p[tris[:, 1]] - p[tris[:, 2]], axis=1), np.linalg.norm(p[tris[:, 2]] - p[tris[:, 0]], axis=1)]
    ratio = edges(points) / np.maximum(edges(verts_h[:, :3]), 1e-6)
    report[name] = {'min_y': round(float(points[:, 1].min()), 3), 'max_y': round(float(points[:, 1].max()), 3),
                    'edges_stretched_over_3x': int((ratio > 3).sum()), 'worst_stretch': round(float(ratio.max()), 1)}
print(json.dumps(report, indent=1))

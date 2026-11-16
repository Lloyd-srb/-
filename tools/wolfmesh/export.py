"""Exports the skeleton (for the repo test fixture) and the skin (for preview renders) from the FBX."""
import sys, json, math
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from fbxinfo import read_fbx, arr, find
import numpy as np

path, skeleton_out, skin_out = sys.argv[1:4]
version, nodes = read_fbx(path)
top = {n[0]: n for n in nodes}
objects = top['Objects'][2]
names = {o[1][0]: (o[0], o[1][1].split('\x00')[0], o[1][2] if len(o[1]) > 2 else '') for o in objects}

models = {}
for o in objects:
    if o[0] == 'Model':
        props = {}
        for p70 in find(o[2], 'Properties70'):
            for p in p70[2]:
                if p[1] and p[1][0] in ('Lcl Translation', 'Lcl Rotation'):
                    props[p[1][0]] = list(p[1][4:7])
        models[o[1][0]] = {'name': names[o[1][0]][1], 'type': o[1][2], 't': props.get('Lcl Translation', [0, 0, 0]), 'r': props.get('Lcl Rotation', [0, 0, 0])}
parent = {}
for c in top['Connections'][2]:
    if c[1][0] == 'OO' and c[1][1] in models and c[1][2] in models:
        parent[c[1][1]] = c[1][2]

def rot(r):
    rx, ry, rz = map(math.radians, r)
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]]); Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]); Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx

def local(m):
    M = np.eye(4); M[:3, :3] = rot(m['r']); M[:3, 3] = m['t']; return M

world = {}
def get_world(i):
    if i not in world:
        world[i] = (get_world(parent[i]) if i in parent else np.eye(4)) @ local(models[i])
    return world[i]

# bones in parent-first order
bones = []
def walk(i):
    m = models[i]
    if m['type'] == 'LimbNode':
        par = parent.get(i)
        bones.append({'name': m['name'], 'parent': models[par]['name'] if par in models and models[par]['type'] == 'LimbNode' else None,
                      't': [round(x, 6) for x in m['t']], 'r': [round(x, 6) for x in m['r']]})
    for c in [k for k, v in parent.items() if v == i]:
        walk(c)
for root in [i for i in models if i not in parent]:
    walk(root)

geo = [o for o in objects if o[0] == 'Geometry'][0]
verts = np.array(arr(find(geo[2], 'Vertices')[0][1][0])).reshape(-1, 3)
idx = arr(find(geo[2], 'PolygonVertexIndex')[0][1][0])
tris, poly = [], []
for i in idx:
    if i < 0:
        poly.append(-i - 1)
        for k in range(1, len(poly) - 1):
            tris.append([poly[0], poly[k], poly[k + 1]])
        poly = []
    else:
        poly.append(i)

clusters = {o[1][0]: o for o in objects if o[0] == 'Deformer' and o[1][2] == 'Cluster'}
bone_of = {}
for c in top['Connections'][2]:
    if c[1][0] == 'OO' and c[1][2] in clusters and c[1][1] in models:
        bone_of[c[1][2]] = c[1][1]
index_of = {b['name']: n for n, b in enumerate(bones)}
influences = [[] for _ in range(len(verts))]
bind = {}
worst = 0.0
for cid, o in clusters.items():
    bid = bone_of[cid]; name = models[bid]['name']
    link = np.array(arr(find(o[2], 'TransformLink')[0][1][0])).reshape(4, 4).T  # column-major -> matrix
    bind[name] = link
    worst = max(worst, float(np.abs(link - get_world(bid)).max()))
    ix = find(o[2], 'Indexes')
    if ix and ix[0][1]:
        for i, w in zip(arr(ix[0][1][0]), arr(find(o[2], 'Weights')[0][1][0])):
            influences[i].append((index_of[name], float(w)))
print('bones', len(bones), 'verts', len(verts), 'tris', len(tris), 'rest-vs-bind max error', round(worst, 6))

json.dump({'source': 'Meshy_AI_Moonfang_Stalker character_mixamo.fbx', 'units_height': float(verts[:, 1].max() - verts[:, 1].min()),
           'bounds_min': verts.min(0).round(5).tolist(), 'bounds_max': verts.max(0).round(5).tolist(), 'bones': bones}, open(skeleton_out, 'w'), indent=1)
json.dump({'verts': verts.round(5).tolist(), 'tris': tris, 'influences': influences,
           'bind': {k: v.round(7).tolist() for k, v in bind.items()}, 'bones': [b['name'] for b in bones]}, open(skin_out, 'w'))

import sys, json
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from fbxinfo import read_fbx, arr, find
version, nodes = read_fbx(sys.argv[1])
top = {n[0]: n for n in nodes}
objects = top['Objects'][2]
names = {o[1][0]: (o[0], o[1][1].split('\x00')[0], o[1][2] if len(o[1]) > 2 else '') for o in objects}
geo = [o for o in objects if o[0] == 'Geometry'][0]
verts = arr(find(geo[2], 'Vertices')[0][1][0])
nv = len(verts) // 3
clusters = {o[1][0]: o for o in objects if o[0] == 'Deformer' and o[1][2] == 'Cluster'}
bone_of = {}
for c in top['Connections'][2]:
    if c[1][0] == 'OO' and c[1][2] in clusters and names.get(c[1][1], ('',))[0] == 'Model':
        bone_of[c[1][2]] = names[c[1][1]][1]
total = [0.0] * nv
count = [0] * nv
rows = []
for cid, o in clusters.items():
    idx = find(o[2], 'Indexes'); w = find(o[2], 'Weights')
    if not idx or not idx[0][1]:
        rows.append((bone_of.get(cid, '?'), 0, 0.0, None)); continue
    idx = arr(idx[0][1][0]); w = arr(w[0][1][0])
    xs = [verts[3 * i] for i in idx]; ys = [verts[3 * i + 1] for i in idx]; zs = [verts[3 * i + 2] for i in idx]
    for i, wt in zip(idx, w):
        total[i] += wt; count[i] += 1
    strong = sum(1 for wt in w if wt > 0.5)
    rows.append((bone_of.get(cid, '?'), len(idx), sum(w), strong, [round(min(xs), 2), round(max(xs), 2)], [round(min(ys), 2), round(max(ys), 2)], [round(min(zs), 2), round(max(zs), 2)]))
rows.sort(key=lambda r: -r[2])
print('vertices', nv, 'unweighted', sum(1 for t in total if t < 0.01), 'max influences', max(count))
for r in rows:
    print('%-26s verts=%-6d weight=%-9.1f dominant=%-6s x=%s y=%s z=%s' % (r[0], r[1], r[2], r[3], *(r[4:] if len(r) > 4 else ('', '', ''))))

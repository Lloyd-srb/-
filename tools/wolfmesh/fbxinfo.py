"""Minimal binary FBX reader: prints mesh, skeleton, material and animation facts."""
import struct, sys, zlib, json, collections

def read_fbx(path):
    data = open(path, 'rb').read()
    assert data[:20] == b'Kaydara FBX Binary  ', 'not a binary FBX'
    version = struct.unpack_from('<I', data, 23)[0]
    wide = version >= 7500
    pos = 27

    def read_node(pos):
        if wide:
            end, nprops, plen = struct.unpack_from('<QQQ', data, pos); pos += 24
        else:
            end, nprops, plen = struct.unpack_from('<III', data, pos); pos += 12
        nlen = data[pos]; pos += 1
        name = data[pos:pos + nlen].decode('ascii', 'replace'); pos += nlen
        if end == 0:
            return None, pos
        props = []
        pend = pos + plen
        for _ in range(nprops):
            t = chr(data[pos]); pos += 1
            if t in 'YCIFDL':
                fmt = {'Y': '<h', 'C': '<?', 'I': '<i', 'F': '<f', 'D': '<d', 'L': '<q'}[t]
                props.append(struct.unpack_from(fmt, data, pos)[0]); pos += struct.calcsize(fmt)
            elif t in 'fdlib':
                n, enc, clen = struct.unpack_from('<III', data, pos); pos += 12
                raw = data[pos:pos + clen]; pos += clen
                if enc:
                    raw = zlib.decompress(raw)
                fmt = {'f': 'f', 'd': 'd', 'l': 'q', 'i': 'i', 'b': '?'}[t]
                props.append(('array', t, n, raw))
            elif t in 'SR':
                n = struct.unpack_from('<I', data, pos)[0]; pos += 4
                raw = data[pos:pos + n]; pos += n
                props.append(raw.decode('utf-8', 'replace') if t == 'S' else ('raw', len(raw)))
            else:
                raise ValueError('unknown property type ' + t)
        assert pos == pend
        children = []
        null_len = 25 if wide else 13
        while pos < end:
            child, pos = read_node(pos)
            if child is None:
                break
            children.append(child)
        return (name, props, children), end

    nodes = []
    while pos < len(data) - 200:
        node, pos = read_node(pos)
        if node is None:
            break
        nodes.append(node)
    return version, nodes

def arr(p):
    _, t, n, raw = p
    fmt = {'f': 'f', 'd': 'd', 'l': 'q', 'i': 'i', 'b': '?'}[t]
    return struct.unpack('<%d%s' % (n, fmt), raw)

def find(children, name):
    return [c for c in children if c[0] == name]

def main(path, out_json=None):
    version, nodes = read_fbx(path)
    top = {n[0]: n for n in nodes}
    print('FBX version', version)
    objects = top['Objects'][2]
    kinds = collections.Counter((o[0], o[1][2] if len(o[1]) > 2 else '') for o in objects)
    for k, v in sorted(kinds.items()):
        print('  %-22s %-14s x%d' % (k[0], k[1], v))

    info = {'geometries': [], 'bones': [], 'models': {}, 'textures': [], 'animations': []}
    names = {}
    for o in objects:
        oid = o[1][0]; name = o[1][1].split('\x00')[0] if isinstance(o[1][1], str) else ''
        names[oid] = (o[0], name, o[1][2] if len(o[1]) > 2 else '')

    for o in objects:
        if o[0] == 'Geometry' and o[1][2] == 'Mesh':
            verts = arr(find(o[2], 'Vertices')[0][1][0])
            idx = arr(find(o[2], 'PolygonVertexIndex')[0][1][0])
            polys, tris, size = 0, 0, 0
            for i in idx:
                size += 1
                if i < 0:
                    polys += 1; tris += size - 2; size = 0
            xs, ys, zs = verts[0::3], verts[1::3], verts[2::3]
            g = {'name': names[o[1][0]][1], 'vertices': len(verts) // 3, 'polygons': polys, 'triangles': tris,
                 'min': [min(xs), min(ys), min(zs)], 'max': [max(xs), max(ys), max(zs)],
                 'uv_layers': len(find(o[2], 'LayerElementUV')), 'colors': len(find(o[2], 'LayerElementColor'))}
            info['geometries'].append(g)
            print('MESH', json.dumps(g))
        elif o[0] == 'Model':
            props = {}
            for p70 in find(o[2], 'Properties70'):
                for p in p70[2]:
                    if p[1] and p[1][0] in ('Lcl Translation', 'Lcl Rotation', 'Lcl Scaling', 'PreRotation', 'RotationOrder'):
                        props[p[1][0]] = [round(x, 5) if isinstance(x, float) else x for x in p[1][4:]]
            info['models'][o[1][0]] = {'name': names[o[1][0]][1], 'type': o[1][2], 'props': props}
        elif o[0] in ('Texture', 'Video'):
            fn = [c[1][0] for c in o[2] if c[0] in ('RelativeFilename', 'FileName', 'Filename') and c[1]]
            content = [c for c in o[2] if c[0] == 'Content']
            size = content[0][1][0][1] if content and content[0][1] and isinstance(content[0][1][0], tuple) else 0
            info['textures'].append({'kind': o[0], 'name': names[o[1][0]][1], 'file': fn[:1], 'embedded_bytes': size})
        elif o[0] == 'AnimationStack':
            info['animations'].append(names[o[1][0]][1])
        elif o[0] == 'Material':
            print('MATERIAL', names[o[1][0]][1])

    # hierarchy from connections
    parent = {}
    for c in top['Connections'][2]:
        if c[1][0] == 'OO':
            child, par = c[1][1], c[1][2]
            if child in info['models'] and (par in info['models'] or par == 0):
                parent[child] = par
    def depth(i):
        d = 0
        while parent.get(i, 0) in info['models']:
            i = parent[i]; d += 1
        return d
    print('MODELS (hierarchy):')
    order = []
    def walk(par, d):
        for cid in [k for k, v in parent.items() if v == par]:
            m = info['models'][cid]
            order.append((d, m))
            walk(cid, d + 1)
    walk(0, 0)
    for d, m in order:
        print('  ' + '  ' * d + '%s [%s] T=%s R=%s S=%s pre=%s' % (m['name'], m['type'], m['props'].get('Lcl Translation'), m['props'].get('Lcl Rotation'), m['props'].get('Lcl Scaling'), m['props'].get('PreRotation')))
    print('TEXTURES', json.dumps(info['textures']))
    print('ANIMATIONS', info['animations'])
    gs = top.get('GlobalSettings')
    if gs:
        for p in gs[2][-1][2]:
            if p[1] and p[1][0] in ('UpAxis', 'FrontAxis', 'CoordAxis', 'UnitScaleFactor', 'OriginalUnitScaleFactor'):
                print('  setting', p[1][0], p[1][4:])
    if out_json:
        json.dump({'geometries': info['geometries'], 'order': [(d, m) for d, m in order], 'textures': info['textures'], 'animations': info['animations']}, open(out_json, 'w'), indent=1)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)

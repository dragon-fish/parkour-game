"""Merge tutorial sublevels into one Godot-space blockout manifest."""
import sys, os, math, json, subprocess
sys.stdout.reconfigure(encoding='utf-8')
from mapdump import MapReader
from hulls import HullReader

SP = os.path.dirname(os.path.abspath(__file__))
MAPS = sys.argv[1]
OUT = sys.argv[2]
FILES = sys.argv[3:]

UU = 100.0          # 1 uu = 1 cm  ->  metres
ROT = 360.0 / 65536.0

# UE3 is LEFT-handed (X forward, Y right, Z up); Godot is RIGHT-handed.
# Converting between opposite handedness REQUIRES a mapping whose determinant
# is -1. The first version used (x, z, -y), whose determinant is +1, so it
# preserved handedness and silently produced a MIRRORED level -- everything
# present and correctly sized, but flipped. Keeping Z positive gives
# det = -1 and leaves X/Y untouched.
def to_godot(x, y, z):
    return (x / UU, z / UU, y / UU)


def godot_basis(rot, scale):
    """UE3 rotator + scale -> Godot basis columns.

    Everything is built in UE space, then conjugated by the same axis map used
    for positions (M swaps Y and Z and is its own inverse): B = M * R * S * M.
    Doing it this way avoids re-deriving Euler conventions in the target space,
    which is where sign errors like the mirrored level came from.
    """
    p, y_, r = (a * ROT * math.pi / 180.0 for a in (rot[0], rot[1], rot[2]))
    sp, sy, sr = math.sin(p), math.sin(y_), math.sin(r)
    cp, cy, cr = math.cos(p), math.cos(y_), math.cos(r)
    # UE FRotationMatrix rows (row-vector convention)
    rows = [
        (cp * cy, cp * sy, sp),
        (sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp),
        (-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp),
    ]
    # column-vector matrix R[i][j], then fold per-axis scale (applied in mesh space)
    R = [[rows[j][i] * scale[j] for j in range(3)] for i in range(3)]
    swap = (0, 2, 1)                      # M as an index permutation
    B = [[R[swap[i]][swap[j]] for j in range(3)] for i in range(3)]
    # emit as three column vectors, which is what Godot's Basis(x, y, z) wants
    return [[round(B[i][j], 6) for i in range(3)] for j in range(3)]
USE_ORG = os.environ.get('USE_ORG', '1') != '0'


def ref_index(v):
    return v[1] if (isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj' and v[1] > 0) else None


def imp_index(v):
    """0-based position into pkg.imports for a negative object reference."""
    if isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj' and v[1] < 0:
        return -v[1] - 1
    return None


def imp_root_pkg(pkg, i):
    """Root package name of import #i (0-based), walking the outer chain."""
    e = pkg.imports[i]
    while True:
        o = e.get('outer', 0)
        if not o:
            return e['name']
        if o < 0:
            e = pkg.imports[-o - 1]
        else:
            return pkg.exports[o - 1]['name']


def sane_bounds(b):
    """FBoxSphereBounds sanity: the sphere reaches the farthest VERTEX, so it
    is legitimately shorter than the box diagonal but never longer."""
    ex, ey, ez, r = b[3], b[4], b[5], b[6]
    diag = math.sqrt(ex * ex + ey * ey + ez * ez)
    return diag > 0 and 0.40 <= r / diag <= 1.05 and min(ex, ey, ez) >= 0 and r < 1e6


# A cooked persistent map does not necessarily embed its meshes. Tutorial_Art
# and Tutorial_Bac cook theirs in (125/89 StaticMesh exports), but Tutorial_p
# has ZERO -- its 852 mesh references are IMPORTS into 26 shared packages
# (P_Renovation, P_Catwalks, ...) elsewhere under CookedPC. DO NOT assume
# in-package resolution is enough because two sublevels happened to work; the
# persistent level is the one that loses 900+ placements silently.
# Shared packages are found by indexing *.upk under the CookedPC root (derived
# from the MAPS argument), loaded lazily, and keyed by mesh NAME.
COOKED_SKIP = {'engine', 'core', 'tdgame', 'gameframework', 'unrealed'}
_upk_index = None
_lib_bounds = {}      # mesh name -> ((ox,oy,oz), (ex,ey,ez))
_lib_hulls = {}       # mesh name -> hulls in HullReader's raw shape
_libs_loaded = set()


def _find_cooked_root(path):
    p2 = os.path.abspath(path)
    while True:
        if os.path.basename(p2).lower() == 'cookedpc':
            return p2
        np2 = os.path.dirname(p2)
        if np2 == p2:
            return None
        p2 = np2


def _index_upks():
    global _upk_index
    _upk_index = {}
    root_dir = _find_cooked_root(MAPS)
    if not root_dir:
        return
    for root, _dirs, files in os.walk(root_dir):
        for fn in files:
            if fn.lower().endswith('.upk'):
                _upk_index.setdefault(fn[:-4].lower(), os.path.join(root, fn))


def _pkg_cflags(path):
    """CompressionFlags out of a UE3 package header (same walk as
    ue3_decompress.py)."""
    import struct
    with open(path, 'rb') as fh:
        raw = fh.read(4096)
    off = 12
    slen, = struct.unpack_from('<i', raw, off); off += 4
    off += slen if slen >= 0 else -slen * 2
    off += 4 + 28 + 16
    gencount, = struct.unpack_from('<i', raw, off); off += 4
    off += gencount * 12 + 8
    return struct.unpack_from('<I', raw, off)[0]


def load_lib(name):
    """Harvest StaticMesh bounds and hulls from shared package `name`, once."""
    key = name.lower()
    if key in _libs_loaded or key in COOKED_SKIP:
        return
    _libs_loaded.add(key)
    if _upk_index is None:
        _index_upks()
    src = _upk_index.get(key)
    if not src:
        return
    # Shared prop/building packages ship UNCOMPRESSED (CompressionFlags 0),
    # unlike the LZO-chunked .me1 maps -- read those in place.
    dec = src if _pkg_cflags(src) == 0 else os.path.join(SP, name + '.upk.dec')
    if not os.path.exists(dec):
        subprocess.run([sys.executable, os.path.join(SP, 'ue3_decompress.py'), src, dec],
                       check=True, capture_output=True)
    mr = MapReader(dec)
    pkg = mr.pkg
    n_b = 0
    for i, e in enumerate(pkg.exports):
        if pkg.class_of(e) != 'StaticMesh':
            continue
        b = mr.bounds(i + 1)
        if b and sane_bounds(b):
            _lib_bounds.setdefault(e['name'], ((b[0], b[1], b[2]), (b[3], b[4], b[5])))
            n_b += 1
    n_h = 0
    for mesh, hs in HullReader(dec).by_mesh().items():
        if mesh not in _lib_hulls:
            _lib_hulls[mesh] = hs
            n_h += 1
    print("    共享包 %-22s -> %4d 网格包围盒, %3d 凸包网格" % (name, n_b, n_h))


# Actor classes worth carrying into the blockout as markers. These are what
# tell you WHERE each mechanic was meant to be used -- far more informative
# than the geometry alone.
#
# The three checkpoint classes are now told apart instead of being mixed into
# one point cloud (the README's own complaint): TdTutorialCheckpoint (teaching
# progress dots) stays the `path`, TdCheckpointVolume (respawn volumes, with
# their real brush shape) and the one TdCheckpoint (the level's master
# checkpoint) become first-class markers.
MARKER_CLASSES = {
    'TdZiplineVolume': 'zipline',
    'TdSwingVolume': 'swing',
    'TdBalanceWalkVolume': 'balance',
    'TdLedgeWalkVolume': 'ledgewalk',
    'TdLadderVolume': 'ladder',
    'TdBarbedWireVolume': 'barbedwire',
    'TdTriggerVolume': 'trigger',
    'BlockingVolume': 'blocking',
    'TdLookAtPoint': 'lookat',
    'PathNode': 'pathnode',
    'BookMark': 'bookmark',
    'InterpActor': 'mover',
    'TdCheckpointVolume': 'checkpointvolume',
    'TdCheckpoint': 'checkpoint',
}


def dir_godot(v):
    """UE3 direction -> unit Godot direction (axis map only, no unit scale)."""
    n = (v[0], v[2], v[1])
    ln = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
    return [round(c / ln, 4) for c in n]


def pt(v):
    return [round(c, 3) for c in to_godot(v[0], v[1], v[2])]


# One volume in the wild (TdBarbedWireVolume_12) carries NaN in its Start and
# SplineLocations. Python's json writes NaN happily and Godot's parser then
# rejects the WHOLE file -- drop non-finite vectors at the source.
def finite(v):
    return all(c == c and abs(c) < 1e30 for c in v)


def _raw_entry(mr, idx, name):
    chain, _ = mr.chain_of(idx)
    for (n, typ, extra, q, sz, arr) in chain:
        if n == name:
            return (typ, extra, q, sz)
    return None


def vec_array(mr, idx, name):
    """A raw ArrayProperty of FVector on export #idx, or None."""
    import struct
    r = _raw_entry(mr, idx, name)
    if not r:
        return None
    _, _, q, sz = r
    cnt = struct.unpack_from('<i', mr.d, q)[0]
    if cnt <= 0 or sz - 4 < cnt * 12:
        return None
    return [struct.unpack_from('<3f', mr.d, q + 4 + i * 12) for i in range(cnt)]


def brush_hulls(mr, comp_idx):
    """KConvexElem hulls out of a BrushComponent's BrushAggGeom -- the same
    FKAggregateGeom that hulls.py reads from RB_BodySetup.AggGeom (12 sec
    12.2: all 129 volumes resolve this way, one 8-vertex box hull each).
    Vertices are LOCAL and unscaled; the marker's basis carries rotation and
    scale."""
    import struct
    r = _raw_entry(mr, comp_idx, 'BrushAggGeom')
    if not r:
        return None
    _, _, q, sz = r
    ok, tags, _ = mr._chain(q, q + sz)
    for (n, _t, _x, q2, sz2, _a) in tags:
        if n != 'ConvexElems':
            continue
        cnt = struct.unpack_from('<i', mr.d, q2)[0]
        p = q2 + 4
        limit = q2 + sz2
        hulls = []
        for _ in range(max(cnt, 0)):
            ok2, elem, _nat = mr._chain(p, limit)
            if not elem:
                break
            verts, tris = None, []
            for (en, _et, _ex, eq, esz, _ea) in elem:
                if en == 'VertexData':
                    c2 = struct.unpack_from('<i', mr.d, eq)[0]
                    if c2 > 0 and esz - 4 >= c2 * 12:
                        verts = [struct.unpack_from('<3f', mr.d, eq + 4 + i * 12)
                                 for i in range(c2)]
                elif en == 'FaceTriData':
                    c2 = struct.unpack_from('<i', mr.d, eq)[0]
                    if c2 > 0 and esz - 4 >= c2 * 4:
                        tris = list(struct.unpack_from('<%di' % c2, mr.d, eq + 4))
            last = elem[-1]
            p = last[3] + last[4]
            while p + 8 <= limit:
                ni = struct.unpack_from('<i', mr.d, p)[0]
                if mr.nm(ni) == 'None':
                    p += 8
                    break
                p += 4
            if verts:
                hulls.append({'v': [pt(v) for v in verts], 't': tris})
        return hulls or None
    return None


def collect_annotations(dec_path):
    """Teaching-progress dots (path), spawn points (with facing) and gameplay
    markers. A marker carries everything the map knows about it:

      kind, pos, name           always
      basis                     when rotated/scaled (same convention as boxes)
      start/end/middle          the volume's own line, metres, Godot space
      wall/dir/floor            unit directions (WallNormal / MoveDirection /
                                FloorNormal) -- `wall` is what a ledge's or
                                ladder's facing is authored against
      spline                    SplineLocations, the real curve (a zipline's
                                sag lives here, 11 points over 88 m)
      hull                      the volume's convex shape, local space,
                                {v: verts, t: tri indices} per element
      cyl                       [radius, height] for cylinder-touch actors

    The importer maps these onto the project's own nodes (InterestLine,
    Checkpoint, SpawnPoint, blocking StaticBody3D, BarbedWire) instead of the
    old anonymous red dots."""
    mr = MapReader(dec_path)
    pkg = mr.pkg
    path, spawns, markers = [], [], []
    for i, e in enumerate(pkg.exports):
        cls = pkg.class_of(e)
        kind = MARKER_CLASSES.get(cls)
        is_path = cls == 'TdTutorialCheckpoint'
        is_spawn = cls == 'TdTutorialStart'
        if not (is_path or kind or is_spawn):
            continue
        pr, _ = mr.props(i + 1)
        if not pr or 'Location' not in pr:
            continue
        l = pr['Location']
        p = pt(l)
        if is_spawn:
            rot = pr.get('Rotation') or (0, 0, 0)
            spawns.append({'pos': p, 'yaw': round(rot[1] * ROT, 1), 'name': e['name']})
            continue
        if is_path:
            path.append(p)
            continue
        m = {'kind': kind, 'pos': p, 'name': e['name']}
        rot = pr.get('Rotation') or (0, 0, 0)
        s3 = pr.get('DrawScale3D') or (1.0, 1.0, 1.0)
        ds = pr.get('DrawScale')
        ds = ds if isinstance(ds, float) else 1.0
        scale = (ds * s3[0], ds * s3[1], ds * s3[2])
        if tuple(rot) != (0, 0, 0) or scale != (1.0, 1.0, 1.0):
            m['basis'] = godot_basis(rot, scale)
        for k_src, k_out in (('Start', 'start'), ('End', 'end'), ('Middle', 'middle')):
            v = pr.get(k_src)
            if isinstance(v, tuple) and len(v) == 3 and finite(v):
                m[k_out] = pt(v)
        for k_src, k_out in (('WallNormal', 'wall'), ('MoveDirection', 'dir'),
                             ('FloorNormal', 'floor')):
            v = pr.get(k_src)
            if isinstance(v, tuple) and len(v) == 3 and finite(v):
                m[k_out] = dir_godot(v)
        sp = vec_array(mr, i + 1, 'SplineLocations')
        if sp and len(sp) > 2 and all(finite(v) for v in sp):
            m['spline'] = [pt(v) for v in sp]
        comp = ref_index(pr.get('BrushComponent'))
        if comp:
            h = brush_hulls(mr, comp)
            if h:
                m['hull'] = h
        cyl = ref_index(pr.get('CylinderComponent'))
        if cyl:
            cpr, _ = mr.props_inherited(cyl)
            if cpr and 'CollisionRadius' in cpr:
                m['cyl'] = [round(cpr['CollisionRadius'] / UU, 3),
                            round(float(cpr.get('CollisionHeight', 16.0)) / UU, 3)]
        markers.append(m)
    return path, spawns, markers


def collect(dec_path, tag):
    mr = MapReader(dec_path)
    pkg = mr.pkg
    bounds = {}
    for i, e in enumerate(pkg.exports):
        if pkg.class_of(e) != 'StaticMesh':
            continue
        b = mr.bounds(i + 1)
        # Requiring sphere/diagonal > 0.95 once rejected valid bounds; the
        # real sanity check lives in sane_bounds().
        if b and sane_bounds(b):
            bounds[i + 1] = b

    out = []
    for i, e in enumerate(pkg.exports):
        if pkg.class_of(e) != 'StaticMeshActor':
            continue
        pr, _ = mr.props_inherited(i + 1)
        if not pr or 'Location' not in pr:
            continue
        loc = pr['Location']
        rot = pr.get('Rotation') or (0, 0, 0)
        s3 = pr.get('DrawScale3D') or (1.0, 1.0, 1.0)
        s = pr.get('DrawScale')
        s = s if isinstance(s, float) else 1.0
        ci = ref_index(pr.get('StaticMeshComponent'))
        mesh, ext, org = None, None, (0.0, 0.0, 0.0)
        if ci:
            cpr, _ = mr.props_inherited(ci)
            if cpr:
                mi = ref_index(cpr.get('StaticMesh'))
                ii = imp_index(cpr.get('StaticMesh'))
                if mi:
                    mesh = pkg.exports[mi - 1]['name']
                    if mi in bounds:
                        b = bounds[mi]
                        org, ext = (b[0], b[1], b[2]), (b[3], b[4], b[5])
                elif ii is not None:
                    mesh = pkg.imports[ii]['name']
                    load_lib(imp_root_pkg(pkg, ii))
                    if mesh in _lib_bounds:
                        org, ext = _lib_bounds[mesh]
        if ext is None:
            continue                                  # no size -> useless for a blockout

        # UE3 (X fwd, Y right, Z up, cm)  ->  Godot (X, Y up, -Z fwd, m)
        # USE_ORG=0 places the box at the actor pivot instead of at the mesh's
        # local bounds centre. The centre is more correct in principle, but only
        # if the local offset is rotated and scaled first, which it is not here.
        # Everything below is emitted in the actor's LOCAL frame, with rotation
        # and scale folded into a basis. The importer then places one node per
        # actor and hangs local-space children off it, so neither the hull
        # vertices nor the fallback box need any transform maths of their own --
        # which is what the earlier rotate-the-bounds-origin-by-hand step got
        # wrong, and it is now gone entirely.
        sx, sy, sz = s * s3[0], s * s3[1], s * s3[2]
        px, py, pz = to_godot(loc[0], loc[1], loc[2])
        basis = godot_basis(rot, (sx, sy, sz))
        size = to_godot(ext[0] * 2, ext[1] * 2, ext[2] * 2)
        off = to_godot(org[0], org[1], org[2]) if USE_ORG else (0.0, 0.0, 0.0)
        out.append({
            'src': tag,
            'mesh': mesh or '?',
            'pos': [round(px, 3), round(py, 3), round(pz, 3)],
            'basis': basis,
            # Fallback axis-aligned box, in LOCAL space and UNSCALED -- the
            # basis already carries the scale. Used only for meshes with no
            # convex hull data.
            'size': [round(abs(v), 3) for v in size],
            'off': [round(v, 3) for v in off],
        })
    return out


all_items, all_path, all_spawns, all_markers = [], [], [], []
all_hulls = {}
for f in FILES:
    src = os.path.join(MAPS, f)
    dec = os.path.join(SP, f + '.dec')
    if not os.path.exists(dec):
        subprocess.run([sys.executable, os.path.join(SP, 'ue3_decompress.py'), src, dec],
                       check=True, capture_output=True)
    items = collect(dec, f)
    pts, spawns, markers = collect_annotations(dec)
    n_new = 0
    for mesh, hs in HullReader(dec).by_mesh().items():
        if mesh in all_hulls:
            continue
        conv = []
        for h in hs:
            conv.append({
                'v': [[round(c, 3) for c in to_godot(*v)] for v in h['verts']],
                't': h['tris'],
            })
        all_hulls[mesh] = conv
        n_new += 1
    print("%-24s -> %5d 摆放, %4d 路径点, %3d 出生点, %4d 标记, %3d 新凸包网格"
          % (f, len(items), len(pts), len(spawns), len(markers), n_new))
    all_items.extend(items)
    all_path.extend(pts)
    all_spawns.extend(spawns)
    all_markers.extend(markers)

# Hulls harvested from shared packages, kept only for meshes some placement
# actually uses -- dumping every lib hull would triple the manifest for
# nothing.
referenced = {b['mesh'] for b in all_items}
n_lib_hulls = 0
for mesh, hs in _lib_hulls.items():
    if mesh in all_hulls or mesh not in referenced:
        continue
    all_hulls[mesh] = [{'v': [[round(c, 3) for c in to_godot(*v)] for v in h['verts']],
                        't': h['tris']} for h in hs]
    n_lib_hulls += 1
if n_lib_hulls:
    print("共享包凸包并入 %d 个网格" % n_lib_hulls)

json.dump({'boxes': all_items, 'path': all_path, 'spawns': all_spawns,
           'markers': all_markers, 'hulls': all_hulls},
          open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
with_hull = sum(1 for b in all_items if b['mesh'] in all_hulls)
print("\n合计 %d 摆放 / %d 路径点 / %d 出生点 / %d 标记 -> %s (%.1f KB)"
      % (len(all_items), len(all_path), len(all_spawns), len(all_markers),
         OUT, os.path.getsize(OUT) / 1024))
print("凸包: %d 个网格 / %d 个凸包体；%d 个摆放可用真实形状 (%.0f%%)，其余回退到包围盒"
      % (len(all_hulls), sum(len(v) for v in all_hulls.values()), with_hull,
         100.0 * with_hull / max(len(all_items), 1)))
kinds = {}
for m in all_markers:
    kinds[m['kind']] = kinds.get(m['kind'], 0) + 1
print("标记分类:", kinds)
if all_items:
    xs = [i['pos'][0] for i in all_items]
    ys = [i['pos'][1] for i in all_items]
    zs = [i['pos'][2] for i in all_items]
    print("Godot 空间包围范围 (m): X %.0f..%.0f  Y %.0f..%.0f  Z %.0f..%.0f"
          % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))

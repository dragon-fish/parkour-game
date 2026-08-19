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


PATH_CLASSES = ('checkpoint',)

# Actor classes worth carrying into the blockout as markers. These are what
# tell you WHERE each mechanic was meant to be used -- far more informative
# than the geometry alone.
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
}


def collect_annotations(dec_path):
    """Route points, spawn points (with facing) and gameplay markers."""
    mr = MapReader(dec_path)
    pkg = mr.pkg
    path, spawns, markers = [], [], []
    for i, e in enumerate(pkg.exports):
        cls = pkg.class_of(e)
        low = cls.lower()
        is_path = any(k in low for k in PATH_CLASSES)
        kind = MARKER_CLASSES.get(cls)
        is_spawn = cls == 'TdTutorialStart'
        if not (is_path or kind or is_spawn):
            continue
        pr, _ = mr.props(i + 1)
        if not pr or 'Location' not in pr:
            continue
        l = pr['Location']
        p = [round(v, 2) for v in to_godot(l[0], l[1], l[2])]
        if is_spawn:
            rot = pr.get('Rotation') or (0, 0, 0)
            spawns.append({'pos': p, 'yaw': round(rot[1] * ROT, 1), 'name': e['name']})
        elif is_path:
            path.append(p)
        else:
            markers.append({'kind': kind, 'pos': p, 'name': e['name']})
    return path, spawns, markers


def collect(dec_path, tag):
    mr = MapReader(dec_path)
    pkg = mr.pkg
    bounds = {}
    for i, e in enumerate(pkg.exports):
        if pkg.class_of(e) != 'StaticMesh':
            continue
        b = mr.bounds(i + 1)
        if not b:
            continue
        ex, ey, ez, r = b[3], b[4], b[5], b[6]
        diag = math.sqrt(ex * ex + ey * ey + ez * ez)
        # SphereRadius is the distance from Origin to the farthest VERTEX, so for
        # anything that does not fill its box it is legitimately shorter than the
        # box diagonal. Requiring ratio > 0.95 rejected valid bounds; the real
        # sanity check is only that the sphere is not LARGER than the diagonal.
        if diag > 0 and 0.40 <= r / diag <= 1.05 and min(ex, ey, ez) >= 0 and r < 1e6:
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
                if mi:
                    mesh = pkg.exports[mi - 1]['name']
                    if mi in bounds:
                        b = bounds[mi]
                        org, ext = (b[0], b[1], b[2]), (b[3], b[4], b[5])
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

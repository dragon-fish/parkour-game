"""Shared conversions and object-reference helpers for the level extractor."""
import math
import os
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

UU = 100.0                 # 1 uu = 1 cm
ROT = 360.0 / 65536.0      # rotator unit -> degrees


class ExtractError(Exception):
    """Anything that would otherwise be silently dropped. Offline tool: stop."""


# UE3 is LEFT-handed (X forward, Y right, Z up); Godot is RIGHT-handed.
# Converting between opposite handedness REQUIRES a mapping whose determinant
# is -1. DO NOT use (x, z, -y): its determinant is +1 and it produces a
# mirrored level that is otherwise correct in every measurement.
def to_godot(x, y, z):
    return (x / UU, z / UU, y / UU)


def dir_godot(v):
    """UE3 direction -> unit Godot direction (axis map only, no unit scale)."""
    n = (v[0], v[2], v[1])
    length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
    return [round(c / length, 5) for c in n]


def point(v):
    return [round(c, 4) for c in to_godot(v[0], v[1], v[2])]


def godot_basis(rot, scale):
    """UE3 rotator + scale -> Godot basis as three column vectors.

    Built in UE space and conjugated by the same axis map used for positions
    (M swaps Y and Z and is its own inverse): B = M * R * S * M. Re-deriving
    Euler conventions in the target space is where the mirrored level came from.
    """
    p, y_, r = (a * ROT * math.pi / 180.0 for a in (rot[0], rot[1], rot[2]))
    sp, sy, sr = math.sin(p), math.sin(y_), math.sin(r)
    cp, cy, cr = math.cos(p), math.cos(y_), math.cos(r)
    rows = [
        (cp * cy, cp * sy, sp),
        (sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp),
        (-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp),
    ]
    R = [[rows[j][i] * scale[j] for j in range(3)] for i in range(3)]
    swap = (0, 2, 1)
    B = [[R[swap[i]][swap[j]] for j in range(3)] for i in range(3)]
    return [[round(B[i][j], 6) for i in range(3)] for j in range(3)]


def actor_scale(props):
    s3 = props.get('DrawScale3D') or (1.0, 1.0, 1.0)
    s = props.get('DrawScale')
    s = s if isinstance(s, float) else 1.0
    return (s * s3[0], s * s3[1], s * s3[2])


def finite(v):
    """TdBarbedWireVolume_12 carries NaN; Godot's JSON parser rejects a whole
    file over one non-finite number, so drop those vectors at the source."""
    return all(c == c and abs(c) < 1e30 for c in v)


def ref_export(v):
    """1-based export index of an object property, or None."""
    return v[1] if isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj' and v[1] > 0 else None


def ref_import(v):
    """0-based import index of an object property, or None."""
    return -v[1] - 1 if isinstance(v, tuple) and len(v) == 2 and v[0] == 'obj' and v[1] < 0 else None


def import_root_package(pkg, index):
    """Root package name of import #index (0-based), walking the outer chain."""
    entry = pkg.imports[index]
    while True:
        outer = entry.get('outer', 0)
        if not outer:
            return entry['name']
        if outer < 0:
            entry = pkg.imports[-outer - 1]
        else:
            return pkg.exports[outer - 1]['name']


def outer_class(pkg, export):
    outer = export['outer_idx']
    return pkg.class_of(pkg.exports[outer - 1]) if outer > 0 else None


def pivot_offset(actor):
    """R * PrePivot in Godot metres: how far an actor's drawn mesh sits from its
    Location. Turned with the actor, NOT scaled: UE3 draws at
    Location + R*(S*v - PrePivot)."""
    if not actor.get('PrePivot'):
        return [0.0, 0.0, 0.0]
    rotation = godot_basis(actor.get('Rotation') or (0, 0, 0), (1.0, 1.0, 1.0))
    local = point(actor['PrePivot'])
    return [sum(rotation[c][k] * local[c] for c in range(3)) for k in range(3)]

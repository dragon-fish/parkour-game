"""Matinee sequences a touch plays: SeqEvent_(Td)Touch -> SeqAct_Interp, and
the SeqAct_Interps that follow on from one of those through "Completed".

Only that shape is read. Kismet is a whole scripting language -- gates,
switches, remote events, sub-sequences, "used" buttons -- and replaying it is
out of scope; a matinee reached any other way is counted in the report and
skipped. See docs/superpowers/specs/2026-09-19-me-chapter-sections-design.md.

Keys are RELATIVE to each driven actor's starting transform: position offsets
in world axes, rotations applied in world axes about the actor's own origin.
[ME:INFERRED] UE3's InterpTrackMove default (MoveFrame IMF_World, relative
keys); only yaw-dominant tracks were checked by eye.
"""
import struct

from annotations import brush_hulls
from common import UU, godot_basis, point, ref_export
import packages as pk

TOUCH_EVENTS = ('SeqEvent_Touch', 'SeqEvent_TdTouch')


def _value(mr, tag):
    name, typ, extra, q, sz, arr = tag
    v = mr._value(typ, extra, q, sz)
    if isinstance(v, tuple) and v[0] == 'raw':
        if typ == 'StrProperty':
            n = struct.unpack_from('<i', mr.d, q)[0]
            if n >= 0:
                return mr.d[q + 4:q + 4 + max(n - 1, 0)].decode('latin-1')
            return mr.d[q + 4:q + 4 - 2 * n - 2].decode('utf-16-le')
        if typ == 'ArrayProperty':
            return ('array', q, sz)
        if typ == 'StructProperty':
            return ('struct', extra, q, sz)
    return v


def _props(mr, idx):
    tags, _ = mr.chain_of(idx)
    return {t[0]: _value(mr, t) for t in tags}


def _struct_array(mr, ref):
    if not (isinstance(ref, tuple) and ref[0] == 'array'):
        return []
    q, sz = ref[1], ref[2]
    count = struct.unpack_from('<i', mr.d, q)[0]
    p, end, out = q + 4, q + sz, []
    for _ in range(max(count, 0)):
        ok, tags, p = mr._chain(p, end)
        out.append({t[0]: _value(mr, t) for t in tags})
    return out


def _int_array(mr, ref):
    if not (isinstance(ref, tuple) and ref[0] == 'array'):
        return []
    q, sz = ref[1], ref[2]
    count = struct.unpack_from('<i', mr.d, q)[0]
    return list(struct.unpack_from('<%di' % count, mr.d, q + 4)) if 0 <= count and 4 + 4 * count <= sz else []


def _move_track_props(mr, idx):
    """chain_of() keeps the LONGEST chain near the export start, which on a
    move track is one key's (InVal, OutVal, tangents, mode) rather than the
    track's own (PosTrack, EulerTrack). Take the chain that has PosTrack."""
    e = mr.pkg.exports[idx - 1]
    base, end = e['offset'], e['offset'] + e['size']
    for off in range(0, min(96, e['size']), 4):
        ok, tags, _ = mr._chain(base + off, end)
        if ok and any(t[0] == 'PosTrack' for t in tags):
            return {t[0]: _value(mr, t) for t in tags}
    return {}


def _curve_points(mr, curve):
    """InterpCurvePoint list: dicts with InVal, OutVal, ArriveTangent,
    LeaveTangent, InterpMode."""
    if not (isinstance(curve, tuple) and curve[0] == 'struct'):
        return []
    ok, tags, _ = mr._chain(curve[2], curve[2] + curve[3])
    for t in tags:
        if t[0] == 'Points':
            return _struct_array(mr, _value(mr, t))
    return []


# How a key leaves for the next one. Curve modes all evaluate as Hermite with
# the stored tangents; they differ only in how the editor computed those.
MODES = {'CIM_Constant': 'constant', 'CIM_Linear': 'linear'}


def _vec(v):
    return v if isinstance(v, tuple) and len(v) == 3 else (0.0, 0.0, 0.0)


def _channel(points, convert):
    return [{'time': round(float(p.get('InVal', 0.0)), 4),
             'value': convert(_vec(p.get('OutVal'))),
             'arrive': convert(_vec(p.get('ArriveTangent'))),
             'leave': convert(_vec(p.get('LeaveTangent'))),
             'mode': MODES.get(p.get('InterpMode'), 'curve')} for p in points]


def _keys(mr, track):
    """Position keys in Godot metres (UE axes swapped like every position);
    rotation keys as the ORIGINAL's (roll, pitch, yaw) degrees, because a
    Hermite curve through Euler angles has to be sampled before it becomes a
    basis -- the level builder's Matinee does that with the same conversion
    as common.godot_basis()."""
    pr = _move_track_props(mr, track)
    return {'position': _channel(_curve_points(mr, pr.get('PosTrack')),
                                 lambda v: [v[0] / UU, v[2] / UU, v[1] / UU]),
            'euler': _channel(_curve_points(mr, pr.get('EulerTrack')), list)}


def _trigger(packages, mr, idx):
    """Where a touch event's originator is, and its shape."""
    actor, _ = pk.resolved_props(packages, mr, idx)
    out = {'name': mr.pkg.exports[idx - 1]['name'], 'class': mr.pkg.class_of(mr.pkg.exports[idx - 1])}
    if 'Location' in actor:
        out['position'] = point(actor['Location'])
    component = ref_export(actor.get('BrushComponent'))
    if component:
        out['hull'] = brush_hulls(mr, component)
        out['basis'] = godot_basis(actor.get('Rotation') or (0, 0, 0), _scale(actor))
    cylinder = ref_export(actor.get('CylinderComponent'))
    if cylinder:
        c, _ = pk.resolved_props(packages, mr, cylinder)
        out['radius'] = float(c.get('CollisionRadius', 0.0)) / UU
        out['height'] = float(c.get('CollisionHeight', 0.0)) / UU
    return out


def _scale(actor):
    s = actor.get('DrawScale', 1.0)
    s3 = actor.get('DrawScale3D') or (1.0, 1.0, 1.0)
    return (s * s3[0], s * s3[1], s * s3[2])


def collect(packages, mr, report):
    pkg = mr.pkg
    fired_by = {}
    for i, e in enumerate(pkg.exports, 1):
        if not pkg.class_of(e).startswith('Seq'):
            continue
        for out in _struct_array(mr, _props(mr, i).get('OutputLinks')):
            for link in _struct_array(mr, out.get('Links')):
                op = ref_export(link.get('LinkedOp'))
                if op:
                    fired_by.setdefault(op, []).append((i, out.get('LinkDesc'), link.get('InputLinkIdx', 0)))

    def name_of(i):
        # By export index: prefab copies share object names within a package.
        return '%s#%d' % (mr.label, i)

    matinees = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'SeqAct_Interp':
            continue
        triggers, after = [], None
        for source, desc, input_idx in fired_by.get(i, []):
            cls = pkg.class_of(pkg.exports[source - 1])
            if cls in TOUCH_EVENTS and input_idx == 0:
                originator = ref_export(_props(mr, source).get('Originator'))
                if originator:
                    triggers.append(_trigger(packages, mr, originator))
            elif cls == 'SeqAct_Interp' and desc == 'Completed' and input_idx == 0:
                after = name_of(source)
        if not triggers and after is None:
            report['matinee_skipped'] = report.get('matinee_skipped', 0) + 1
            continue
        groups, length = [], None
        variables = {}
        for link in _struct_array(mr, _props(mr, i).get('VariableLinks')):
            for var in _int_array(mr, link.get('LinkedVariables')):
                if var <= 0:
                    continue
                cls = pkg.class_of(pkg.exports[var - 1])
                if cls == 'InterpData':
                    data = _props(mr, var)
                    length = data.get('InterpLength')
                    for g in _int_array(mr, data.get('InterpGroups')):
                        gp = _props(mr, g)
                        for t in _int_array(mr, gp.get('InterpTracks')):
                            if pkg.class_of(pkg.exports[t - 1]) == 'InterpTrackMove':
                                # An unnamed group is UE3's default name, which is what
                                # the variable links then call it.
                                groups.append({'group': gp.get('GroupName') or 'InterpGroup', 'keys': _keys(mr, t)})
                elif cls.startswith('SeqVar_Object'):
                    obj = ref_export(_props(mr, var).get('ObjValue'))
                    if obj:
                        variables.setdefault(link.get('LinkDesc') or 'None', []).append(
                            '%s.%s' % (mr.label, pkg.exports[obj - 1]['name']))
        for g in groups:
            g['actors'] = variables.get(g['group'], [])
        groups = [g for g in groups if g['actors']
                  and max(len(g['keys']['position']), len(g['keys']['euler'])) >= 2]
        if not groups:
            report['matinee_without_movement'] = report.get('matinee_without_movement', 0) + 1
            continue
        matinees.append({'name': name_of(i), 'package': mr.label, 'length': length,
                         'triggers': triggers, 'after': after, 'groups': groups})
    return matinees

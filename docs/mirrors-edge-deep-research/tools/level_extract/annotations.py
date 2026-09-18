"""Gameplay annotations: interaction volumes, air walls, hazards, spawns and checkpoints."""
import struct

from common import (ExtractError, UU, ROT, actor_scale, dir_godot, finite, godot_basis,
                    outer_class, point, ref_export)

# Volume class -> manifest kind. InterestLine kinds, wire, walls and lethal
# volumes; the three checkpoint classes are handled apart below.
VOLUME_KINDS = {
    'TdZiplineVolume': 'zipline',
    'TdSwingVolume': 'swing',
    'TdBalanceWalkVolume': 'balance',
    'TdLedgeWalkVolume': 'ledgewalk',
    'TdLadderVolume': 'ladder',
    'TdBarbedWireVolume': 'barbedwire',
    'BlockingVolume': 'blocking',
    'TdKillVolume': 'kill',
    'TdCheckpointVolume': 'checkpointvolume',
}

# Found and counted, never mapped: meaning not verified against the original.
REPORTED_ONLY = ('TdFallHeightVolume',)


def _raw_entry(mr, idx, name):
    chain, _ = mr.chain_of(idx)
    for (n, typ, extra, q, sz, _arr) in chain:
        if n == name:
            return typ, extra, q, sz
    return None


def vector_array(mr, idx, name):
    entry = _raw_entry(mr, idx, name)
    if not entry:
        return None
    _, _, q, sz = entry
    count = struct.unpack_from('<i', mr.d, q)[0]
    if count <= 0 or sz - 4 < count * 12:
        return None
    return [struct.unpack_from('<3f', mr.d, q + 4 + i * 12) for i in range(count)]


def brush_hulls(mr, component_idx):
    """KConvexElem hulls of a BrushComponent's BrushAggGeom (the same
    FKAggregateGeom hulls.py reads). Local, unscaled: the basis carries both."""
    entry = _raw_entry(mr, component_idx, 'BrushAggGeom')
    if not entry:
        return []
    _, _, q, sz = entry
    _ok, tags, _ = mr._chain(q, q + sz)
    for (n, _t, _x, q2, sz2, _a) in tags:
        if n != 'ConvexElems':
            continue
        count = struct.unpack_from('<i', mr.d, q2)[0]
        p, limit = q2 + 4, q2 + sz2
        hulls = []
        for _ in range(max(count, 0)):
            _ok2, elem, _nat = mr._chain(p, limit)
            if not elem:
                break
            vertices, triangles = None, []
            for (en, _et, _ex, eq, esz, _ea) in elem:
                c = struct.unpack_from('<i', mr.d, eq)[0]
                if en == 'VertexData' and c > 0 and esz - 4 >= c * 12:
                    vertices = [struct.unpack_from('<3f', mr.d, eq + 4 + i * 12) for i in range(c)]
                elif en == 'FaceTriData' and c > 0 and esz - 4 >= c * 4:
                    triangles = list(struct.unpack_from('<%di' % c, mr.d, eq + 4))
            last = elem[-1]
            p = last[3] + last[4]
            while p + 8 <= limit:
                if mr.nm(struct.unpack_from('<i', mr.d, p)[0]) == 'None':
                    p += 8
                    break
                p += 4
            if vertices:
                hulls.append({'vertices': [point(v) for v in vertices], 'triangles': triangles})
        return hulls
    return []


def blocking_defaults(packages):
    """bExludeHandMoves / bExludeFootMoves as BlockingVolume's class defaults."""
    engine = packages.cooked_reader('Engine.u')
    default = next((i for i, e in enumerate(engine.pkg.exports, 1)
                    if e['name'] == 'Default__BlockingVolume'), None)
    if default is None:
        raise ExtractError('Engine.u has no Default__BlockingVolume')
    props = engine.props(default)[0]
    return {'exclude_hand': props['bExludeHandMoves'], 'exclude_foot': props['bExludeFootMoves']}


## How far the cooked Start/End may sit outside the ladder's own steps. On a
## sound ladder the first step is ~0.34 m above Start and the last ~0.96 m
## below End (tutorial, Stormdrain StdP and StdE alike).
LADDER_STEP_SLACK_UU = 200.0


def _ladder_from_steps(mr, idx, props, annotation, report):
    """Rebuild a ladder's line from PawnLadderLocations when the cooked
    Start/End/SplineLocations are broken.

    Measured, not hypothetical: in Stormdrain StdE several rotated ladder
    volumes were cooked with Start/End thousands of kilometres apart
    (SplineLength 3.8e9 uu) or NaN, while their per-step locations are sound.
    A line that long became 20,000 runtime nodes per ladder and 8 GB of video
    memory. [ME:INFERRED] the original climbs by the steps, not by the spline.
    """
    steps = vector_array(mr, idx, 'PawnLadderLocations')
    if not steps or not all(finite(v) for v in steps):
        return
    # Every axis, not only height: some are off sideways instead, one end
    # right and the other metres out across open air.
    low = [min(v[k] for v in steps) - LADDER_STEP_SLACK_UU for k in range(3)]
    high = [max(v[k] for v in steps) + LADDER_STEP_SLACK_UU for k in range(3)]
    cooked = [props.get('Start'), props.get('End')] + list(vector_array(mr, idx, 'SplineLocations') or [])
    sound = all(isinstance(v, tuple) and len(v) == 3 and finite(v)
                and all(low[k] <= v[k] <= high[k] for k in range(3)) for v in cooked)
    if sound:
        return
    annotation['start'] = point(steps[0])
    annotation['end'] = point(steps[-1])
    annotation['spline'] = [point(v) for v in steps]
    report.setdefault('ladders_from_steps', []).append('%s.%s' % (mr.label, annotation['name']))


def collect(mr, defaults, report):
    """Annotations, spawns, anchors and checkpoints of one package."""
    pkg = mr.pkg
    out = {'annotations': [], 'spawns': [], 'anchors': [], 'checkpoints': []}
    for i, e in enumerate(pkg.exports, 1):
        cls = pkg.class_of(e)
        if cls in REPORTED_ONLY:
            report['unmapped'][cls] = report['unmapped'].get(cls, 0) + 1
            continue
        if cls not in VOLUME_KINDS and cls not in ('TdTutorialStart', 'TdTutorialCheckpoint',
                                                    'TdCheckpoint', 'PlayerStart'):
            continue
        if outer_class(pkg, e) != 'Level':
            continue                      # prefab templates, not placed actors
        props, _ = mr.props_inherited(i)
        if not props or 'Location' not in props:
            continue
        position = point(props['Location'])
        rotation = props.get('Rotation') or (0, 0, 0)
        if cls == 'TdTutorialCheckpoint':
            out['anchors'].append(position)
            continue
        if cls in ('TdTutorialStart', 'TdCheckpoint', 'PlayerStart'):
            entry = {'name': e['name'], 'class': cls, 'package': mr.label,
                     'position': position, 'yaw_deg': round(-90.0 - rotation[1] * ROT, 3)}
            (out['spawns'] if cls == 'TdTutorialStart' else out['checkpoints']).append(entry)
            continue
        annotation = {'kind': VOLUME_KINDS[cls], 'name': e['name'], 'package': mr.label,
                      'position': position, 'basis': godot_basis(rotation, actor_scale(props))}
        for source, key in (('Start', 'start'), ('End', 'end'), ('Middle', 'middle')):
            v = props.get(source)
            if isinstance(v, tuple) and len(v) == 3 and finite(v):
                annotation[key] = point(v)
        for source, key in (('WallNormal', 'wall'), ('MoveDirection', 'direction'),
                            ('FloorNormal', 'floor')):
            v = props.get(source)
            if isinstance(v, tuple) and len(v) == 3 and finite(v):
                annotation[key] = dir_godot(v)
        spline = vector_array(mr, i, 'SplineLocations')
        if spline and len(spline) > 2 and all(finite(v) for v in spline):
            annotation['spline'] = [point(v) for v in spline]
        if cls == 'TdLadderVolume':
            _ladder_from_steps(mr, i, props, annotation, report)
        component = ref_export(props.get('BrushComponent'))
        annotation['hull'] = brush_hulls(mr, component) if component else []
        if cls == 'BlockingVolume':
            if e['archetype'] and not ('bExludeHandMoves' in props and 'bExludeFootMoves' in props):
                raise ExtractError('%s.%s: archetype outside the package; class defaults may not apply'
                                   % (mr.label, e['name']))
            annotation['exclude_hand'] = props.get('bExludeHandMoves', defaults['exclude_hand'])
            annotation['exclude_foot'] = props.get('bExludeFootMoves', defaults['exclude_foot'])
        out['annotations'].append(annotation)
    return out

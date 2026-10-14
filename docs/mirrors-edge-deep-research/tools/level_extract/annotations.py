"""Gameplay annotations: interaction volumes, air walls, hazards, spawns and checkpoints."""
import math
import struct

import packages as pk

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
    # Only the pain-causing ones: Escape's electric fences are PhysicsVolumes
    # with bPainCausing, DamagePerSec and TdDmgType_ElectricShock. The rest
    # (Plaza's ZoneVelocity water) are counted in the report.
    'PhysicsVolume': 'pain',
    'TdFallHeightVolume': 'fallheight',
}

# Actors collected ONLY when they ride something -- when Base names another
# actor in the same package. The game places hundreds of loose Triggers and
# flares that mean nothing here; attached to a mover they are the whole of how
# a passing train kills, warns and lights the way, because the train's own mesh
# has no collision at all.
#
# `effect` rather than a name per class: what one of these DOES is decided by
# the Kismet its touch reaches (matinee.rider_effects), not by its class. The
# Mall runs a lethal box and a horn box off the same DynamicTriggerVolume.
RIDER_ONLY_KINDS = {
    'DynamicTriggerVolume': 'effect',
    'Trigger': 'effect',
    'LensFlareSource': 'flare',
}

# How far up a Base chain a rider may sit. The Mall's kill box rides the
# train's head directly; a box on a middle CAR would be one hop further.
BASE_CHAIN_MAX = 4


def _ridden_base(mr, idx, report):
    """(`package.name` of the actor this one ultimately rides, bHardAttach), or
    (None, False).

    Follows Base to the end of the chain -- the actor that has none of its own,
    which is the one a matinee drives. A base in ANOTHER package is counted and
    dropped: an export index means nothing outside the package that wrote it.

    bHardAttach is reported, not required. LensFlareSource leaves it unset and
    still rides: it decides whether the attachment keeps a relative rotation,
    not whether there is one.
    """
    pkg = mr.pkg
    props, _ = mr.props_inherited(idx)
    if not props or props.get('Base') is None:
        return None, False
    hard = bool(props.get('bHardAttach'))
    seen, cur = {idx}, idx
    for _ in range(BASE_CHAIN_MAX):
        step, _ = mr.props_inherited(cur)
        raw = (step or {}).get('Base')
        if raw is None:
            return '%s.%s' % (mr.label, pkg.exports[cur - 1]['name']), hard
        nxt = ref_export(raw)
        if nxt is None:
            counts = report.setdefault('counts', {})
            counts['base_outside_package'] = counts.get('base_outside_package', 0) + 1
            return None, False
        if nxt in seen:
            raise ExtractError('%s.%s: Base chain loops' % (mr.label, pkg.exports[idx - 1]['name']))
        seen.add(nxt)
        cur = nxt
    raise ExtractError('%s.%s: Base chain deeper than %d'
                       % (mr.label, pkg.exports[idx - 1]['name'], BASE_CHAIN_MAX))


def _volume_reach(annotation):
    """How far off its own line the original's volume still reaches, metres, or
    None when the volume has no hull or no line to measure against.

    The volumes are boxes and ours are capsules, so this is the box's own
    half-extent across the line -- the widest a body can be off the line and
    still stand inside what the level author drew. Measured, not guessed: the
    Mall's ziplines reach 2.2 to 4.1 m where this project had been using 0.6.
    """
    hull = annotation.get('hull') or []
    start, end = annotation.get('start'), annotation.get('end')
    if not hull or start is None or end is None:
        return None
    axis = [end[k] - start[k] for k in range(3)]
    length = math.sqrt(sum(c * c for c in axis))
    if length < 0.01:
        return None
    axis = [c / length for c in axis]
    basis = annotation['basis']
    points = []
    for shape in hull:
        for v in shape['vertices']:
            # basis is three column vectors; the hull is local and unscaled.
            points.append([sum(basis[row][k] * v[row] for row in range(3)) for k in range(3)])
    if not points:
        return None
    centre = [sum(p[k] for p in points) / len(points) for k in range(3)]
    furthest = 0.0
    for p in points:
        rel = [p[k] - centre[k] for k in range(3)]
        along = sum(rel[k] * axis[k] for k in range(3))
        perp = [rel[k] - along * axis[k] for k in range(3)]
        furthest = max(furthest, math.sqrt(sum(c * c for c in perp)))
    return round(furthest, 3)


def _raw_entry(mr, idx, name, widest=False):
    chain, _ = mr.chain_of(idx, widest)
    for (n, typ, extra, q, sz, _arr) in chain:
        if n == name:
            return typ, extra, q, sz
    return None


def string_property(mr, idx, name):
    """A StrProperty's text, or '' when absent. Negative length is UTF-16."""
    entry = _raw_entry(mr, idx, name)
    if not entry:
        return ''
    q = entry[2]
    n = struct.unpack_from('<i', mr.d, q)[0]
    if n > 0:
        return mr.d[q + 4:q + 4 + n - 1].decode('latin-1')
    return mr.d[q + 4:q + 4 - 2 * n - 2].decode('utf-16-le')


def vector_array(mr, idx, name):
    entry = _raw_entry(mr, idx, name)
    if not entry:
        return None
    _, _, q, sz = entry
    count = struct.unpack_from('<i', mr.d, q)[0]
    if count <= 0 or sz - 4 < count * 12:
        return None
    return [struct.unpack_from('<3f', mr.d, q + 4 + i * 12) for i in range(count)]


def streamed_by(mr, idx):
    """[ME:CONFIRMED] a TdCheckpoint lists the packages a restore there loads,
    as references to the persistent level's LevelStreaming objects: the world
    as it stands at that checkpoint. Spelt as streaming.package_key() spells
    a package (a PackageName carries no extension)."""
    entry = _raw_entry(mr, idx, 'StreamingLevels')
    if not entry:
        return []
    _, _, q, sz = entry
    count = struct.unpack_from('<i', mr.d, q)[0]
    if count <= 0 or sz - 4 < count * 4:
        return []
    out = []
    for ref in struct.unpack_from('<%di' % count, mr.d, q + 4):
        name = (mr.props(ref)[0] or {}).get('PackageName') if ref > 0 else None
        if name:
            out.append(str(name).lower())
    return out


# UE's world is 524288 uu across, so 5242.88 m in Godot space. A brush that was
# never built keeps the unbounded plane the editor starts it from, and cooking
# writes that plane out as a four-point "hull" reaching the world's edge. Eight
# across the corpus are like this; sp02's PhysicsVolume_5 came out
# 5243 x 5243 x 0 m and painted the whole Storm Drain as a pain volume.
WORLD_EDGE = 5000.0


def built(hull):
    """False for the unbounded plane an unbuilt brush cooks down to."""
    v = hull['vertices']
    return max(max(p[k] for p in v) - min(p[k] for p in v) for k in range(3)) < WORLD_EDGE


def brush_hulls(mr, component_idx):
    """KConvexElem hulls of a BrushComponent's BrushAggGeom (the same
    FKAggregateGeom hulls.py reads). Local, unscaled: the basis carries both.

    The WIDEST chain: a component with nothing stored before its BrushAggGeom
    has its first ConvexElem's chain (seven tags) start where the calibration
    looks, and that chain outnumbers the component's own three. Read by tag
    count, the brush came back without its BrushAggGeom, i.e. without a brush."""
    entry = _raw_entry(mr, component_idx, 'BrushAggGeom', widest=True)
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


def inherited_hulls(packages, mr, component_idx, depth=0):
    """brush_hulls() of a BrushComponent, or of the first archetype up its
    chain that has any, across packages. A volume placed from a prefab (Factory's
    server racks) carries a delta component; the brush is on the prefab's."""
    hulls = brush_hulls(mr, component_idx)
    if hulls or depth > 8:
        return hulls
    archetype = mr.pkg.exports[component_idx - 1]['archetype']
    if archetype > 0:
        return inherited_hulls(packages, mr, archetype, depth + 1)
    if archetype < 0:
        root, path = pk.import_path(mr.pkg, -archetype - 1)
        shared = packages.shared_reader(root)
        target = pk.find_export(shared, path) if shared else None
        if target is None:
            raise ExtractError('%s: brush archetype %s not found' % (mr.label, '.'.join([root] + path)))
        return inherited_hulls(packages, shared, target, depth + 1)
    return []


def blocking_defaults(packages):
    """Class defaults the volumes fall back to: BlockingVolume's
    bExludeHandMoves / bExludeFootMoves and PhysicsVolume's DamageType."""
    engine = packages.cooked_reader('Engine.u')

    def default_of(name):
        idx = next((i for i, e in enumerate(engine.pkg.exports, 1) if e['name'] == name), None)
        if idx is None:
            raise ExtractError('Engine.u has no %s' % name)
        return engine.props(idx)[0]

    blocking = default_of('Default__BlockingVolume')
    physics = default_of('Default__PhysicsVolume')
    return {'exclude_hand': blocking['bExludeHandMoves'], 'exclude_foot': blocking['bExludeFootMoves'],
            'pain_damage_type': engine.pkg.resolve(physics['DamageType'][1])}


def _object_name(value):
    """The bare name of an object reference read through resolved_props(),
    local or carried from the package that wrote it."""
    if isinstance(value, tuple) and len(value) == 3 and value[0] == 'ext':
        return value[1].pkg.resolve(value[2])
    return None


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
    # Some cooked splines collapse to one point even though their steps span
    # a real ladder; being inside the step bounds is not enough.
    if sound and props['Start'] != props['End']:
        return
    annotation['start'] = point(steps[0])
    annotation['end'] = point(steps[-1])
    annotation['spline'] = [point(v) for v in steps]
    report.setdefault('ladders_from_steps', []).append('%s.%s' % (mr.label, annotation['name']))


## How far outside its own brush a fall-height volume's cooked Center may sit,
## metres: rounding, nothing more. Every volume of the corpus is inside.
CENTER_SLACK_M = 0.05


def fall_height(props, annotation, label):
    """What TdFallHeightVolume.Touch reads, on its annotation.

    [ME:CONFIRMED decompile TdFallHeightVolume.Touch] a TdPawn touching the
    volume has EnterFallingHeight set to Center.Z + FallHeightOffset and its
    current move's TouchedFallHeightVolume() called. Center is TdMovementVolume's
    and is cooked into the map. FallHeightOffset has no class default, so an
    unset one is 0. The placement itself (PrePivot included) is place_brush's.
    """
    center = props.get('Center')
    if not (isinstance(center, tuple) and len(center) == 3 and finite(center)):
        raise ExtractError('%s: fall-height volume has no Center' % label)
    annotation['fall_height_offset'] = float(props.get('FallHeightOffset', 0.0)) / UU
    # Off until Kismet's SeqAct_ChangeCollision turns it on (Escape's R1 and
    # Stormdrain's StdP ones): kismet.py marks the actor, and a level that does
    # not run its Kismet must not build it live.
    if props.get('bCollideActors') is False:
        annotation['starts_off'] = True


def place_brush(props, annotation, label):
    """Move a brush-placed volume from its Location to where its brush IS.

    UE3 places a brush at Location + R*S*(v - PrePivot): a volume with a
    PrePivot sits R*S*PrePivot away from Location (Stormdrain's chute volume by
    255 m, Boat's railings by up to 449 m), so `position` becomes the brush's
    origin. A brush's PrePivot IS scaled by DrawScale3D, unlike a static mesh's
    (common.pivot_offset): the Stormdrain roof's zipline volume, scale 13.4 on
    X, only agrees with its cooked Center when it is. DO NOT place a brush at
    Location; 88 of 97 BlockingVolumes
    overlap their railing geometry only with the pivot applied.

    A volume that carries a cooked Center (TdMovementVolume's: the brush's own
    centre in world space, PrePivot included) is checked against the placed
    brush. A Center outside it means the placement, not the Center, is wrong:
    stop.
    """
    basis = annotation['basis']
    local = point(props['PrePivot']) if props.get('PrePivot') else [0.0, 0.0, 0.0]
    pivot = [sum(basis[c][k] * local[c] for c in range(3)) for k in range(3)]
    annotation['position'] = [round(annotation['position'][k] - pivot[k], 4) for k in range(3)]
    center = props.get('Center')
    if not (isinstance(center, tuple) and len(center) == 3 and finite(center)):
        return
    annotation['center'] = point(center)
    basis = annotation['basis']
    world = [[annotation['position'][k] + sum(basis[c][k] * v[c] for c in range(3)) for k in range(3)]
             for hull in annotation['hull'] for v in hull['vertices']]
    if not world:
        raise ExtractError('%s: volume with a Center has no brush' % label)
    for k in range(3):
        lo, hi = min(p[k] for p in world), max(p[k] for p in world)
        if not lo - CENTER_SLACK_M <= annotation['center'][k] <= hi + CENTER_SLACK_M:
            raise ExtractError('%s: Center %s lies outside the placed brush on axis %d (%.2f..%.2f)'
                               % (label, annotation['center'], k, lo, hi))


def collect(packages, mr, defaults, report):
    """Annotations, spawns, anchors and checkpoints of one package."""
    pkg = mr.pkg
    out = {'annotations': [], 'spawns': [], 'anchors': [], 'checkpoints': []}
    for i, e in enumerate(pkg.exports, 1):
        cls = pkg.class_of(e)
        if cls not in VOLUME_KINDS and cls not in RIDER_ONLY_KINDS \
                and cls not in ('TdTutorialStart', 'TdTutorialCheckpoint',
                                'TdCheckpoint', 'PlayerStart'):
            continue
        if outer_class(pkg, e) != 'Level':
            continue                      # prefab templates, not placed actors
        props, _ = mr.props_inherited(i)
        if not props or 'Location' not in props:
            continue
        if cls == 'BlockingVolume' and props.get('bCollideActors') is False:
            # Off until Kismet turns it on (SeqAct_ChangeCollision), which is
            # not replayed: the boss lift's doorway and a Std slice floor
            # were solid walls and a floating shelf here.
            counts = report.setdefault('counts', {})
            counts['blocking_off'] = counts.get('blocking_off', 0) + 1
            continue
        if cls == 'PhysicsVolume' and not props.get('bPainCausing'):
            counts = report.setdefault('counts', {})
            counts['physics_volume_harmless'] = counts.get('physics_volume_harmless', 0) + 1
            continue
        position = point(props['Location'])
        rotation = props.get('Rotation') or (0, 0, 0)
        if cls == 'TdTutorialCheckpoint':
            out['anchors'].append(position)
            continue
        if cls in ('TdTutorialStart', 'TdCheckpoint', 'PlayerStart'):
            entry = {'name': e['name'], 'class': cls, 'package': mr.label,
                     'position': position, 'yaw_deg': round(-90.0 - rotation[1] * ROT, 3)}
            if cls == 'TdCheckpoint':
                # The level designer's own name, the chapter order (weight
                # grows along the level) and the level-start flag.
                entry['label'] = string_property(mr, i, 'CheckpointName')
                entry['weight'] = props.get('CheckpointWeight', 0)
                entry['default'] = bool(props.get('DefaultCheckpoint', False))
                entry['streaming'] = streamed_by(mr, i)
            (out['spawns'] if cls == 'TdTutorialStart' else out['checkpoints']).append(entry)
            continue
        base, hard = _ridden_base(mr, i, report)
        if cls in RIDER_ONLY_KINDS and base is None:
            continue                      # a loose trigger or flare: not ours
        annotation = {'kind': VOLUME_KINDS.get(cls) or RIDER_ONLY_KINDS[cls],
                      'name': e['name'], 'package': mr.label,
                      'position': position, 'basis': godot_basis(rotation, actor_scale(props))}
        if base is not None:
            annotation['base'] = base
            annotation['hard'] = hard
        cylinder = ref_export(props.get('CylinderComponent'))
        if cylinder:
            # A Trigger is a cylinder, not a brush: the Mall's camera shake
            # reaches 28.52 m around the train's head.
            c, _ = pk.resolved_props(packages, mr, cylinder)
            annotation['radius'] = float(c.get('CollisionRadius', 0.0)) / UU
            annotation['height'] = float(c.get('CollisionHeight', 0.0)) / UU
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
        hulls = inherited_hulls(packages, mr, component) if component else []
        annotation['hull'] = [h for h in hulls if built(h)]
        if hulls and not annotation['hull'] and 'radius' not in annotation:
            counts = report.setdefault('counts', {})
            counts['brush_unbuilt'] = counts.get('brush_unbuilt', 0) + 1
            report.setdefault('brushes_unbuilt', []).append('%s.%s' % (mr.label, e['name']))
            continue
        if component:
            chain_props = pk.resolved_props(packages, mr, i)[0]
            label = '%s.%s' % (mr.label, e['name'])
            if 'PrePivot' in chain_props and 'PrePivot' not in props:
                raise ExtractError('%s: PrePivot only on the archetype chain' % label)
            place_brush(props, annotation, label)
            if props.get('PrePivot'):
                counts = report.setdefault('counts', {})
                counts['pivoted_' + cls] = counts.get('pivoted_' + cls, 0) + 1
            if base is not None and props.get('PrePivot'):
                report.setdefault('pivoted_riders', []).append(label)
        reach = _volume_reach(annotation)
        if reach is not None:
            annotation['reach_radius'] = reach
        if cls == 'BlockingVolume':
            # The WHOLE archetype chain, across packages: a volume placed from a
            # prefab (Factory's server racks) takes its flags from a template
            # in the prefab's package, and only past its end do the class
            # defaults apply.
            chain, _ = pk.resolved_props(packages, mr, i)
            annotation['exclude_hand'] = chain.get('bExludeHandMoves', defaults['exclude_hand'])
            annotation['exclude_foot'] = chain.get('bExludeFootMoves', defaults['exclude_foot'])
            # What the volume's surface IS: Escape's slanted-building chute is
            # a BlockingVolume with PM_Glass_BulletproofSlide lying on a mesh
            # that has no slide flag of its own. extract.py reads its flags.
            override = (mr.props(component)[0] or {}).get('PhysMaterialOverride') if component else None
            if override:
                annotation['physical_material'] = pkg.resolve(override[1] if isinstance(override, tuple) else override)
        if cls == 'PhysicsVolume':
            chain, _ = pk.resolved_props(packages, mr, i)
            damage_type = chain.get('DamageType')
            if damage_type is None:
                # Left at the class default: Subway's.
                name = defaults['pain_damage_type']
            elif damage_type == ('obj', 0):
                # Set to None on purpose: pain with no damage type (Boat's).
                name = 'None'
            elif isinstance(damage_type, tuple) and damage_type[0] == 'obj':
                name = pkg.resolve(damage_type[1])
            else:
                name = _object_name(damage_type)
            if not name:
                raise ExtractError('%s.%s: pain volume DamageType %r unreadable' % (mr.label, e['name'], damage_type))
            annotation['damage_per_sec'] = float(chain.get('DamagePerSec', 0.0))
            annotation['damage_type'] = name
        if cls == 'TdFallHeightVolume':
            fall_height(props, annotation, '%s.%s' % (mr.label, e['name']))
        out['annotations'].append(annotation)
    return out

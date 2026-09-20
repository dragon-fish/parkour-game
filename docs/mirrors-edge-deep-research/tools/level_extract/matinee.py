"""Matinee sequences a touch, a use or a kick plays, directly or through "Completed"
of another one, traced back through Switch, Gate and Delay.

Only that shape is read. Kismet is a whole scripting language -- remote
events, sub-sequences, counters, conditions -- and replaying it is out of
scope; a matinee reached any other way is counted in the report and skipped. See docs/superpowers/specs/2026-09-19-me-chapter-sections-design.md.

Keys are RELATIVE to each driven actor's starting transform: position offsets
in world axes, rotations applied in world axes about the actor's own origin.
[ME:INFERRED] UE3's InterpTrackMove default (MoveFrame IMF_World, relative
keys); only yaw-dominant tracks were checked by eye.
"""
import struct

from annotations import brush_hulls
from common import UU, godot_basis, outer_class, pivot_offset, point, ref_export
import packages as pk

TOUCH_EVENTS = ('SeqEvent_Touch', 'SeqEvent_TdTouch')
# A kick: [ME:CONFIRMED Stormdrain Kismet] doors open on TakeDamage of a
# hidden InterpActor in front of them. This project has no kick; the level
# plays these when the player runs into that spot, a KICK_REACH_M cylinder
# around the damaged actor's origin.
DAMAGE_EVENTS = ('SeqEvent_TakeDamage',)
KICK_REACH_M = 1.0
KICK_HALF_HEIGHT_M = 1.5
# "Used": the player pressed the use key at the originator. This project has
# no use key; the level plays these when the player stands in the trigger.
USED_EVENTS = ('SeqEvent_Used', 'SeqEvent_TdUsed')
# Nodes a start is traced back through. Switch hands each activation to its
# next output, which is how a used lever alternates up and down.
PASS_THROUGH = ('SeqAct_Switch', 'SeqAct_Gate', 'SeqAct_Delay')
# InterpData.InterpLength's class default: omitted from the export when unchanged.
DEFAULT_LENGTH = 5.0
# SeqAct_Delay.Duration's class default, for a Delay that omits it.
DEFAULT_DELAY = 1.0


def _delay_seconds(mr, idx):
    """(seconds, low, high) of a SeqAct_Delay. low/high are None unless the
    Duration comes from a linked SeqVar_RandomFloat.

    A constant gap makes a metronome of a level. [ME:CONFIRMED Mall Kismet]
    the trains re-run through a Delay whose Duration is a RandomFloat of
    5 to 10 s, and reading only the literal gave every train a 1 s gap.
    """
    props = _props(mr, idx)
    seconds = float(props.get('Duration', DEFAULT_DELAY))
    for link in _struct_array(mr, props.get('VariableLinks')):
        if link.get('LinkDesc') != 'Duration':
            continue
        for var in _int_array(mr, link.get('LinkedVariables')):
            if var <= 0 or mr.pkg.class_of(mr.pkg.exports[var - 1]) != 'SeqVar_RandomFloat':
                continue
            v = _props(mr, var)
            low, high = float(v.get('Min', seconds)), float(v.get('Max', seconds))
            return (low + high) / 2.0, low, high
    return seconds, None, None


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
            'euler': _channel(_curve_points(mr, pr.get('EulerTrack')), list),
            # IMF_RelativeToInitial: keys in the actor's OWN frame. The lift's
            # two door leaves face opposite ways and share one "-76 along X",
            # which opens them to opposite sides only read this way.
            # UE3's class default is IMF_World.
            'local': pr.get('MoveFrame') == 'IMF_RelativeToInitial'}


def _trigger(packages, mr, idx):
    """Where a touch event's originator is, and its shape."""
    actor, _ = pk.resolved_props(packages, mr, idx)
    out = {'name': mr.pkg.exports[idx - 1]['name'], 'class': mr.pkg.class_of(mr.pkg.exports[idx - 1])}
    if 'Location' in actor:
        out['position'] = point(actor['Location'])
        # Where the actor is drawn and collides (see extract.pivot_offset): a
        # kicked door's hidden target sits 2.56 m below its Location.
        turned = pivot_offset(actor)
        out['position'] = [round(out['position'][k] - turned[k], 4) for k in range(3)]
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


def collect(packages, mr, report, keep_driving=frozenset()):
    """Matinees of one package.

    `keep_driving` holds actor ids (`package.name`) whose sequence is wanted
    even though nothing this module can read ever starts it. A respawn twin is
    the case: the only thing that plays it is a remote event sent by the
    checkpoint being loaded, and remote events are out of scope here. Such a
    matinee comes out with an empty `starts`, for whoever named it to play.
    """
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

    def starts_of(op, depth=0, seen=None):
        """How `op` gets fired, walked up through the nodes that only pass a
        signal on: Switch outputs, a Gate's In, a Delay (whose duration adds
        up). Returns {on, trigger|source, delay, input} dicts, input being
        the SeqAct_Interp input the path arrives at (0 play, 1 reverse)."""
        # Per PATH, not shared: a lever's up and down both come through the
        # same Gate, and a shared set drops whichever is walked second.
        seen = seen if seen is not None else frozenset()
        out = []
        for source, desc, input_idx in fired_by.get(op, []):
            cls = pkg.class_of(pkg.exports[source - 1])
            # Only a pass-through node can close a loop; a matinee restarting
            # itself through a Delay is a loop the level means (the subway).
            if depth > 8 or (cls in PASS_THROUGH and source in seen):
                continue
            if cls in TOUCH_EVENTS or cls in USED_EVENTS or cls in DAMAGE_EVENTS:
                originator = ref_export(_props(mr, source).get('Originator'))
                # A prefab's own sequence names the prefab's TEMPLATE actors,
                # which stand at the prefab's origin, not in the level.
                if originator and outer_class(pkg, pkg.exports[originator - 1]) == 'Level':
                    trigger = _trigger(packages, mr, originator)
                    if cls in DAMAGE_EVENTS:
                        trigger.pop('hull', None)
                        trigger.update(radius=KICK_REACH_M, height=KICK_HALF_HEIGHT_M)
                    out.append({'on': 'use' if cls in USED_EVENTS else 'touch',
                                'trigger': trigger, 'delay': 0.0, 'input': input_idx})
            elif cls == 'SeqAct_Interp' and desc == 'Completed':
                out.append({'on': 'after', 'source': name_of(source), 'delay': 0.0, 'input': input_idx})
            elif cls in PASS_THROUGH:
                delay, low, high = _delay_seconds(mr, source) if cls == 'SeqAct_Delay' \
                    else (0.0, None, None)
                if low is None:
                    low = high = delay
                for up in starts_of(source, depth + 1, seen | {op}):
                    if cls == 'SeqAct_Gate' and up.get('via_input', 0) != 0:
                        continue
                    out.append(dict(up, delay=up['delay'] + delay,
                                    delay_min=up.get('delay_min', up['delay']) + low,
                                    delay_max=up.get('delay_max', up['delay']) + high,
                                    input=input_idx))
            else:
                continue
        # The input a path enters the NEXT node by, for a Gate's filter above.
        return [dict(o, via_input=o['input']) for o in out]

    matinees = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'SeqAct_Interp':
            continue
        starts = [{k: v for k, v in s.items() if k != 'via_input'} for s in starts_of(i)
                  if s['input'] in (0, 1)]
        # A startless sequence is dropped -- UNLESS the config asked for the
        # actor it drives. Which actor that is only becomes known once the
        # groups below are read, so the decision waits until then.
        if not starts and not keep_driving:
            report['matinee_skipped'] = report.get('matinee_skipped', 0) + 1
            continue
        groups, length = [], None
        variables, frames = {}, {}
        for link in _struct_array(mr, _props(mr, i).get('VariableLinks')):
            for var in _int_array(mr, link.get('LinkedVariables')):
                if var <= 0:
                    continue
                cls = pkg.class_of(pkg.exports[var - 1])
                if cls == 'InterpData':
                    data = _props(mr, var)
                    # Absent means UE3's default: the lift and the StdE crane.
                    length = data.get('InterpLength', DEFAULT_LENGTH)
                    for g in _int_array(mr, data.get('InterpGroups')):
                        gp = _props(mr, g)
                        # An unnamed group is UE3's default name, which is what
                        # the variable links then call it.
                        keys = {'position': [], 'euler': [], 'scale': [], 'local': False}
                        for t in _int_array(mr, gp.get('InterpTracks')):
                            track_class = pkg.class_of(pkg.exports[t - 1])
                            if track_class == 'InterpTrackMove':
                                keys.update(_keys(mr, t))
                            elif track_class == 'InterpTrackVectorProp':
                                tp = _props(mr, t)
                                # DrawScale3D, absolute, in the actor's own UE axes:
                                # the Std crane's cable is stretched to follow its
                                # falling board this way.
                                if tp.get('PropertyName') == 'DrawScale3D':
                                    keys['scale'] = _channel(_curve_points(mr, tp.get('VectorTrack')),
                                                             lambda v: [v[0], v[2], v[1]])
                        groups.append({'group': gp.get('GroupName') or 'InterpGroup', 'keys': keys})
                elif cls.startswith('SeqVar_Object'):
                    obj = ref_export(_props(mr, var).get('ObjValue'))
                    if obj:
                        actor_id = '%s.%s' % (mr.label, pkg.exports[obj - 1]['name'])
                        variables.setdefault(link.get('LinkDesc') or 'None', []).append(actor_id)
                        # Where every driven actor starts, meshless or not: the
                        # builder pivots anything hard-attached to it about this.
                        actor, _ = pk.resolved_props(packages, mr, obj)
                        if 'Location' in actor:
                            frames[actor_id] = {'position': point(actor['Location']),
                                                'basis': godot_basis(actor.get('Rotation') or (0, 0, 0), (1.0, 1.0, 1.0))}
        for g in groups:
            g['actors'] = variables.get(g['group'], [])
        groups = [g for g in groups if g['actors']
                  and max(len(g['keys'][c]) for c in ('position', 'euler', 'scale')) >= 2]
        if not groups:
            report['matinee_without_movement'] = report.get('matinee_without_movement', 0) + 1
            continue
        if not starts:
            if not any(a in keep_driving for g in groups for a in g['actors']):
                report['matinee_skipped'] = report.get('matinee_skipped', 0) + 1
                continue
            report['matinee_kept_startless'] = report.get('matinee_kept_startless', 0) + 1
        # A sequence whose ONLY way in is its own loop has to be started by the
        # level itself, or it never runs: the Mall's trains are exactly this,
        # and without it the tracks stay empty.
        #
        # The test is deliberately narrow -- only a pure self-loop. A sequence
        # opened by a remote event from another package looks startless here
        # too, but this module does not follow remote events, and starting
        # everything it cannot trace would run the level's whole cast at once.
        autostart = bool(starts) and all(
            s['on'] == 'after' and s.get('source') == name_of(i) for s in starts)
        entry = {'name': name_of(i), 'package': mr.label, 'length': length,
                 # PlayRate is on the ACTION, not the data: the Std crane's
                 # swing is keyed over 2 s and played at 0.2, ten seconds in
                 # the original.
                 'play_rate': float(_props(mr, i).get('PlayRate', 1.0)),
                 'starts': starts, 'groups': groups, 'frames': frames}
        if autostart:
            entry['autostart'] = True
        # Where a play begins. [ME:CONFIRMED Stormdrain Kismet] the sequence a
        # respawn plays is forced part-way in -- the girder twin to 3.1 s of
        # its 5 -- and without it the thing the point stands on is still at the
        # bottom of its rise. The designer's comment on that action is "load".
        if _props(mr, i).get('bForceStartPos'):
            entry['start_position'] = float(_props(mr, i).get('ForceStartPosition', 0.0))
        rolling = _running_sound(mr, i)
        if rolling:
            entry['sound'] = rolling
        matinees.append(entry)
    return matinees


def _running_sound(mr, idx):
    """The sound a matinee holds WHILE it plays, from its own `soundon` output.

    [ME:CONFIRMED Mall Kismet] the train's rolling noise is not a touch: the
    sequence's soundon starts it and its soundoff stops it, so it lasts exactly
    as long as the movement does.
    """
    pkg = mr.pkg
    for out in _struct_array(mr, _props(mr, idx).get('OutputLinks')):
        if out.get('LinkDesc') != 'soundon':
            continue
        for link in _struct_array(mr, out.get('Links')):
            op = ref_export(link.get('LinkedOp'))
            if not op or pkg.class_of(pkg.exports[op - 1]) != SOUND_ACTION:
                continue
            props = _props(mr, op)
            cue = props.get('PlaySound')
            if not (isinstance(cue, tuple) and cue[0] == 'obj' and cue[1]):
                continue
            name = pkg.resolve(cue[1]) if cue[1] < 0 else pkg.exports[cue[1] - 1]['name']
            return {'name': name, 'fade_in': float(props.get('FadeInTime', 0.0)),
                    'fade_out': float(props.get('FadeOutTime', 0.0))}
    return None


# What a volume riding a mover does when it is touched. FOUR outcomes are read
# and nothing else; anything further is counted in the report, exactly as a
# matinee reached by a shape this module does not read is.
#
# [ME:CONFIRMED Mall Kismet] the Mall's train is FOUR of these on one actor and
# no collision of its own: a box around all four cars that fails the player, a
# box 48 m ahead that sounds the horn, a cylinder around the head that shakes
# the camera, and two flares for the headlights.
FAIL_ACTIONS = ('SeqAct_TdPlayerFail', 'SeqAct_CauseDamage')
SOUND_ACTION = 'SeqAct_TdPlaySound'
SHAKE_ACTION = 'SeqAct_TdCameraShake'
# Nodes a touch is followed THROUGH. RandomSwitch hands its activation to ONE
# output at random, so what lies past it is an alternative rather than a
# sequence -- the horn box reaches both Horn_Short and Horn_Long and sounds
# one. That is why every sound found is collected into one list and the choice
# is left to the game: modelling the switch itself would buy nothing.
FOLLOW_THROUGH = ('SeqAct_Switch', 'SeqAct_Gate', 'SeqAct_Delay', 'SeqAct_RandomSwitch')
RIDER_WALK_DEPTH = 6


def rider_effects(mr, riders, report):
    """{rider name: {kill, sounds, shake}} for the actor names in `riders`.

    A rider with no readable outcome is absent from the result. The Mall hangs
    some forty 0.4 m Triggers along each train that no sequence listens to;
    built as empty volumes they would be pure cost.
    """
    pkg = mr.pkg
    downstream = {}
    for i, e in enumerate(pkg.exports, 1):
        if not pkg.class_of(e).startswith(('Seq', 'TdSeq')):
            continue
        for out in _struct_array(mr, _props(mr, i).get('OutputLinks')):
            for link in _struct_array(mr, out.get('Links')):
                op = ref_export(link.get('LinkedOp'))
                if op:
                    downstream.setdefault(i, []).append((op, link.get('InputLinkIdx', 0)))

    def sound_of(idx):
        props = _props(mr, idx)
        cue = props.get('PlaySound')
        name = pkg.resolve(cue[1]) if isinstance(cue, tuple) and cue[0] == 'obj' and cue[1] < 0 \
            else (pkg.exports[cue[1] - 1]['name'] if isinstance(cue, tuple) and cue[0] == 'obj' and cue[1] > 0 else None)
        if not name:
            return None
        return {'name': name, 'fade_in': float(props.get('FadeInTime', 0.0)),
                'fade_out': float(props.get('FadeOutTime', 0.0))}

    out = {}
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) not in TOUCH_EVENTS:
            continue
        originator = ref_export(_props(mr, i).get('Originator'))
        if not originator:
            continue
        rider = pkg.exports[originator - 1]['name']
        if rider not in riders:
            continue
        # Walk the touch forward, remembering every Delay met so the one that
        # STOPS a shake can be told from the rest.
        found = out.setdefault(rider, {'kill': False, 'sounds': [], 'shake': None})
        reached, delays, todo, seen = [], [], [(i, 0)], set()
        while todo:
            op, depth = todo.pop()
            if op in seen or depth > RIDER_WALK_DEPTH:
                continue
            seen.add(op)
            cls = pkg.class_of(pkg.exports[op - 1])
            if cls == 'SeqAct_Delay':
                delays.append(op)
            if cls in FAIL_ACTIONS or cls == SOUND_ACTION or cls == SHAKE_ACTION:
                reached.append(op)
            elif not cls.startswith(('SeqEvent', 'SeqEvt')) and cls not in FOLLOW_THROUGH:
                report['rider_effect_unread'] = report.get('rider_effect_unread', 0) + 1
                continue
            for nxt, _input in downstream.get(op, []):
                todo.append((nxt, depth + 1))
        for op in reached:
            cls = pkg.class_of(pkg.exports[op - 1])
            if cls in FAIL_ACTIONS:
                found['kill'] = True
            elif cls == SOUND_ACTION:
                cue = sound_of(op)
                if cue and cue not in found['sounds']:
                    found['sounds'].append(cue)
            elif cls == SHAKE_ACTION:
                props = _props(mr, op)
                # The shake runs until its second input is fired, which is what
                # the Delay beside it is for. No such Delay: it has no end we
                # can read, and the game decides when to stop it.
                hold = 0.0
                for d in delays:
                    if any(target == op and idx == 1 for target, idx in downstream.get(d, [])):
                        hold = max(hold, _delay_seconds(mr, d)[0])
                found['shake'] = {'amplitude': float(props.get('Amplitude', 0.0)),
                                  'frequency': float(props.get('Frequency', 0.0)),
                                  'hold': hold}
    empty = [name for name, f in out.items() if not f['kill'] and not f['sounds'] and f['shake'] is None]
    for name in empty:
        del out[name]
    report['rider_effects'] = report.get('rider_effects', 0) + len(out)
    return out


# Breakable glass: [ME:CONFIRMED Cranes Kismet] a pane is an InterpActor whose
# SeqEvent_TakeDamage takes TdDmgType_Barge -- the body crashing into it. The
# event spawns the shatter and deals bullet damage to a hidden "Broken" twin,
# whose own event hides and destroys both. Only the pair is read; the chain
# itself is the builder's BreakableGlass.
#
# THE TWIN IS WHAT MAKES IT GLASS. Barge damage alone also marks the doors the
# original barges open (Subway's and Factory's maintenance doors) and
# Subway's destroyable fences; taken for glass, a door vanished in a shower
# of shards.
BARGE_DAMAGE = 'TdDmgType_Barge'


def collect_glass(packages, mr, report):
    pkg = mr.pkg
    out = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'SeqEvent_TakeDamage':
            continue
        props = _props(mr, i)
        types = [pkg.resolve(t) for t in _int_array(mr, props.get('DamageTypes'))]
        if BARGE_DAMAGE not in types:
            continue
        pane = ref_export(props.get('Originator'))
        if not pane or pkg.class_of(pkg.exports[pane - 1]) != 'InterpActor' \
                or outer_class(pkg, pkg.exports[pane - 1]) != 'Level':
            continue
        broken = None
        for out_link in _struct_array(mr, props.get('OutputLinks')):
            for link in _struct_array(mr, out_link.get('Links')):
                op = ref_export(link.get('LinkedOp'))
                if not op or pkg.class_of(pkg.exports[op - 1]) != 'SeqAct_CauseDamage':
                    continue
                for var_link in _struct_array(mr, _props(mr, op).get('VariableLinks')):
                    if var_link.get('LinkDesc') != 'Target':
                        continue
                    for var in _int_array(mr, var_link.get('LinkedVariables')):
                        target = ref_export(_props(mr, var).get('ObjValue')) if var > 0 else None
                        if target and target != pane:
                            broken = '%s.%s' % (mr.label, pkg.exports[target - 1]['name'])
        if broken is None:
            continue
        actor, _ = pk.resolved_props(packages, mr, pane)
        out.append({'kind': 'glass', 'name': pkg.exports[pane - 1]['name'], 'package': mr.label,
                    'position': point(actor['Location']),
                    'pane': '%s.%s' % (mr.label, pkg.exports[pane - 1]['name']), 'broken': broken})
    report['glass'] = report.get('glass', 0) + len(out)
    return out


def self_disabling(mr):
    """Names of the volumes a touch switches off: [ME:CONFIRMED Factory
    Kismet] a pain volume standing in for a falling lift hurts once, because
    its own Touch turns its collision off (SeqAct_ChangeCollision, NoCollision)."""
    pkg = mr.pkg
    out = set()
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) not in TOUCH_EVENTS:
            continue
        props = _props(mr, i)
        volume = ref_export(props.get('Originator'))
        if not volume:
            continue
        for out_link in _struct_array(mr, props.get('OutputLinks')):
            for link in _struct_array(mr, out_link.get('Links')):
                op = ref_export(link.get('LinkedOp'))
                if not op or pkg.class_of(pkg.exports[op - 1]) != 'SeqAct_ChangeCollision':
                    continue
                action = _props(mr, op)
                if action.get('CollisionType') != 'COLLIDE_NoCollision':
                    continue
                for var_link in _struct_array(mr, action.get('VariableLinks')):
                    for var in _int_array(mr, var_link.get('LinkedVariables')):
                        if var > 0 and ref_export(_props(mr, var).get('ObjValue')) == volume:
                            out.add(pkg.exports[volume - 1]['name'])
    return out


# The chapter's end: [ME:CONFIRMED Escape, Cranes Kismet] SeqAct_TdLevelCompleted,
# reached from a touch through whatever the level plays on the way (input off,
# an outro matinee, a delay, a fade) and often through remote events sent from
# another package. Only the touches are wanted; the path is replaced by a
# white fade to the menu.
LEVEL_END_WALK_DEPTH = 16


def level_end_links(packages, mr):
    """This package's part of the chain: the touches and remote event names
    upstream of each SeqAct_TdLevelCompleted ('end'), and of each
    SeqAct_ActivateRemoteEvent by the event it sends ('sends')."""
    pkg = mr.pkg
    fired_by = {}
    for i, e in enumerate(pkg.exports, 1):
        if not pkg.class_of(e).startswith(('Seq', 'TdSeq')):
            continue
        for out in _struct_array(mr, _props(mr, i).get('OutputLinks')):
            for link in _struct_array(mr, out.get('Links')):
                op = ref_export(link.get('LinkedOp'))
                if op:
                    fired_by.setdefault(op, []).append((i, link.get('InputLinkIdx', 0)))

    def upstream(start):
        triggers, names, seen, todo = [], set(), set(), [(start, 0)]
        while todo:
            op, depth = todo.pop()
            if op in seen or depth > LEVEL_END_WALK_DEPTH:
                continue
            seen.add(op)
            cls = pkg.class_of(pkg.exports[op - 1])
            props = _props(mr, op)
            if cls in TOUCH_EVENTS or cls in USED_EVENTS:
                originator = ref_export(props.get('Originator'))
                if originator and outer_class(pkg, pkg.exports[originator - 1]) == 'Level':
                    triggers.append(_trigger(packages, mr, originator))
                continue
            if cls == 'SeqEvent_RemoteEvent':
                if props.get('EventName'):
                    names.add(str(props['EventName']))
                continue
            if cls.startswith(('SeqEvent', 'SeqEvt')):
                continue
            for up, input_idx in fired_by.get(op, []):
                # Only what goes THROUGH a gate, not what opens it: Edge's roof
                # end flies the helicopter in and opens the gate; grabbing the
                # helicopter ends the level.
                if cls == 'SeqAct_Gate' and input_idx != 0:
                    continue
                todo.append((up, depth + 1))
        return triggers, names

    out = {'end': [], 'sends': {}}
    for i, e in enumerate(pkg.exports, 1):
        cls = pkg.class_of(e)
        if cls == 'SeqAct_TdLevelCompleted':
            out['end'].append(upstream(i))
        elif cls == 'SeqAct_ActivateRemoteEvent' and _props(mr, i).get('EventName'):
            out['sends'].setdefault(str(_props(mr, i)['EventName']), []).append(upstream(i))
    return out


def level_ends(links):
    """The touches that end the chapter, as [(package label, trigger)], from
    every package's level_end_links(); remote events followed across them."""
    found, names = [], set()
    for label, part in links:
        for triggers, sent in part['end']:
            found += [(label, t) for t in triggers]
            names |= sent
    done = set()
    while names - done:
        name = (names - done).pop()
        done.add(name)
        for label, part in links:
            for triggers, sent in part['sends'].get(name, []):
                found += [(label, t) for t in triggers]
                names |= sent
    unique = {}
    for label, t in found:
        unique.setdefault((label, t['name']), (label, t))
    return list(unique.values())

"""When the original loads and unloads its packages, flattened out of Kismet.

[ME:CONFIRMED] a chapter's packages come and go through
SeqAct_MultiLevelStreaming (and a few SeqAct_LevelStreaming) in the persistent
level: a touch unloads one list, its Finished loads the next, so two stretches
that stand in each other's space are never loaded together. The
LevelStreamingVolumes are all bDisabled and nothing activates a
SeqAct_StreamingZone anywhere in the game; neither is read.

Each action is walked UP to the events that fire it and written as one step
per path: who fires it, after how long, in which order, load or unload, which
packages. Gates and Switches are walked through, not simulated -- a load or an
unload is idempotent on the set of present packages, so one firing too many
is usually harmless -- and every path that crossed one says so in `through`,
which is where to look first when a stretch is wrong.

Two layers, so the walk can be tested with no game data: read_graph() turns a
package into plain dicts, flatten() works on those alone.
See docs/superpowers/specs/2026-09-21-me-level-streaming-design.md.
"""
import os

from common import outer_class, ref_export
from matinee import (DAMAGE_EVENTS, DEFAULT_LENGTH, KICK_HALF_HEIGHT_M, KICK_REACH_M,
                     LEVEL_END_WALK_DEPTH, TOUCH_EVENTS, USED_EVENTS, _delay_seconds,
                     _int_array, _props, _struct_array, _trigger)

STREAMING_ACTIONS = ('SeqAct_MultiLevelStreaming', 'SeqAct_LevelStreaming')
# Walked through without a word: they carry the signal and decide nothing.
# DisableLoadFromLastCheckpoint is the save system's switch and sits on a
# hundred of these paths.
TRANSPARENT = ('SeqAct_ActivateRemoteEvent', 'SeqAct_DisableLoadFromLastCheckpoint',
               'SeqAct_FinishSequence', 'Sequence')
# A restore takes the checkpoint's own snapshot; the path needs no step.
CUTSCENE = 'SeqAct_TdIntoCutscene'
RESTORE_EVENTS = ('SeqEvt_TdCheckpointLoaded',)
# Packages with no geometry. Their Kismet is still read: Convoy's
# Remove_sluice_interior, which unloads a corridor, is sent by a music package.
NO_GEOMETRY = ('_aud', '_mus')
KIND_OF = dict([(c, 'touch') for c in TOUCH_EVENTS] + [(c, 'used') for c in USED_EVENTS]
               + [(c, 'damage') for c in DAMAGE_EVENTS])


def package_key(name):
    """A package as every table here spells it: lower case, no extension. The
    original's own spelling varies (Convoy_Roof-Conv_slc_lgts). The builder's
    MeLevelCommon.package_key() is the same rule."""
    name = str(name)
    return (name[:-4] if name.lower().endswith('.me1') else name).lower()


def has_geometry(key):
    return not key.endswith(NO_GEOMETRY)


def read_graph(packages, mr):
    """One package's Kismet as {export index: node}. A node is a dict with
    `cls`, `ups` [(source index, output name, input index)] and, by class:
    `event` (remote events, both ends), `delay`, `length`, `levels` plus
    `inputs` (streaming actions), `trigger` (events an actor of the level
    originates). A sub-sequence is a node like any other, wired through its
    ports: `port` on a SeqEvent_SequenceActivated is (sequence, input index)
    of the input that activates it, `finishes` on a Sequence maps an output's
    name to the SeqAct_FinishSequence behind it."""
    pkg = mr.pkg
    nodes = {}
    for i, e in enumerate(pkg.exports, 1):
        cls = pkg.class_of(e)
        if not cls.startswith(('Seq', 'TdSeq')) or cls.startswith(('SeqVar', 'TdSeqVar')):
            continue
        nodes[i] = {'cls': cls, 'ups': []}
    for i, node in nodes.items():
        props = _props(mr, i)
        cls = node['cls']
        for out in _struct_array(mr, props.get('OutputLinks')):
            for link in _struct_array(mr, out.get('Links')):
                op = ref_export(link.get('LinkedOp'))
                if op in nodes:
                    nodes[op]['ups'].append((i, str(out.get('LinkDesc')), int(link.get('InputLinkIdx', 0))))
        if cls == 'Sequence':
            for input_idx, link in enumerate(_struct_array(mr, props.get('InputLinks'))):
                event = ref_export(link.get('LinkedOp'))
                if event in nodes:
                    nodes[event]['port'] = (i, input_idx)
            node['finishes'] = {str(link.get('LinkDesc')): ref_export(link.get('LinkedOp'))
                                for link in _struct_array(mr, props.get('OutputLinks'))}
        elif cls in ('SeqEvent_RemoteEvent', 'SeqAct_ActivateRemoteEvent'):
            node['event'] = str(props.get('EventName') or '').lower()
        elif cls == 'SeqAct_Delay':
            node['delay'] = _delay_seconds(mr, i)[0]
        elif cls == 'SeqAct_Interp':
            node['length'] = _interp_seconds(mr, i, props)
        elif cls in STREAMING_ACTIONS:
            node['inputs'] = [str(x.get('LinkDesc')).lower() for x in _struct_array(mr, props.get('InputLinks'))]
            levels = [x.get('LevelName') for x in _struct_array(mr, props.get('Levels'))] or [props.get('LevelName')]
            node['levels'] = [package_key(n) for n in levels if n and str(n) != 'None']
        elif cls in KIND_OF:
            originator = ref_export(props.get('Originator'))
            # A prefab's own sequence names the prefab's TEMPLATE actors,
            # which stand at the prefab's origin, not in the level.
            if originator and outer_class(pkg, pkg.exports[originator - 1]) == 'Level':
                trigger = _trigger(packages, mr, originator)
                if cls in DAMAGE_EVENTS:
                    trigger.pop('hull', None)
                    trigger.update(radius=KICK_REACH_M, height=KICK_HALF_HEIGHT_M)
                node['trigger'] = trigger
    return nodes


def _interp_seconds(mr, idx, props):
    length = DEFAULT_LENGTH
    for link in _struct_array(mr, props.get('VariableLinks')):
        for var in _int_array(mr, link.get('LinkedVariables')):
            if var > 0 and mr.pkg.class_of(mr.pkg.exports[var - 1]) == 'InterpData':
                length = float(_props(mr, var).get('InterpLength', DEFAULT_LENGTH))
    rate = float(props.get('PlayRate', 1.0)) or 1.0
    return length / rate


def flatten(graphs):
    """(steps, report) from {package name: read_graph()}."""
    senders = {}
    for name, nodes in graphs.items():
        for i, node in nodes.items():
            if node['cls'] == 'SeqAct_ActivateRemoteEvent' and node.get('event'):
                senders.setdefault(node['event'], []).append((name, i))
    report = {'unsent': set(), 'unhandled_roots': {}, 'dead_ends': {}, 'restores': 0}
    found = {}

    def walk(name, idx, out_desc, delay, order, through, seen, emit):
        """Arrived at node `idx` from below, out of its output `out_desc`."""
        node = graphs[name][idx]
        cls = node['cls']
        if (name, idx) in seen or len(seen) > LEVEL_END_WALK_DEPTH:
            return
        seen = seen | {(name, idx)}
        if cls == 'SeqEvent_RemoteEvent':
            sent = senders.get(node.get('event', ''), [])
            if not sent:
                report['unsent'].add(node.get('event', ''))
            for other, sender in sent:
                walk(other, sender, 'Out', delay, order, through, seen, emit)
            return
        if cls == 'SeqEvent_SequenceActivated' and 'port' in node:
            # Out of a sub-sequence by the input that activates it: Stormdrain
            # loads its roof from inside one.
            sequence, port = node['port']
            for up, desc, input_idx in graphs[name][sequence]['ups']:
                if input_idx == port:
                    walk(name, up, desc, delay, order, through, seen, emit)
            return
        if cls == 'Sequence':
            # ...and into one by the output the signal came out of.
            finish = node.get('finishes', {}).get(out_desc)
            if finish in graphs[name]:
                walk(name, finish, 'Out', delay, order, through, seen, emit)
            return
        if cls.startswith(('SeqEvent', 'SeqEvt', 'TdSeqEvent', 'TdSeqEvt')):
            if cls in RESTORE_EVENTS:
                report['restores'] += 1
            elif 'trigger' in node:
                emit(name, node, delay, order, through)
            else:
                report['unhandled_roots'][cls] = report['unhandled_roots'].get(cls, 0) + 1
            return
        if cls in STREAMING_ACTIONS:
            if out_desc == 'Finished':
                order += 1
        elif cls == 'SeqAct_Delay':
            delay += node.get('delay', 0.0)
        elif cls == 'SeqAct_Interp':
            # Only a path that waits for the matinee pays for it: a lift's
            # button unloads what is behind on the doors' Completed, and
            # without the wait the way back went before the doors had shut.
            if out_desc in ('Completed', 'Reversed'):
                delay += node.get('length', 0.0)
        elif cls not in TRANSPARENT:
            through = through | {cls}
        if not node['ups']:
            report['dead_ends'][cls] = report['dead_ends'].get(cls, 0) + 1
        for up, desc, input_idx in node['ups']:
            # Only what goes THROUGH a gate, not what opens or shuts it.
            if cls == 'SeqAct_Gate' and input_idx != 0:
                continue
            # A Delay's Stop and Pause do not start it.
            if cls == 'SeqAct_Delay' and input_idx != 0:
                continue
            walk(name, up, desc, delay, order, through, seen, emit)

    for name, nodes in graphs.items():
        for i, node in nodes.items():
            if node['cls'] not in STREAMING_ACTIONS or not node.get('levels'):
                continue
            for up, desc, input_idx in node['ups']:
                inputs = node.get('inputs') or ['load', 'unload']
                op = inputs[input_idx] if input_idx < len(inputs) else ''
                if op not in ('load', 'unload'):
                    continue

                def emit(root_package, root, delay, order, through, op=op, levels=node['levels']):
                    trigger = root['trigger']
                    # A cutscene is not played here, so nothing waits for one:
                    # Escape's office scene would hold a load back 130 s.
                    if CUTSCENE in through:
                        delay = 0.0
                    key = (root_package, trigger['name'], op, tuple(levels))
                    step = {'source': {'kind': KIND_OF[root['cls']], 'package': root_package, 'trigger': trigger},
                            'delay': round(delay, 3), 'order': order, 'op': op,
                            'packages': list(levels), 'through': sorted(through)}
                    # Two paths from one trigger to one action: the quicker is
                    # the one that gets there first.
                    if key not in found or (step['delay'], step['order']) < (found[key]['delay'], found[key]['order']):
                        found[key] = step

                walk(name, up, desc, 0.0, 0, frozenset(), frozenset({(name, i)}), emit)

    steps = sorted(found.values(), key=lambda s: (s['source']['package'], s['source']['trigger']['name'],
                                                  s['delay'], s['order'], s['op']))
    report['unsent'] = sorted(report['unsent'])
    return steps, report


def collect(packages, checkpoints, report):
    """manifest['streaming'] for a chapter, and report['streaming']."""
    streamed = packages.streamed_packages()
    graphs = {}
    for name in sorted(os.listdir(packages.chapter_dir)):
        if not name.lower().endswith('.me1'):
            continue
        if name != packages.persistent and package_key(name) not in streamed:
            continue
        graphs[name] = read_graph(packages, packages.reader(name))
    steps, walked = flatten(graphs)
    for step in steps:
        step['packages'] = [k for k in step['packages'] if has_geometry(k)]
    steps = [s for s in steps if s['packages']]
    managed = set()
    for c in checkpoints:
        managed.update(c.get('streaming', []))
    for step in steps:
        managed.update(step['packages'])
    kinds, crossed = {}, {}
    for step in steps:
        kinds[step['source']['kind']] = kinds.get(step['source']['kind'], 0) + 1
        for cls in step['through']:
            crossed[cls] = crossed.get(cls, 0) + 1
    report['streaming'] = dict(walked, steps=len(steps), kinds=kinds,
                               steps_through_unsimulated=sum(1 for s in steps if s['through']),
                               through=crossed)
    return {'steps': steps, 'managed': sorted(k for k in managed if has_geometry(k))}

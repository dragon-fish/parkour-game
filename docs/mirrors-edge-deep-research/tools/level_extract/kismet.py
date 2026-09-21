"""A chapter's Kismet as a plain graph, for the level to run as the original did.

Kismet is UE3's visual scripting: events, actions, conditions and variables
wired together, advanced by impulses, with state in the nodes (a Gate is open
or shut, a Switch remembers where it was). Reading single facts OUT of it --
which touch starts this matinee, which button unloads that stretch -- is how
this extractor began, and each time the answer was wrong wherever the graph
held state: a Gate that starts shut was walked through as though open, and a
button unloaded the floor the player stood on. So the graph is exported whole
and interpreted (scripts/level/kismet/), and nothing here decides what a node
MEANS: that is the interpreter's, one class at a time.

What is written, engine-neutral:

  nodes   {id: {cls, package, name, sequence, ins, outs, vars, props, ...}}
          id is "<package key>#<export index>". `outs` is [{name, delay, to}],
          `to` being [[node id, input index], ...]. `vars` maps a variable
          link's name to variable ids. `props` holds the node's own scalar
          properties as the original names them.
  vars    {id: {cls, name?, value? | actor? | actors? | find?}}
  actors  {"<package key>.<actor>": {cls, package, trigger?}} for everything a
          node refers to; `trigger` is the shape of one that originates an
          event, as matinee._trigger() reads it, and `wall` the shape of a
          DynamicBlockingVolume.

See docs/kismet-runtime.md.
"""
import os

import packages as pk

from common import ExtractError, actor_scale, godot_basis, outer_class, point, ref_export
from matinee import (DAMAGE_EVENTS, DEFAULT_LENGTH, KICK_HALF_HEIGHT_M, KICK_REACH_M,
                     _int_array, _struct_array, _trigger, _value)
from streaming import package_key

# The editor's own bookkeeping, and what is exported structurally instead.
SKIPPED_PROPS = frozenset((
    'ObjPosX', 'ObjPosY', 'DrawWidth', 'DrawHeight', 'MaxWidth', 'ObjInstanceVersion', 'ObjName',
    'ParentSequence', 'InputLinks', 'OutputLinks', 'VariableLinks', 'EventLinks', 'SequenceObjects',
    'Originator', 'ObjValue', 'ObjList', 'Levels', 'bSuppressAutoComment', 'bOutputObjCommentToScreen',
    'ObjColor', 'DefaultViewX', 'DefaultViewY', 'DefaultViewZoom'))
SCALARS = (bool, int, float, str)
# Walls that exist to be switched by Kismet: the steam across Stormdrain's
# valve corridor is one, with a pain volume inside it. Nothing else extracts
# them -- a BlockingVolume is an annotation, these are not -- so they are
# built with the graph that is their only reason to exist.
SWITCHED_WALLS = ('DynamicBlockingVolume',)


def _props(mr, idx):
    """matinee._props() with the WIDEST chain (see MapReader.chain_of): read
    the usual way, every SeqEvent_LevelLoaded and LevelReset -- 92 objects in
    Stormdrain, and nothing else -- came back as one of its own output links.
    With them went whatever a level sets up as it loads: the steam behind the
    valve's entrance starts off only because a LevelLoaded turns it off."""
    tags, _ = mr.chain_of(idx, widest=True)
    return {t[0]: _value(mr, t) for t in tags}


def node_id(package, index):
    return '%s#%d' % (package_key(package), index)


def _scalar_props(props):
    out = {}
    for key, value in props.items():
        if key in SKIPPED_PROPS:
            continue
        if isinstance(value, SCALARS):
            out[key] = round(value, 5) if isinstance(value, float) else value
    return out


def _actor_id(mr, index):
    """"<package key>.<name>" of an actor placed in this package's level, or
    None: a prefab's template or an import is nothing the level holds."""
    if not index or index <= 0:
        return None
    export = mr.pkg.exports[index - 1]
    if outer_class(mr.pkg, export) != 'Level':
        return None
    return '%s.%s' % (package_key(mr.label), export['name'])


def _interp(mr, props):
    """A matinee's length and what its event tracks fire, and when."""
    length, events = DEFAULT_LENGTH, []
    for link in _struct_array(mr, props.get('VariableLinks')):
        for var in _int_array(mr, link.get('LinkedVariables')):
            if var <= 0 or mr.pkg.class_of(mr.pkg.exports[var - 1]) != 'InterpData':
                continue
            data = _props(mr, var)
            length = float(data.get('InterpLength', DEFAULT_LENGTH))
            for group in _int_array(mr, data.get('InterpGroups')):
                for track in _int_array(mr, _props(mr, group).get('InterpTracks')):
                    if track <= 0 or mr.pkg.class_of(mr.pkg.exports[track - 1]) != 'InterpTrackEvent':
                        continue
                    tp = _props(mr, track)
                    for key in _struct_array(mr, tp.get('EventTrack')):
                        events.append({'name': str(key.get('EventName')), 'time': round(float(key.get('Time', 0.0)), 4),
                                       # Both default to true and are written only when false.
                                       'forwards': bool(tp.get('bFireEventsWhenForwards', True)),
                                       'backwards': bool(tp.get('bFireEventsWhenBackwards', True))})
    return round(length, 4), events


def read_package(packages, mr, actors, variables, mesh_of=None):
    """This package's nodes; fills `actors` and `variables` as it meets them.
    `mesh_of(mr, reference)` gives the mesh record behind a StaticMesh
    property, and by asking puts the mesh in the library: what a
    SeqAct_SetStaticMesh swaps in is placed nowhere, so nothing else would."""
    pkg = mr.pkg
    nodes = {}
    indices = [i for i, e in enumerate(pkg.exports, 1)
               if pkg.class_of(e).startswith(('Seq', 'TdSeq')) and not pkg.class_of(e).startswith(('SeqVar', 'TdSeqVar'))
               or pkg.class_of(e) == 'Sequence']

    def variable(index):
        vid = node_id(mr.label, index)
        if vid in variables:
            return vid
        cls = pkg.class_of(pkg.exports[index - 1])
        props = _props(mr, index)
        entry = {'cls': cls}
        if props.get('VarName') and str(props['VarName']) != 'None':
            entry['name'] = str(props['VarName'])
        if cls == 'SeqVar_Named':
            entry['find'] = str(props.get('FindVarName'))
        elif cls == 'SeqVar_ObjectList':
            entry['actors'] = [a for a in (_note_actor(ref) for ref in _int_array(mr, props.get('ObjList'))) if a]
        elif 'ObjValue' in props:
            entry['actor'] = _note_actor(ref_export(props.get('ObjValue')))
        else:
            for key in ('bValue', 'IntValue', 'FloatValue', 'StrValue', 'Min', 'Max'):
                if isinstance(props.get(key), SCALARS):
                    entry.setdefault('value', {})[key] = props[key]
        variables[vid] = entry
        return vid

    def _note_actor(index):
        aid = _actor_id(mr, index)
        if aid and aid not in actors:
            cls = pkg.class_of(pkg.exports[index - 1])
            actors[aid] = {'cls': cls, 'package': package_key(mr.label)}
            inherited, _ = mr.props_inherited(index)
            # [ME:CONFIRMED] what Kismet switches usually starts OFF: the crush
            # volume under a steel door (10000 damage a second) collides only
            # while the door comes down, a corridor's end wall only while the
            # next stretch loads. Built as though on, the first killed whoever
            # walked through an open door.
            if inherited and inherited.get('bCollideActors') is False:
                actors[aid]['starts_off'] = True
            # annotations.collect() leaves a BlockingVolume that starts off
            # out altogether -- built solid it was a wall across the boss
            # lift's doorway -- so it is built here, with what switches it.
            if cls in SWITCHED_WALLS or (cls == 'BlockingVolume' and actors[aid].get('starts_off')):
                actors[aid]['wall'] = _trigger(packages, mr, index)
        return aid

    for i in indices:
        export = pkg.exports[i - 1]
        cls = pkg.class_of(export)
        props = _props(mr, i)
        node = {'cls': cls, 'package': package_key(mr.label), 'name': export['name']}
        parent = ref_export(props.get('ParentSequence'))
        if parent:
            node['sequence'] = node_id(mr.label, parent)
        if props.get('ObjComment'):
            node['comment'] = str(props['ObjComment'])
        node['ins'] = [str(x.get('LinkDesc')) for x in _struct_array(mr, props.get('InputLinks'))]
        outs = []
        for out in _struct_array(mr, props.get('OutputLinks')):
            entry = {'name': str(out.get('LinkDesc')),
                     'to': [[node_id(mr.label, op), int(link.get('InputLinkIdx', 0))]
                            for link in _struct_array(mr, out.get('Links'))
                            for op in [ref_export(link.get('LinkedOp'))] if op]}
            if float(out.get('ActivateDelay', 0.0) or 0.0) > 0.0:
                entry['delay'] = round(float(out['ActivateDelay']), 4)
            if out.get('bDisabled'):
                entry['disabled'] = True
            # A sub-sequence's output is fed from inside, by a FinishSequence.
            inner = ref_export(out.get('LinkedOp'))
            if cls == 'Sequence' and inner:
                entry['from'] = node_id(mr.label, inner)
            outs.append(entry)
        node['outs'] = outs
        if cls == 'Sequence':
            # ...and its inputs lead to the SequenceActivated events inside.
            node['ports'] = [node_id(mr.label, op) if op else None
                             for link in _struct_array(mr, props.get('InputLinks'))
                             for op in [ref_export(link.get('LinkedOp'))]]
        links = {}
        for link in _struct_array(mr, props.get('VariableLinks')):
            found = [variable(v) for v in _int_array(mr, link.get('LinkedVariables'))
                     if v > 0 and pkg.class_of(pkg.exports[v - 1]) != 'InterpData']
            if found:
                links[str(link.get('LinkDesc'))] = found
        if links:
            node['vars'] = links
        events = [node_id(mr.label, v) for link in _struct_array(mr, props.get('EventLinks'))
                  for v in _int_array(mr, link.get('LinkedEvents')) if v > 0]
        if events:
            node['events'] = events
        scalars = _scalar_props(props)
        if scalars:
            node['props'] = scalars

        originator = ref_export(props.get('Originator'))
        if originator:
            aid = _note_actor(originator)
            if aid:
                node['originator'] = aid
                if 'trigger' not in actors[aid]:
                    trigger = _trigger(packages, mr, originator)
                    if cls in DAMAGE_EVENTS:
                        # This project has no kick and no gun: the level fires
                        # these when the player runs into the spot, as the
                        # matinees' own starts have always done.
                        trigger.pop('hull', None)
                        trigger.update(radius=KICK_REACH_M, height=KICK_HALF_HEIGHT_M)
                    actors[aid]['trigger'] = trigger
        if cls == 'SeqAct_Interp':
            node['length'], node['events_at'] = _interp(mr, props)
            # The name matinee.collect() gives the same action.
            node['matinee'] = '%s#%d' % (mr.label, i)
        elif cls == 'SeqAct_SetStaticMesh' and mesh_of is not None:
            # The record, not its name: a name is only final once every mesh
            # of the level is known (extract.py settles it after the fact).
            record = mesh_of(mr, props.get('NewStaticMesh'))
            if record is not None:
                node['_mesh_record'] = record
        elif cls == 'SeqAct_Teleport':
            # Where each destination STANDS. Most are markers and triggers the
            # level builds nothing for, so the place travels with the node;
            # settle_teleports() moves it for one a sequence has carried off.
            spots = []
            for link in _struct_array(mr, props.get('VariableLinks')):
                if str(link.get('LinkDesc')) != 'Destination':
                    continue
                for var in _int_array(mr, link.get('LinkedVariables')):
                    spot = ref_export(_props(mr, var).get('ObjValue')) if var > 0 else None
                    aid = _actor_id(mr, spot)
                    if not aid:
                        continue
                    placed, _ = pk.resolved_props(packages, mr, spot)
                    if placed and 'Location' in placed:
                        spots.append({'actor': aid, 'position': point(placed['Location']),
                                      'basis': godot_basis(placed.get('Rotation') or (0, 0, 0), (1.0, 1.0, 1.0))})
            if spots:
                node['destinations'] = spots
        elif cls == 'SeqAct_ActorFactory' and mesh_of is not None:
            # Only a factory of static meshes, which is how the original puts
            # SCENERY in at run time: the subway's train ride ends by spawning
            # four still tunnel pieces where its rolling four were, and only
            # then hides those. Rigid bodies and emitters have nothing here.
            factory = ref_export(props.get('Factory'))
            if factory and pkg.class_of(pkg.exports[factory - 1]) == 'ActorFactoryStaticMesh':
                made = _props(mr, factory)
                record = mesh_of(mr, made.get('StaticMesh'))
                spots = []
                for link in _struct_array(mr, props.get('VariableLinks')):
                    if str(link.get('LinkDesc')) != 'Spawn Point':
                        continue
                    for var in _int_array(mr, link.get('LinkedVariables')):
                        spot = ref_export(_props(mr, var).get('ObjValue')) if var > 0 else None
                        if not spot:
                            continue
                        placed, _ = mr.props_inherited(spot)
                        if placed and 'Location' in placed:
                            spots.append({'position': point(placed['Location']),
                                          'basis': godot_basis(placed.get('Rotation') or (0, 0, 0), actor_scale(made))})
                if record is not None and spots:
                    node['_mesh_record'] = record
                    node['spawn_points'] = spots
        elif cls in ('SeqAct_MultiLevelStreaming', 'SeqAct_LevelStreaming'):
            levels = [x.get('LevelName') for x in _struct_array(mr, props.get('Levels'))] or [props.get('LevelName')]
            node['levels'] = [package_key(n) for n in levels if n and str(n) != 'None']
        nodes[node_id(mr.label, i)] = node
    return nodes


# What a node has to be for the level to be any different for its running.
# Everything else -- a checkpoint being set, the look-at hint being moved, an
# AI being told where to walk, music -- changes nothing this project has.
SPAWNS_SCENERY = 'SeqAct_ActorFactory'
EFFECTS_ON_ACTORS = ('SeqAct_Toggle', 'SeqAct_ToggleHidden', 'SeqAct_ChangeCollision', 'SeqAct_Destroy',
                     'SeqAct_SetStaticMesh')
EFFECTS = ('SeqAct_MultiLevelStreaming', 'SeqAct_LevelStreaming', 'SeqAct_TdInElevator', 'SeqAct_Teleport',
           'SeqAct_TdPlayerFail', 'SeqAct_TdFallOnBack')


def _track_position(keys, frame, time):
    """Where a move track has its actor at `time`: LINEAR between keys, which
    is exact at a key -- and a teleport is fired from one (an event at 0, or
    the sequence's end)."""
    points = keys.get('position') or []
    if not points:
        return None
    time = min(max(time, points[0]['time']), points[-1]['time'])
    value = points[-1]['value']
    for a, b in zip(points, points[1:]):
        if a['time'] <= time <= b['time']:
            f = 0.0 if b['time'] == a['time'] else (time - a['time']) / (b['time'] - a['time'])
            value = [a['value'][i] + (b['value'][i] - a['value'][i]) * f for i in range(3)]
            break
    if keys.get('absolute'):
        return [round(v, 4) for v in value]
    columns = frame['basis']
    return [round(frame['position'][i] + sum(columns[c][i] * value[c] for c in range(3)), 4) for i in range(3)]


def settle_teleports(graph, matinees):
    """A destination a sequence moves is where the sequence has PUT it by the
    time the teleport fires. [ME:CONFIRMED Boat] a first-person cutscene is a
    SkeletalMeshActor on a move track whose event track teleports the player
    onto it; nothing is built for that actor, so nothing at run time could
    say where it has got to."""
    by_name = {m['name']: m for m in matinees}
    for node in graph['nodes'].values():
        played = by_name.get(node.get('matinee')) if node['cls'] == 'SeqAct_Interp' else None
        if not played:
            continue
        times = {e['name']: e['time'] for e in node.get('events_at', [])}
        times['Completed'] = node.get('length', 0.0)
        for out in node['outs']:
            if out['name'] not in times:
                continue
            for target, _ in out['to']:
                for spot in graph['nodes'].get(target, {}).get('destinations', []):
                    for group in played['groups']:
                        for driven in group['actors']:
                            label, _, name = driven.partition('.me1.')
                            if '%s.%s' % (package_key(label), name) != spot['actor'] or driven not in played['frames']:
                                continue
                            moved = _track_position(group['keys'], played['frames'][driven], times[out['name']])
                            if moved:
                                spot['position'] = moved


def mark_useful(graph, built_actors, built_matinees, handled_elsewhere=frozenset()):
    """Sets `useful` on every actor whose events can lead to something that
    has an effect here; the builder makes a zone for those and no others.

    A chapter has some two hundred and thirty actors that originate events and
    most lead only to a checkpoint, a look-at point or an AI: built, they were
    a wall of zones in the debug overlay and a touch event fired for nothing.

    REACHABILITY, generously: from an event, along every output of every node
    met, across remote events by name, in and out of sub-sequences, and from a
    node that writes a variable to every node that reads it. Arriving at a
    Gate's Open counts as reaching what the Gate leads to -- Stormdrain's
    Trigger_14 does nothing but open one, and the unload behind it is the
    point of the corridor. Too generous keeps a zone that does nothing; too
    strict loses a door, so it errs the first way.

    `handled_elsewhere` are actors whose events this project answers with
    something of its own, and whose zone would answer them a second time:
    [ME:CONFIRMED] a pane of glass is a TakeDamage that hides the pane and
    hurts the fracture mesh behind it, and BreakableGlass is that, with the
    shatter. Left in, the graph took the pane away on the touch and there was
    nothing left to break."""
    nodes, variables, actors = graph['nodes'], graph['vars'], graph['actors']
    listeners, readers, finishes = {}, {}, {}
    for nid, node in nodes.items():
        if node['cls'] == 'SeqEvent_RemoteEvent':
            listeners.setdefault(str(node.get('props', {}).get('EventName', '')).lower(), []).append(nid)
        for linked in node.get('vars', {}).values():
            for var in linked:
                readers.setdefault(var, []).append(nid)
        if node['cls'] == 'Sequence':
            for out in node['outs']:
                if out.get('from'):
                    finishes.setdefault(out['from'], []).extend(t[0] for t in out['to'])

    def following(nid):
        node = nodes[nid]
        out = [t[0] for o in node['outs'] for t in o['to']]
        if node['cls'] == 'SeqAct_ActivateRemoteEvent':
            out += listeners.get(str(node.get('props', {}).get('EventName', '')).lower(), [])
        if node['cls'] == 'Sequence':
            out += [port for port in node.get('ports', []) if port]
        out += finishes.get(nid, [])
        # From a node that WRITES a value to the nodes that read it. Only
        # values: an object variable is shared by everything that names the
        # player, and followed it joins the whole chapter into one.
        for linked in node.get('vars', {}).values():
            for var in linked:
                if variables.get(var, {}).get('cls') in ('SeqVar_Bool', 'SeqVar_Int', 'SeqVar_Float', 'SeqVar_String', 'SeqVar_Named'):
                    out += [r for r in readers.get(var, []) if r != nid]
        out += node.get('events', [])
        return [n for n in out if n in nodes]

    def has_effect(node, useful):
        if node['cls'] in EFFECTS:
            return True
        if node['cls'] == 'SeqAct_Interp':
            return node.get('matinee') in built_matinees
        if node['cls'] == SPAWNS_SCENERY:
            return 'spawn_points' in node
        if node['cls'] == 'SeqAct_CauseDamage':
            # Only when it can be the PLAYER who is hurt: named as such, or an
            # object variable nothing fills but an event's Instigator.
            return any(variables.get(var, {}).get('cls') in ('SeqVar_Player', 'SeqVar_TdLocalPawn')
                       or (variables.get(var, {}).get('cls') == 'SeqVar_Object' and not variables[var].get('actor'))
                       for var in node.get('vars', {}).get('Target', []))
        if node['cls'] in EFFECTS_ON_ACTORS:
            for var in node.get('vars', {}).get('Target', []):
                entry = variables.get(var, {})
                for actor in [entry.get('actor')] + list(entry.get('actors', [])):
                    if actor and (actor in built_actors or actor in useful or 'wall' in actors.get(actor, {})):
                        return True
            # Switching an EVENT on or off matters when that event does.
            return any(nodes[e].get('originator') in useful for e in node.get('events', []) if e in nodes)
        return False

    events_of = {}
    for nid, node in nodes.items():
        if node.get('originator'):
            events_of.setdefault(node['originator'], []).append(nid)
    reach = {}
    for actor, events in events_of.items():
        if actor in handled_elsewhere:
            continue
        seen, todo = set(events), list(events)
        while todo:
            for nxt in following(todo.pop()):
                if nxt not in seen:
                    seen.add(nxt)
                    todo.append(nxt)
        reach[actor] = seen
    # To a fixpoint: a zone that only switches another zone on is useful when
    # that one is.
    useful = set()
    while True:
        found = {actor for actor, seen in reach.items()
                 if actor not in useful and any(has_effect(nodes[n], useful) for n in seen)}
        if not found:
            break
        useful |= found
    for actor in useful:
        actors[actor]['useful'] = True
    return len(useful), len(events_of)


def collect(packages, report, built_actors=frozenset(), built_matinees=frozenset(), handled_elsewhere=frozenset(),
            mesh_of=None, overrides=None):
    """manifest['kismet'] for a chapter. `built_actors` are the actors the
    level has nodes for, `built_matinees` the sequences it has Matinee nodes
    for, `handled_elsewhere` the actors whose events it answers some other
    way, all as this module spells them: see mark_useful()."""
    streamed = packages.streamed_packages()
    nodes, actors, variables = {}, {}, {}
    for name in sorted(os.listdir(packages.chapter_dir)):
        if not name.lower().endswith('.me1'):
            continue
        if name != packages.persistent and package_key(name) not in streamed:
            continue
        nodes.update(read_package(packages, packages.reader(name), actors, variables, mesh_of))
    # A volume that starts off and that NOTHING in the graph names can never
    # come on, but the shell has built it, hurting: it is listed all the same,
    # so that the level turns it off with the rest.
    idle = 0
    for name in sorted(os.listdir(packages.chapter_dir)):
        if not name.lower().endswith('.me1') or (name != packages.persistent and package_key(name) not in streamed):
            continue
        mr = packages.reader(name)
        for i, e in enumerate(mr.pkg.exports, 1):
            cls = mr.pkg.class_of(e)
            if not cls.endswith('Volume') or outer_class(mr.pkg, e) != 'Level':
                continue
            aid = '%s.%s' % (package_key(name), e['name'])
            if aid in actors:
                continue
            inherited, _ = mr.props_inherited(i)
            if inherited and inherited.get('bCollideActors') is False:
                actors[aid] = {'cls': cls, 'package': package_key(name), 'starts_off': True}
                idle += 1
    report.setdefault('kismet_idle_volumes', idle)
    classes = {}
    for node in nodes.values():
        classes[node['cls']] = classes.get(node['cls'], 0) + 1
    report['kismet'] = {'nodes': len(nodes), 'variables': len(variables), 'actors': len(actors),
                        'classes': dict(sorted(classes.items(), key=lambda kv: -kv[1]))}
    for node_id, patch in (overrides or {}).items():
        if node_id not in nodes:
            raise ExtractError('kismet_overrides names no such node: %s' % node_id)
        patch = dict(patch)
        nodes[node_id].setdefault('props', {}).update(patch.pop('props', {}))
        nodes[node_id].update(patch)
    report['kismet']['overridden'] = sorted((overrides or {}).keys())
    graph = {'persistent': package_key(packages.persistent), 'nodes': nodes, 'vars': variables, 'actors': actors}
    kept, originating = mark_useful(graph, built_actors, built_matinees, handled_elsewhere)
    report['kismet']['event_zones'] = {'useful': kept, 'of': originating}
    return graph

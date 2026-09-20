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

from common import outer_class, ref_export
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


def read_package(packages, mr, actors, variables):
    """This package's nodes; fills `actors` and `variables` as it meets them."""
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
        elif cls in ('SeqAct_MultiLevelStreaming', 'SeqAct_LevelStreaming'):
            levels = [x.get('LevelName') for x in _struct_array(mr, props.get('Levels'))] or [props.get('LevelName')]
            node['levels'] = [package_key(n) for n in levels if n and str(n) != 'None']
        nodes[node_id(mr.label, i)] = node
    return nodes


def collect(packages, report):
    """manifest['kismet'] for a chapter."""
    streamed = packages.streamed_packages()
    nodes, actors, variables = {}, {}, {}
    for name in sorted(os.listdir(packages.chapter_dir)):
        if not name.lower().endswith('.me1'):
            continue
        if name != packages.persistent and package_key(name) not in streamed:
            continue
        nodes.update(read_package(packages, packages.reader(name), actors, variables))
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
    return {'persistent': package_key(packages.persistent), 'nodes': nodes, 'vars': variables, 'actors': actors}

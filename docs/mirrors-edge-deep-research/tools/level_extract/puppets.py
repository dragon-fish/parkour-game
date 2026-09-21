"""The people a Matinee animates: who they are, what is played on them and when.

[ME:CONFIRMED] a cutscene here is an InterpTrackAnimControl per character, on a
SkeletalMeshActor standing in the level (hidden until its scene), playing
AnimSequences out of the group's GroupAnimSets. Sp09 has 35 such actors: ten
SWAT, Jacknife, Kate, a fixer, their guns and handcuffs, two rats and two
pigeons. Each becomes a PUPPET -- the original's own mesh on its own skeleton
(skeletal_glb), stood where the actor stands -- and each sequence that animates
it says which of its animations plays from when (`plays`).

Not the scenery extract.py flies on a move track (SKELETAL_SCENERY): that has
no skeleton here, and its animation is already its path.
"""
import os
import struct

import packages as pk
import skeletal_anim
import skeletal_glb
import skeletal_mesh
from common import ExtractError, actor_scale, godot_basis, import_root_package, point, ref_export
from streaming import package_key
from matinee import _int_array, _props, _struct_array, _value


# SkeletalMeshActorMAT is the one Matinee may swap the animation tree of: every
# "Faith 1p" stand-in is one, the first-person body a cutscene is seen from.
PUPPET_CLASSES = ('SkeletalMeshActor', 'SkeletalMeshActorMAT')


# The body a first-person cutscene is SEEN FROM. The level stands a one-bone
# placeholder where the scene happens and plays the animation on the player's
# own pawn, whose first-person body is two meshes on one 74-bone skeleton with
# an EyeJoint and a CameraJoint: {placeholder mesh: (package, meshes)}.
# [ME:CONFIRMED] "Fixer" is Faith's name in the data.
FIRST_PERSON_BODIES = {'CINE_Female1p': ('CH_TKY_Crim_Fixer_1P', ('SK_UpperBody', 'SK_LowerBody'))}
PLAYER_VARIABLES = ('SeqVar_Player', 'SeqVar_TdLocalPawn')
# A first-person animation is the PAWN's, and a pawn's origin is the middle of
# its capsule, not its feet. [ME:DERIVED] 94 uu: stood at the stand-in's own
# place, the body's toes were 0.94 m under the Escape's office floor from the
# first frame of cs3_r1_faith to the last; and 94 is the Origin the original's
# character meshes carry (SK_TKY_Crim_Jacknife: (0, 94, 0)) to be set down by
# exactly that much when one is NOT on a pawn.
PAWN_HALF_HEIGHT_UU = 94.0


def _bone_names(cache, reader, idx):
    key = (reader.label, idx)
    if key not in cache:
        cache[key] = {b['name'] for b in skeletal_mesh.parse_render(reader, idx)['skeleton']['bones']}
    return cache[key]


def _sequences_for(mr, group_idx, bone_names):
    """{sequence name: export index} over the group's GroupAnimSets, and where
    two sets have a sequence of one name -- a cutscene's Faith1P and Faith3P
    sets both have `cs3_r1_faith` -- the one whose tracks fit this skeleton."""
    best = {}
    for anim_set in _int_array(mr, _props(mr, group_idx).get('GroupAnimSets')):
        if anim_set <= 0:
            continue
        tracks = set()
        for tag in mr.chain_of(anim_set, widest=True)[0]:
            if tag[0] == 'TrackBoneNames':
                count = struct.unpack_from('<i', mr.d, tag[3])[0]
                tracks = {mr.pkg.name(struct.unpack_from('<i', mr.d, tag[3] + 4 + 8 * k)[0]) for k in range(count)}
        fit = len(tracks & bone_names) - len(tracks - bone_names)
        for sequence in _int_array(mr, _props(mr, anim_set).get('Sequences')):
            if sequence <= 0:
                continue
            chain = {tag[0]: tag for tag in mr.chain_of(sequence, widest=True)[0]}
            if 'SequenceName' in chain:
                name = str(_value(mr, chain['SequenceName']))
                if name not in best or fit > best[name][0]:
                    best[name] = (fit, sequence)
    return {name: entry[1] for name, entry in best.items()}


def _mesh_of(packages, mr, actor):
    """(reader, export index) of the actor's SkeletalMesh, or None."""
    component = actor.get('SkeletalMeshComponent')
    props = pk.resolved_props(packages, mr, component[1])[0] if isinstance(component, tuple) and len(component) == 2 \
        and component[0] == 'obj' and component[1] > 0 else {}
    ref = (props or {}).get('SkeletalMesh')
    if not (isinstance(ref, tuple) and len(ref) == 2 and ref[0] == 'obj' and ref[1]):
        return None
    if ref[1] > 0:
        return (mr, ref[1]) if mr.pkg.class_of(mr.pkg.exports[ref[1] - 1]) == 'SkeletalMesh' else None
    imported = -ref[1] - 1
    name = mr.pkg.imports[imported]['name']
    try:
        shared = packages.shared_reader(import_root_package(mr.pkg, imported))
    except Exception:
        shared = None
    if shared is None:
        return None
    idx = next((i for i, e in enumerate(shared.pkg.exports, 1)
                if e['name'] == name and shared.pkg.class_of(e) == 'SkeletalMesh'), None)
    return (shared, idx) if idx else None


def collect(packages, mr, report, left_out=()):
    """(puppets, plays) of one package.

    puppets: {actor id: {name, package, position, basis, hidden, _mesh: (reader, idx), _sequences: {name: idx}}}
    plays:   {matinee name: {actor id: [{animation, start, offset, rate, loops}]}}
    """
    pkg = mr.pkg
    puppets, plays = {}, {}
    bone_cache = {}
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) != 'SeqAct_Interp':
            continue
        groups, variables, played_on_player = [], {}, set()
        for link in _struct_array(mr, _props(mr, i).get('VariableLinks')):
            for var in _int_array(mr, link.get('LinkedVariables')):
                if var <= 0:
                    continue
                cls = pkg.class_of(pkg.exports[var - 1])
                if cls == 'InterpData':
                    for g in _int_array(mr, _props(mr, var).get('InterpGroups')):
                        gp = _props(mr, g)
                        for t in _int_array(mr, gp.get('InterpTracks')):
                            if pkg.class_of(pkg.exports[t - 1]) == 'InterpTrackAnimControl':
                                groups.append((gp.get('GroupName') or 'InterpGroup', g, t))
                elif cls in PLAYER_VARIABLES:
                    played_on_player.add(link.get('LinkDesc') or 'None')
                elif cls.startswith('SeqVar_Object'):
                    obj = _props(mr, var).get('ObjValue')
                    if isinstance(obj, tuple) and obj[0] == 'obj' and obj[1] > 0:
                        variables.setdefault(link.get('LinkDesc') or 'None', []).append(obj[1])
        for group_name, group_idx, track_idx in groups:
            for obj in variables.get(group_name, []):
                if pkg.class_of(pkg.exports[obj - 1]) not in PUPPET_CLASSES:
                    continue
                actor, _ = pk.resolved_props(packages, mr, obj)
                mesh = _mesh_of(packages, mr, actor)
                if mesh is None:
                    report['puppets_without_mesh'] = report.get('puppets_without_mesh', 0) + 1
                    continue
                mesh_name = mesh[0].pkg.exports[mesh[1] - 1]['name']
                if mesh_name.startswith(tuple(left_out)):
                    continue
                more, first_person = (), False
                if group_name in played_on_player and mesh_name in FIRST_PERSON_BODIES:
                    package, halves = FIRST_PERSON_BODIES[mesh_name]
                    shared = packages.shared_reader(package)
                    found = [next((k for k, x in enumerate(shared.pkg.exports, 1) if x['name'] == half
                                   and shared.pkg.class_of(x) == 'SkeletalMesh'), None) for half in halves] if shared else []
                    if found and all(found):
                        mesh, more, first_person = (shared, found[0]), tuple(found[1:]), True
                known = _sequences_for(mr, group_idx, _bone_names(bone_cache, mesh[0], mesh[1]))
                # The widest chain, for skeletal_anim.flight_keys()'s reason.
                wide = {tag[0]: _value(mr, tag) for tag in mr.chain_of(track_idx, widest=True)[0]}
                played = []
                for entry in _struct_array(mr, wide.get('AnimSeqs')):
                    name = str(entry.get('AnimSeqName'))
                    if name in known:
                        played.append({'animation': name, 'start': float(entry.get('StartTime', 0.0)),
                                       'offset': float(entry.get('AnimStartOffset', 0.0)),
                                       'rate': float(entry.get('AnimPlayRate', 1.0)),
                                       'loops': bool(entry.get('bLooping', False))})
                if not played:
                    continue
                actor_id = '%s.%s' % (mr.label, pkg.exports[obj - 1]['name'])
                # What it stands ON. [ME:CONFIRMED] the Scraper's Jacknife and
                # Kate are hard-attached to the Blackhawk's VH_Main bone, which
                # is the bone that helicopter is flown by here: they ride it as
                # a carriage rides its train, and their own animation -- the
                # walk across the cabin -- goes on top.
                based = ref_export(actor.get('Base')) if actor.get('bHardAttach') else None
                base = '%s.%s' % (mr.label, pkg.exports[based - 1]['name']) if based else None
                puppet = puppets.setdefault(actor_id, {
                    'base': base,
                    'name': pkg.exports[obj - 1]['name'], 'package': mr.label,
                    'position': point(tuple(c + (PAWN_HALF_HEIGHT_UU if first_person and k == 2 else 0.0)
                                            for k, c in enumerate(actor.get('Location') or (0.0, 0.0, 0.0)))),
                    'basis': godot_basis(actor.get('Rotation') or (0, 0, 0), actor_scale(actor)),
                    'hidden': bool(actor.get('bHidden', False)), '_mesh': mesh, '_more': more, '_sequences': {}}
                    | ({'first_person': True} if first_person else {}))
                for play in played:
                    puppet['_sequences'][play['animation']] = known[play['animation']]
                plays.setdefault('%s#%d' % (mr.label, i), {})[actor_id] = sorted(played, key=lambda p: p['start'])
    return puppets, plays


def write_bodies(puppets, readers, out_dir, report):
    """One .glb per (package, mesh): the mesh, its skeleton and every sequence
    any puppet of that package plays on it. Sets each puppet's `body` to the
    file's name and drops the working keys."""
    os.makedirs(out_dir, exist_ok=True)
    bodies = {}
    for puppet in puppets.values():
        mesh_reader, mesh_idx = puppet['_mesh']
        key = (puppet['package'], mesh_reader.label, mesh_idx)
        bodies.setdefault(key, {}).update(puppet['_sequences'])
    names = {}
    for (package, mesh_label, mesh_idx), sequences in bodies.items():
        mesh_reader = next(p['_mesh'][0] for p in puppets.values()
                           if p['package'] == package and p['_mesh'][0].label == mesh_label and p['_mesh'][1] == mesh_idx)
        mesh_name = mesh_reader.pkg.exports[mesh_idx - 1]['name']
        file_name = ('%s__%s.glb' % (package_key(package), mesh_name)).lower()
        try:
            more = next(p['_more'] for p in puppets.values()
                        if p['package'] == package and p['_mesh'][0].label == mesh_label and p['_mesh'][1] == mesh_idx)
            _, animations = skeletal_glb.build(mesh_reader, mesh_idx, sorted(set(sequences.values())),
                                               os.path.join(out_dir, file_name), sequence_reader=readers[package],
                                               more_meshes=more)
        except (ExtractError, KeyError, IndexError, ValueError) as error:
            report.setdefault('puppet_bodies_failed', []).append('%s: %s' % (file_name, error))
            continue
        names[(package, mesh_label, mesh_idx)] = file_name
        report.setdefault('puppet_bodies', {})[file_name] = len(animations)
    out = []
    for actor_id, puppet in puppets.items():
        mesh_reader, mesh_idx = puppet.pop('_mesh')
        puppet.pop('_sequences')
        puppet.pop('_more')
        body = names.get((puppet['package'], mesh_reader.label, mesh_idx))
        if body:
            out.append(dict(puppet, id=actor_id, body=body))
    return out

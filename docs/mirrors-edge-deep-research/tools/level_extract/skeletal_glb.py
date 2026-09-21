"""A skinned mesh and the AnimSequences played on it, as one .glb.

    uv run --no-project --python 3.12 --with lzallright --with numpy skeletal_glb.py \\
        <level config> <package> <SkeletalMesh name> <out.glb> [sequence name ...]

The mesh keeps its own skeleton and its own bone names (HumanIK's, for the
people: Hips, Spine, LeftUpLeg ...), so what Godot imports can be played as it
is or mapped onto a humanoid profile and played on another body.

Conventions, each checked against the data rather than assumed:

  * A reference-pose orientation is used AS STORED. Posed that way every bone
    of SK_TKY_Cop_SWAT_Sniper lands 7.8 uu, on average, from the middle of the
    vertices skinned to it; with W negated, 88.8.
  * An animation key off the root has W NEGATED against that (UE3's own rule,
    applied in skeletal_anim.bone_tracks): cs16_jacknife's first keys agree
    with the reference pose to 0.966 that way and 0.754 the other.
  * UE is left-handed and Z-up in centimetres, glTF right-handed and Y-up in
    metres. Positions swap Y and Z (common.to_godot); a rotation R becomes
    M R M with M that same swap; triangles turn over.
  * The mesh's RotOrigin is the transform of the node the skeleton hangs from,
    so a scene places the .glb with the ACTOR's transform and nothing else.
"""
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import packages  # noqa: E402
import skeletal_anim as sa  # noqa: E402
import skeletal_mesh  # noqa: E402
from common import UU  # noqa: E402
from matinee import _value  # noqa: E402

SWAP = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])


def _matrix(columns):
    """skeletal_anim's list-of-columns as a numpy matrix, in glTF's axes."""
    return SWAP @ np.array(columns).T @ SWAP


def _point(v):
    return np.array([v[0], v[2], v[1]]) / UU


def _quat(m):
    """(x, y, z, w) of rotation matrix `m`."""
    trace = m[0, 0] + m[1, 1] + m[2, 2]
    if trace > 0.0:
        s = math.sqrt(trace + 1.0) * 2.0
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    else:
        i = int(np.argmax([m[0, 0], m[1, 1], m[2, 2]]))
        j, k = (i + 1) % 3, (i + 2) % 3
        s = math.sqrt(max(m[i, i] - m[j, j] - m[k, k] + 1.0, 1e-12)) * 2.0
        q = [0.0, 0.0, 0.0, (m[k, j] - m[j, k]) / s]
        q[i] = 0.25 * s
        q[j] = (m[j, i] + m[i, j]) / s
        q[k] = (m[k, i] + m[i, k]) / s
    n = math.sqrt(sum(c * c for c in q))
    return [c / n for c in q]


class Glb:
    def __init__(self):
        self.doc = {'asset': {'version': '2.0', 'generator': 'me level_extract skeletal_glb'}, 'buffers': [{}],
                    'bufferViews': [], 'accessors': [], 'nodes': [], 'scenes': [{'nodes': []}], 'scene': 0}
        self.blob = bytearray()

    def accessor(self, array, kind, component, target=None, bounds=False):
        array = np.ascontiguousarray(array)
        while len(self.blob) % 4:
            self.blob.append(0)
        view = {'buffer': 0, 'byteOffset': len(self.blob), 'byteLength': array.nbytes}
        if target:
            view['target'] = target
        self.blob += array.tobytes()
        self.doc['bufferViews'].append(view)
        entry = {'bufferView': len(self.doc['bufferViews']) - 1, 'componentType': component,
                 'count': int(array.shape[0]), 'type': kind}
        if bounds:
            flat = array.reshape(array.shape[0], -1)
            entry['min'] = [float(c) for c in flat.min(axis=0)]
            entry['max'] = [float(c) for c in flat.max(axis=0)]
        self.doc['accessors'].append(entry)
        return len(self.doc['accessors']) - 1

    def write(self, path):
        while len(self.blob) % 4:
            self.blob.append(0)
        self.doc['buffers'][0]['byteLength'] = len(self.blob)
        text = json.dumps(self.doc, separators=(',', ':')).encode('utf-8')
        text += b' ' * (-len(text) % 4)
        with open(path, 'wb') as out:
            out.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(text) + 8 + len(self.blob)))
            out.write(struct.pack('<I4s', len(text), b'JSON') + text)
            out.write(struct.pack('<I4s', len(self.blob), b'BIN\x00') + bytes(self.blob))


def build(mr, mesh_idx, sequence_indices, out_path):
    record = skeletal_mesh.parse_render(mr, mesh_idx, with_skin=True)
    bones, skin = record['skeleton']['bones'], record['skin']
    glb = Glb()
    nodes = glb.doc['nodes']

    # Node 0 carries RotOrigin; the bones follow in the mesh's own order, so
    # bone k is node k + 1.
    nodes.append({'name': mr.pkg.exports[mesh_idx - 1]['name'], 'children': [],
                  'rotation': _quat(_matrix(sa._from_rotator(*record['skeleton']['rot_origin'])))})
    world = []
    for k, bone in enumerate(bones):
        local = np.eye(4)
        local[:3, :3] = _matrix(sa._from_quat(bone['rotation']))
        local[:3, 3] = _point(bone['position'])
        is_root = bone['parent'] == k or k == 0
        world.append(local if is_root else world[bone['parent']] @ local)
        nodes.append({'name': bone['name'], 'translation': [float(c) for c in local[:3, 3]],
                      'rotation': _quat(local[:3, :3])})
        nodes[0 if is_root else bone['parent'] + 1].setdefault('children', []).append(k + 1)

    positions = np.array([_point(v) for v in skin['raw_vertices']], dtype=np.float32)
    normals = np.frombuffer(__import__('base64').b64decode(record['normals']), dtype=np.float32).reshape(-1, 3)
    # parse_render() turned the normals by RotOrigin; the node does that here.
    unturn = _matrix(sa._from_rotator(*record['skeleton']['rot_origin'])).T
    normals = (normals @ unturn.T).astype(np.float32)
    primitives = []
    attributes = {'POSITION': glb.accessor(positions, 'VEC3', 5126, 34962, bounds=True),
                  'NORMAL': glb.accessor(normals, 'VEC3', 5126, 34962),
                  'JOINTS_0': glb.accessor(np.array(skin['joints'], dtype=np.uint16), 'VEC4', 5123, 34962),
                  'WEIGHTS_0': glb.accessor(np.array(skin['weights'], dtype=np.float32), 'VEC4', 5126, 34962)}
    materials = []
    for surface in record['surfaces']:
        indices = np.frombuffer(__import__('base64').b64decode(surface['indices']), dtype=np.uint16)
        if not len(indices):
            continue
        materials.append({'name': surface['material'] or 'none',
                          'pbrMetallicRoughness': {'baseColorFactor': [0.8, 0.8, 0.8, 1.0], 'metallicFactor': 0.0}})
        primitives.append({'attributes': attributes, 'indices': glb.accessor(indices.astype(np.uint32), 'SCALAR', 5125, 34963),
                           'material': len(materials) - 1})
    inverse_bind = np.array([np.linalg.inv(w).T for w in world], dtype=np.float32)
    glb.doc['materials'] = materials
    glb.doc['meshes'] = [{'name': nodes[0]['name'], 'primitives': primitives}]
    glb.doc['skins'] = [{'joints': list(range(1, len(bones) + 1)), 'skeleton': 1,
                         'inverseBindMatrices': glb.accessor(inverse_bind.reshape(-1, 16), 'MAT4', 5126)}]
    nodes.append({'name': nodes[0]['name'] + '_mesh', 'mesh': 0, 'skin': 0})
    nodes[0]['children'].append(len(nodes) - 1)
    glb.doc['scenes'][0]['nodes'] = [0]

    by_name = {bone['name']: k for k, bone in enumerate(bones)}
    glb.doc['animations'] = []
    for sequence in sequence_indices:
        tags = {tag[0]: tag for tag in mr.chain_of(sequence, widest=True)[0]}
        tracks, length = sa.bone_tracks(mr, sequence)
        animation = {'name': str(_value(mr, tags['SequenceName'])), 'channels': [], 'samplers': []}
        for bone_name, (translations, rotations) in tracks.items():
            if bone_name not in by_name:
                continue
            for path, keys in (('translation', translations), ('rotation', rotations)):
                times = np.array([length * i / max(len(keys) - 1, 1) for i in range(len(keys))], dtype=np.float32)
                if path == 'translation':
                    values = np.array([_point(k) for k in keys], dtype=np.float32)
                else:
                    values = np.array([_quat(_matrix(sa._from_quat(k))) for k in keys], dtype=np.float32)
                    # The same rotation has two quaternions; keep neighbours
                    # on the same side or the lerp between them goes round.
                    for i in range(1, len(values)):
                        if float(np.dot(values[i], values[i - 1])) < 0.0:
                            values[i] = -values[i]
                animation['samplers'].append({'input': glb.accessor(times, 'SCALAR', 5126, bounds=True),
                                              'output': glb.accessor(values, 'VEC3' if path == 'translation' else 'VEC4', 5126),
                                              'interpolation': 'LINEAR'})
                animation['channels'].append({'sampler': len(animation['samplers']) - 1,
                                              'target': {'node': by_name[bone_name] + 1, 'path': path}})
        glb.doc['animations'].append(animation)
    if not glb.doc['animations']:
        del glb.doc['animations']
    glb.write(out_path)
    return record, [a['name'] for a in glb.doc.get('animations', [])]


def main(argv):
    config_path, package, mesh_name, out_path = argv[:4]
    wanted = set(argv[4:])
    root = str(Path(__file__).resolve().parents[4])
    config = packages.load_config(config_path)
    reader = packages.PackageSet(root, config, str(Path(root, '_local/me-reference/level-extract/_cache'))).reader(package)
    pkg = reader.pkg
    mesh = next(i for i, e in enumerate(pkg.exports, 1) if e['name'] == mesh_name and pkg.class_of(e) == 'SkeletalMesh')
    sequences = []
    for i, e in enumerate(pkg.exports, 1):
        if pkg.class_of(e) == 'AnimSequence':
            tags = {tag[0]: tag for tag in reader.chain_of(i, widest=True)[0]}
            if str(_value(reader, tags['SequenceName'])) in wanted:
                sequences.append(i)
    record, names = build(reader, mesh, sequences, out_path)
    print('%s: %d vertices, %d bones, animations %s -> %s' % (mesh_name, record['vertex_count'],
                                                           len(record['skeleton']['bones']), names, out_path))


if __name__ == '__main__':
    main(sys.argv[1:])

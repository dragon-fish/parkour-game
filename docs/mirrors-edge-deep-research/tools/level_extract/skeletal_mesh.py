"""SkeletalMesh render data (LOD0) in its reference pose, package version 536.

Read for the SCENERY that happens to be skinned -- the helicopters two chapters
end on -- and returned in static_mesh.parse_render()'s shape, so everything
downstream draws it as the rigid thing it is here. Nothing of the skeleton
survives: no bones, no weights, no animation (a rotor stands still).

[ME:CONFIRMED] the layout, walked on SK_SWAT_Blackhawk_01_exterior and
SK_VH_Helicopter_01 and checked against the data at every step:

    tagged properties, then 4 bytes
    FBoxSphereBounds            7 floats
    Materials                   count, object references
    Origin, RotOrigin           3 floats, 3 ints (pitch, yaw, roll)
    RefSkeleton                 count x 52 bytes: name 8, flags 4, orientation 4f,
                                position 3f, child count, parent, colour
    SkeletalDepth               int
    LODModels                   count, then per LOD:
        Sections                count x (WORD material, WORD chunk, DWORD first index, WORD triangles)
        IndexBuffer             element size 2, count, WORDs
        ShadowIndices           count, WORDs
        ActiveBoneIndices       count, WORDs
        ShadowTriangleDoubleSided   count, bytes
        Chunks                  count, then per chunk:
            BaseVertexIndex     DWORD
            RigidVertices       count x (position 3f, 3 packed normals, 3 x 2f UVs, bone byte)
            SoftVertices        count x (the same, 4 bone bytes, 4 weight bytes)
            BoneMap             count, WORDs
            NumRigidVertices, NumSoftVertices, MaxBoneInfluences

The cooked chunks still hold their vertices (the GPU buffer after them is a
second copy), in MESH space at the reference pose, so no bone is needed to
place one. A vertex's index is its chunk's BaseVertexIndex plus its place in
the chunk, rigid before soft.
"""
import math
import struct

from common import ExtractError, godot_basis, to_godot, UU
from static_mesh import _b64, pkg_name, ref_name

# A chunk vertex has room for this many UV sets whatever NumUVSets says; the
# property is how many of them mean anything (the Edge's helicopter: 1).
UV_SLOTS = 3


def parse_render(mr, idx, with_skin=False):
    """`with_skin` adds `skin`: per vertex, four bone indices (into the
    skeleton) and four weights summing to 1, and `raw_vertices`, the positions
    as the file has them (UE axes and units, RotOrigin NOT applied) -- what
    something that means to POSE the mesh needs, and nothing else does."""
    pkg, d = mr.pkg, mr.d
    e = pkg.exports[idx - 1]
    where = '%s.%s' % (pkg_name(mr), e['name'])
    end = e['offset'] + e['size']
    chain, p = mr.chain_of(idx, widest=True)
    if p is None:
        raise ExtractError('%s: no tagged properties' % where)
    uv_sets = 1
    for tag in chain:
        if tag[0] == 'NumUVSets':
            uv_sets = struct.unpack_from('<i', d, tag[3])[0]
    if not 1 <= uv_sets <= UV_SLOTS:
        raise ExtractError('%s: %d UV sets' % (where, uv_sets))
    p += 4

    def take(fmt):
        nonlocal p
        if p + struct.calcsize(fmt) > end:
            raise ExtractError('%s: ran off the export at +%d' % (where, p - e['offset']))
        values = struct.unpack_from(fmt, d, p)
        p += struct.calcsize(fmt)
        return values

    def skip(size):
        nonlocal p
        p += size

    # DO NOT add a count straight onto p: an augmented assignment reads p
    # BEFORE count() has moved it, and the count's own four bytes are lost.
    def count(limit, what):
        n = take('<i')[0]
        if not 0 <= n <= limit:
            raise ExtractError('%s: %d %s' % (where, n, what))
        return n

    ox, oy, oz, ex, ey, ez, radius = take('<7f')
    if abs(math.sqrt(ex * ex + ey * ey + ez * ez) - radius) > 0.01 * max(radius, 1.0):
        raise ExtractError('%s: bounds do not agree with their own radius' % where)
    materials = take('<%di' % count(64, 'materials'))
    origin = take('<3f')
    pitch, yaw, roll = take('<3i')
    bones = []
    for _ in range(count(512, 'bones')):
        # Name, flags, orientation, position, child count, parent, colour.
        name, _number, _flags, qx, qy, qz, qw, bx, by, bz, _children, parent, _colour = take('<3i7f3i')
        bones.append({'name': pkg.name(name), 'parent': parent, 'position': [bx, by, bz], 'rotation': [qx, qy, qz, qw]})
    take('<i')                                 # SkeletalDepth
    if count(8, 'LODs') < 1:
        raise ExtractError('%s: no LOD' % where)

    sections = [take('<HHIH') for _ in range(count(64, 'sections'))]
    stride, index_count = take('<2i')
    if stride != 2 or index_count % 3 or p + 2 * index_count > end:
        raise ExtractError('%s: index buffer %d x %d' % (where, stride, index_count))
    indices = struct.unpack_from('<%dH' % index_count, d, p)
    p += 2 * index_count
    if sum(s[3] for s in sections) * 3 != index_count:
        raise ExtractError('%s: section triangles do not sum to the index buffer' % where)
    skip(2 * count(index_count, 'shadow indices'))
    skip(2 * count(512, 'active bones'))
    skip(count(index_count, 'shadow flags'))

    rigid_bytes = 24 + 8 * UV_SLOTS + 1
    soft_bytes = 24 + 8 * UV_SLOTS + 8
    placed = {}
    influences = {}
    bound = [0] * len(bones)
    for _ in range(count(64, 'chunks')):
        at = take('<I')[0]
        first_bones = []
        for size in (rigid_bytes, soft_bytes):
            for _ in range(count(1 << 20, 'chunk vertices')):
                if p + size > end:
                    raise ExtractError('%s: chunk vertices run off the export' % where)
                placed[at] = p
                # Rigid: one bone, the whole weight. Soft: four bone bytes
                # then four weight bytes, of 255.
                tail = p + 24 + 8 * UV_SLOTS
                influences[at] = ([d[tail]], [255]) if size == rigid_bytes else (list(d[tail:tail + 4]), list(d[tail + 4:tail + 8]))
                # A rigid vertex's one bone, a soft vertex's first: an index
                # into the chunk's bone map, which follows the vertices.
                first_bones.append(d[p + 24 + 8 * UV_SLOTS])
                at += 1
                p += size
        bone_map = take('<%dH' % count(512, 'bone map'))
        for vertex in range(at - len(first_bones), at):
            local, weights = influences[vertex]
            influences[vertex] = ([bone_map[b] if w and b < len(bone_map) else 0 for b, w in zip(local, weights)], weights)
        for local in first_bones:
            if local >= len(bone_map) or bone_map[local] >= len(bones):
                raise ExtractError('%s: a vertex names bone %d of a map of %d' % (where, local, len(bone_map)))
            bound[bone_map[local]] += 1
        take('<3i')
    if not placed or max(indices) >= len(placed) or set(placed) != set(range(len(placed))):
        raise ExtractError('%s: %d vertices do not cover the index buffer' % (where, len(placed)))

    # The mesh stands as RotOrigin turns it: the Blackhawk is modelled nose-up
    # and lies down only through this. Baked in, so a placement is the actor's
    # own transform and nothing else.
    turn = godot_basis((pitch, yaw, roll), (1.0, 1.0, 1.0))

    def turned(v):
        return [sum(turn[c][k] * v[c] for c in range(3)) for k in range(3)]

    vertices, normals = [], []
    uvs = [[] for _ in range(uv_sets)]
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    for k in range(len(placed)):
        q = placed[k]
        x, y, z = struct.unpack_from('<3f', d, q)
        v = turned(to_godot(x + origin[0], y + origin[1], z + origin[2]))
        vertices.extend(v)
        lo = [min(lo[a], v[a]) for a in range(3)]
        hi = [max(hi[a], v[a]) for a in range(3)]
        # TangentZ, the third of the three packed vectors, is the normal.
        n = [b / 127.5 - 1.0 for b in d[q + 20:q + 23]]
        length = math.sqrt(sum(c * c for c in n)) or 1.0
        normals.extend(turned([n[0] / length, n[2] / length, n[1] / length]))
        for channel, out in enumerate(uvs):
            out.extend(struct.unpack_from('<2f', d, q + 24 + 8 * channel))

    skin = None
    if with_skin:
        skin = {'joints': [], 'weights': [], 'raw_vertices': []}
        for k in range(len(placed)):
            joints, weights = influences[k]
            total = float(sum(weights)) or 1.0
            skin['joints'].append((joints + [0, 0, 0])[:4])
            skin['weights'].append(([w / total for w in weights] + [0.0, 0.0, 0.0])[:4])
            skin['raw_vertices'].append(struct.unpack_from('<3f', d, placed[k]))

    surfaces = []
    for material, _chunk, first, triangles in sections:
        if material >= len(materials):
            raise ExtractError('%s: section names material %d of %d' % (where, material, len(materials)))
        tri = indices[first:first + triangles * 3]
        flipped = []
        for t in range(0, len(tri), 3):
            flipped.extend((tri[t], tri[t + 2], tri[t + 1]))
        surfaces.append({'material': ref_name(pkg, materials[material]), 'material_ref': materials[material],
                         'collide': False, 'indices': _b64('H', flipped)})
    return {
        'vertices': _b64('f', vertices),
        'normals': _b64('f', normals),
        'uvs': [_b64('f', channel) for channel in uvs],
        'vertex_count': len(placed),
        'triangle_count': index_count // 3,
        'kdop_triangles': 0,
        'collide_triangles': 0,
        # Of the vertices as they stand, not the file's: that one is padded for
        # every pose an animation might reach.
        'bounds': {'origin': [(lo[a] + hi[a]) * 0.5 for a in range(3)],
                   'extent': [(hi[a] - lo[a]) * 0.5 for a in range(3)]},
        'surfaces': surfaces,
        'body_setup': 0,
        'use_simple_box_collision': False,
        # For skeletal_anim, and popped by whoever asked before the record is
        # stored: what an animation has to move to move this mesh as one
        # piece is the bone most of it is skinned to.
        'skeleton': {'bones': bones, 'bound_to': bound.index(max(bound)), 'rot_origin': [pitch, yaw, roll],
                     'origin': list(origin)},
    } | ({'skin': skin} if skin else {})

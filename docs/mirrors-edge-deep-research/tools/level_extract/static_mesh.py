"""StaticMesh render data (LOD0), simple collision and physical material, package version 536."""
import base64
import math
import struct

from common import ExtractError, to_godot, UU
from hulls import HullReader

# Axis-aligned box corners -> triangles, winding as the existing box hulls use.
BOX_TRIANGLES = [0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6,
                 0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7,
                 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5]

# A packed normal of (128, 128, 128) is the zero vector: the mesh was cooked
# without normals. Anything else that is not unit length is a parse error.
# A zero vector packs to 127 or 128 per byte depending on rounding.
ZERO_NORMAL_BYTES = (127, 128)


def _b64(fmt, values):
    return base64.b64encode(struct.pack('<%d%s' % (len(values), fmt), *values)).decode('ascii')


def parse_render(mr, idx):
    """LOD0 of StaticMesh export #idx. Every section is checked against the
    data itself; the layout is documented in the level extractor spec."""
    pkg, d = mr.pkg, mr.d
    e = pkg.exports[idx - 1]
    where = '%s.%s' % (pkg_name(mr), e['name'])
    end = e['offset'] + e['size']
    props, p = mr.props(idx)
    if p is None:
        raise ExtractError('%s: no tagged properties' % where)
    ox, oy, oz, ex, ey, ez, _r = struct.unpack_from('<7f', d, p); p += 28
    body = struct.unpack_from('<i', d, p)[0]; p += 4

    def bulk(expect=None):
        nonlocal p
        stride, count = struct.unpack_from('<2i', d, p)
        if count < 0 or stride < 0 or (expect and count and stride != expect) or p + 8 + stride * count > end:
            raise ExtractError('%s: bad bulk array %d x %d at +%d' % (where, stride, count, p - e['offset']))
        start = p + 8
        p = start + stride * count
        return stride, count, start

    bulk(32)                                   # kDOP nodes
    _, kdop_triangles, _ = bulk(8)
    _version, lods = struct.unpack_from('<2i', d, p); p += 8
    if not 1 <= lods <= 8:
        raise ExtractError('%s: %d LODs' % (where, lods))
    _flags, _count, raw_size, _offset = struct.unpack_from('<4i', d, p); p += 16 + max(raw_size, 0)
    element_count = struct.unpack_from('<i', d, p)[0]; p += 4
    if not 0 < element_count < 64:
        raise ExtractError('%s: %d elements' % (where, element_count))
    elements = []
    for _ in range(element_count):
        material, collide, _old, _shadow, first, triangles, _vmin, _vmax, _mi, fragments = \
            struct.unpack_from('<10i', d, p)
        p += 40 + 8 * fragments
        elements.append({'material': ref_name(pkg, material), 'material_ref': material, 'collide': bool(collide),
                         'first': first, 'triangles': triangles})
    p += 8                                     # PositionVertexBuffer stride, count
    _, position_count, position_start = bulk(12)
    tex_coords, vertex_stride, _vn, full_uvs = struct.unpack_from('<4i', d, p); p += 16
    expected_stride = 12 + tex_coords * (8 if full_uvs else 4)
    stride, vertex_count_buffer, vertex_start = bulk()
    if stride != vertex_stride or stride != expected_stride:
        raise ExtractError('%s: vertex stride %d, expected %d' % (where, stride, expected_stride))
    p += 8
    bulk()                                     # shadow extrusion
    vertex_count = struct.unpack_from('<i', d, p)[0]; p += 4
    _, index_count, index_start = bulk(2)
    if vertex_count <= 0 or vertex_count > position_count or vertex_count > vertex_count_buffer:
        raise ExtractError('%s: %d vertices, %d positions' % (where, vertex_count, position_count))
    indices = struct.unpack_from('<%dH' % index_count, d, index_start)
    if index_count % 3 or (indices and max(indices) >= vertex_count):
        raise ExtractError('%s: index buffer out of range' % where)
    if sum(el['triangles'] for el in elements) != index_count // 3:
        raise ExtractError('%s: element triangles do not sum to the index buffer' % where)

    slack = max(1.0, 0.01 * max(ex, ey, ez))
    uv_format = '<2f' if full_uvs else '<2e'
    uv_size = 8 if full_uvs else 4
    # EVERY channel the buffer carries, not the first two: a material names
    # the one it samples by index (MaterialExpressionTextureCoordinate), and
    # the truck's M_Outside names 2. Cut to two, the builder fell back to the
    # last one it had -- the lightmap's atlas UVs -- and drew the doors
    # stretched and offset. The Godot mesh still carries ONE set per surface,
    # whichever the material asked for (mesh_library._uv_set).
    uvs = [[] for _ in range(tex_coords)]
    vertices, normals = [], []
    zero_normals = False
    for k in range(vertex_count):
        x, y, z = struct.unpack_from('<3f', d, position_start + k * 12)
        if abs(x - ox) > ex + slack or abs(y - oy) > ey + slack or abs(z - oz) > ez + slack:
            raise ExtractError('%s: vertex %d outside bounds' % (where, k))
        vertices.extend(to_godot(x, y, z))
        for channel, out in enumerate(uvs):
            out.extend(struct.unpack_from(uv_format, d, vertex_start + k * stride + 12 + channel * uv_size))
        packed = d[vertex_start + k * stride + 4:vertex_start + k * stride + 7]
        if all(b in ZERO_NORMAL_BYTES for b in packed):
            zero_normals = True
            normals.extend((0.0, 0.0, 0.0))
            continue
        n = [b / 127.5 - 1.0 for b in packed]
        length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        if abs(length - 1.0) > 0.03:
            raise ExtractError('%s: normal %d has length %.3f' % (where, k, length))
        normals.extend((n[0] / length, n[2] / length, n[1] / length))

    surfaces = []
    for el in elements:
        tri = indices[el['first']:el['first'] + el['triangles'] * 3]
        # The axis map flips handedness, so every triangle's winding flips too.
        flipped = []
        for t in range(0, len(tri), 3):
            flipped.extend((tri[t], tri[t + 2], tri[t + 1]))
        surfaces.append({'material': el['material'], 'material_ref': el['material_ref'],
                         'collide': el['collide'], 'indices': _b64('H', flipped)})
    return {
        'vertices': _b64('f', vertices),
        'normals': None if zero_normals else _b64('f', normals),
        # Texture coordinates by set: 0 for textures, 1 is usually the lightmap
        # set, which some facade materials also sample.
        'uvs': [_b64('f', channel) for channel in uvs],
        'vertex_count': vertex_count,
        'triangle_count': index_count // 3,
        'kdop_triangles': kdop_triangles,
        'collide_triangles': sum(el['triangles'] for el in elements if el['collide']),
        'bounds': {'origin': list(to_godot(ox, oy, oz)), 'extent': [ex / UU, ez / UU, ey / UU]},
        'surfaces': surfaces,
        'body_setup': body,
        'use_simple_box_collision': (props or {}).get('UseSimpleBoxCollision', True),
    }


def simple_collision(mr, body_idx):
    """Convex hulls and BoxElems of an RB_BodySetup, in Godot space, plus its
    physical material name."""
    if body_idx <= 0:
        return [], None
    reader = HullReader.__new__(HullReader)
    reader.mr, reader.pkg, reader.d = mr, mr.pkg, mr.d
    shapes = [{'vertices': [[round(c, 4) for c in to_godot(*v)] for v in h['verts']],
               'triangles': h['tris']} for h in reader.hulls_for(body_idx)]
    tags, _ = reader._calibrated(body_idx)
    shapes += _boxes(reader, tags)
    material = None
    pm = next((t for t in tags if t[0] == 'PhysMaterial'), None)
    if pm is not None:
        material = ref_name(mr.pkg, struct.unpack_from('<i', mr.d, pm[3])[0])
    return shapes, material


def _boxes(reader, tags):
    agg = next((t for t in tags if t[0] == 'AggGeom'), None)
    if agg is None:
        return []
    box = next((t for t in reader._tags(agg[3], agg[3] + agg[4]) if t[0] == 'BoxElems'), None)
    if box is None:
        return []
    d = reader.d
    q, end = box[3] + 4, box[3] + box[4]
    count = struct.unpack_from('<i', d, box[3])[0]
    result = []
    for _ in range(count):
        ok, props, q = reader.mr._chain(q, end)
        if not ok:
            raise ExtractError('unterminated BoxElem')
        props = {t[0]: t for t in props}
        tm = props['TM']
        raw = struct.unpack_from('<16f', d, tm[3])
        # This package version serializes each matrix plane as W, X, Y, Z.
        if not all(abs(raw[i * 4] - (1 if i == 3 else 0)) < 1e-5 for i in range(4)):
            raise ExtractError('BoxElem TM is not affine')
        rows = [raw[i * 4 + 1:i * 4 + 4] for i in range(4)]
        size = [struct.unpack_from('<f', d, props[k][3])[0] for k in ('X', 'Y', 'Z')]
        corners = []
        for corner in range(8):
            local = [size[i] * (0.5 if corner & (1 << i) else -0.5) for i in range(3)]
            world = [rows[3][j] + sum(local[i] * rows[i][j] for i in range(3)) for j in range(3)]
            corners.append([round(c, 4) for c in to_godot(*world)])
        result.append({'vertices': corners, 'triangles': BOX_TRIANGLES})
    if q != end:
        raise ExtractError('BoxElems left %d bytes unread' % (end - q))
    return result


def ref_name(pkg, idx):
    return pkg.resolve(idx) if idx else None


def pkg_name(mr):
    return getattr(mr, 'label', '?')

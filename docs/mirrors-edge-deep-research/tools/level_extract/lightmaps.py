"""The original's baked lighting: Beast lightmaps of placed static meshes and
of the world BSP, package version 536.

A placed StaticMeshComponent ends, after its tagged properties, in its LODData:
per LOD the shadow maps, the shadow vertex buffers and one FLightMapRef. A
ModelComponent ends in its elements, each with its own FLightMapRef, the
material it draws and the BSP nodes it owns. An FLightMapRef is one of

  0  none
  1  FLightMap1D, a vertex lightmap: three FColor samples per vertex of the
     mesh's LOD, decoded pow(rgb, 2.2) * ScaleVector
  2  FLightMap2D, a texture lightmap: three LightMapTexture2D (one per
     coefficient of the directional basis) sampled at
     uv[LightMapCoordinateIndex] * CoordinateScale + CoordinateBias, sRGB
     decoded, times ScaleVector

[ME:CONFIRMED Engine/Shaders/BasePassVertexShader.usf, BasePassPixelShader.usf,
LocalVertexFactory.usf] for both decodes. The 4th texture and scale of each are
the cooked-out simple lightmap: a 1x1 white placeholder, never drawn.

Nothing here decodes a texel: the atlases are written as DDS with their own
DXT1 blocks and mips, so the game shows exactly what Beast stored.
"""
import base64
import os
import struct

from common import ExtractError

NONE, VERTEX, TEXTURE = 0, 1, 2
# Coefficients of the directional basis; the 4th entry of each array is the
# cooked-out simple lightmap.
COEFFICIENTS = 3
STORED_COEFFICIENTS = 4
# One FQuantizedDirectionalLightSample: three FColor, B G R A in memory.
VERTEX_SAMPLE_SIZE = 4 * COEFFICIENTS
LIGHTMAP_TEXTURE_CLASS = 'LightMapTexture2D'
# DXT blocks are 4x4 texels, 8 bytes each for DXT1; uncompressed is 4 per texel.
FORMATS = {'PF_DXT1': 'dxt1', 'PF_A8R8G8B8': 'bgra8'}
BULK_STORED_ELSEWHERE = 0x1
BULK_CHUNK_COMPRESSED = 0x10


class Cursor:
    """Little-endian reads that refuse to cross the end of the export."""

    def __init__(self, data, start, end, where):
        self.data, self.p, self.end, self.where = data, start, end, where

    def take(self, fmt):
        size = struct.calcsize(fmt)
        if self.p + size > self.end:
            raise ExtractError('%s: read past the end of the export' % self.where)
        values = struct.unpack_from('<' + fmt, self.data, self.p)
        self.p += size
        return values

    def i32(self):
        return self.take('i')[0]

    def count(self, limit):
        n = self.i32()
        if not 0 <= n <= limit:
            raise ExtractError('%s: array of %d at +%d' % (self.where, n, self.p))
        return n

    def bulk(self):
        """An untyped bulk data header and, when stored here, its payload's offset."""
        flags, count, size, _offset = self.take('4i')
        start = self.p
        if not flags & BULK_STORED_ELSEWHERE:
            if size < 0 or self.p + size > self.end:
                raise ExtractError('%s: bulk data of %d bytes overruns the export' % (self.where, size))
            self.p += size
        return {'flags': flags, 'count': count, 'size': size, 'start': start,
                'inline': not flags & BULK_STORED_ELSEWHERE}


def read_lightmap_ref(cur):
    """One FLightMapRef. Texture references are export indices of the package."""
    kind = cur.i32()
    if kind == NONE:
        return {'kind': NONE}
    if kind not in (VERTEX, TEXTURE):
        raise ExtractError('%s: lightmap type %d' % (cur.where, kind))
    guids = cur.count(4096)
    cur.take('%dB' % (16 * guids))
    if kind == VERTEX:
        cur.i32()                              # Owner
        samples = cur.bulk()
        scales = [list(cur.take('3f')) for _ in range(STORED_COEFFICIENTS)]
        cur.bulk()                             # simple samples, cooked out
        if not samples['inline'] or samples['size'] != samples['count'] * VERTEX_SAMPLE_SIZE:
            raise ExtractError('%s: vertex lightmap of %d samples in %d bytes'
                               % (cur.where, samples['count'], samples['size']))
        return {'kind': VERTEX, 'scales': scales[:COEFFICIENTS], 'samples': samples}
    textures, scales = [], []
    for _ in range(STORED_COEFFICIENTS):
        textures.append(cur.i32())
        scales.append(list(cur.take('3f')))
    uv_scale = list(cur.take('2f'))
    uv_bias = list(cur.take('2f'))
    return {'kind': TEXTURE, 'textures': textures[:COEFFICIENTS], 'scales': scales[:COEFFICIENTS],
            'uv_scale': uv_scale, 'uv_bias': uv_bias}


def parse_component_tail(data, start, end, where):
    """LODData of a StaticMeshComponent: [lightmap ref] per LOD."""
    cur = Cursor(data, start, end, where)
    lods = []
    for _ in range(cur.count(8)):
        cur.take('%di' % cur.count(64))        # ShadowMaps
        cur.take('%di' % cur.count(64))        # ShadowVertexBuffers
        lods.append(read_lightmap_ref(cur))
    if cur.p != end:
        raise ExtractError('%s: %d bytes after the LODData' % (where, end - cur.p))
    return lods


def parse_model_component_tail(data, start, end, where):
    """A ModelComponent's Model, its elements and the BSP nodes each owns."""
    cur = Cursor(data, start, end, where)
    model, _zone = cur.take('2i')
    elements = []
    for _ in range(cur.count(65536)):
        lightmap = read_lightmap_ref(cur)
        _component, material = cur.take('2i')
        nodes = list(cur.take('%dH' % cur.count(1 << 20)))
        cur.take('%di' % cur.count(1024))      # ShadowMaps
        cur.take('%dB' % (16 * cur.count(1024)))   # IrrelevantLights (GUIDs)
        elements.append({'lightmap': lightmap, 'material': material, 'nodes': nodes})
    _index = cur.take('H')
    cur.take('%dH' % cur.count(1 << 20))       # every node of the component
    if cur.p != end:
        raise ExtractError('%s: %d bytes after the elements' % (where, end - cur.p))
    return {'model': model, 'elements': elements}


def _native(mr, idx):
    export = mr.pkg.exports[idx - 1]
    _props, start = mr.props(idx)
    if start is None:
        raise ExtractError('%s.%s: no tagged properties' % (mr.label, export['name']))
    return start, export['offset'] + export['size'], '%s.%s' % (mr.label, export['name'])


def component_lightmap(mr, idx):
    """LOD0's lightmap of a placed StaticMeshComponent, or None when it has no
    LODData (a mover or a rigid body: the original lights those dynamically)."""
    start, end, where = _native(mr, idx)
    lods = parse_component_tail(mr.d, start, end, where)
    return lods[0] if lods else None


def bsp_lightmaps(mr):
    """{(Model export index, node index): lightmap} over every ModelComponent
    placed in this package's level."""
    pkg = mr.pkg
    out = {}
    for idx, export in enumerate(pkg.exports, 1):
        if pkg.class_of(export) != 'ModelComponent' or not _in_level(pkg, export):
            continue
        start, end, where = _native(mr, idx)
        component = parse_model_component_tail(mr.d, start, end, where)
        for element in component['elements']:
            for node in element['nodes']:
                key = (component['model'], node)
                if key in out:
                    raise ExtractError('%s: BSP node %d is in two elements' % (where, node))
                out[key] = element['lightmap']
    return out


def _in_level(pkg, export):
    """A ModelComponent's outer is the Level itself; one under anything else
    is an archetype's."""
    outer = export['outer_idx']
    return outer > 0 and pkg.class_of(pkg.exports[outer - 1]) == 'Level'


class Atlases:
    """The LightMapTexture2D exports placements and BSP name, written once each
    as DDS into `out_dir`, keyed '<package stem>.<export name>'."""

    def __init__(self, out_dir, report):
        self.out_dir = out_dir
        self.written = {}
        self.stats = report.setdefault('lightmaps', {})
        os.makedirs(out_dir, exist_ok=True)
        for stale in os.listdir(out_dir):
            if stale.endswith('.dds'):
                os.remove(os.path.join(out_dir, stale))

    def key(self, mr, idx):
        return '%s.%s' % (mr.label.rsplit('.', 1)[0], mr.pkg.exports[idx - 1]['name'])

    def texture(self, mr, idx):
        if not 0 < idx <= len(mr.pkg.exports) or mr.pkg.class_of(mr.pkg.exports[idx - 1]) != LIGHTMAP_TEXTURE_CLASS:
            raise ExtractError('%s: lightmap texture %d is not a %s' % (mr.label, idx, LIGHTMAP_TEXTURE_CLASS))
        key = self.key(mr, idx)
        if key not in self.written:
            fmt, width, height, mips = texture_mips(mr, idx)
            with open(os.path.join(self.out_dir, key + '.dds'), 'wb') as fh:
                fh.write(dds(fmt, width, height, mips))
            self.written[key] = (width, height)
            self.stats['atlas_bytes'] = self.stats.get('atlas_bytes', 0) + sum(len(m) for m in mips)
        return key

    def entry(self, mr, ref, vertex_count=None):
        """A lightmap ref as the manifest carries it, or None for none."""
        if ref is None or ref['kind'] == NONE:
            self.stats['none'] = self.stats.get('none', 0) + 1
            return None
        if ref['kind'] == TEXTURE:
            self.stats['texture'] = self.stats.get('texture', 0) + 1
            return {'kind': 'texture', 'textures': [self.texture(mr, t) for t in ref['textures']],
                    'scales': [[round(c, 6) for c in s] for s in ref['scales']],
                    'uv_scale': [round(c, 7) for c in ref['uv_scale']],
                    'uv_bias': [round(c, 7) for c in ref['uv_bias']]}
        samples = ref['samples']
        if vertex_count is not None and samples['count'] != vertex_count:
            raise ExtractError('%s: vertex lightmap of %d samples for %d vertices'
                               % (mr.label, samples['count'], vertex_count))
        self.stats['vertex'] = self.stats.get('vertex', 0) + 1
        return {'kind': 'vertex', 'scales': [[round(c, 6) for c in s] for s in ref['scales']],
                'samples': vertex_samples_rgb(mr.d[samples['start']:samples['start'] + samples['size']])}


def vertex_samples_rgb(raw):
    """Three B G R A FColors per vertex -> base64 of R G B, three per vertex."""
    out = bytearray(len(raw) // 4 * 3)
    for channel, source in enumerate((2, 1, 0)):
        out[channel::3] = raw[source::4]
    return base64.b64encode(bytes(out)).decode('ascii')


def texture_mips(mr, idx):
    """(format, width, height, [mip bytes]) of a LightMapTexture2D, its mips
    from the top down for as long as they are stored in the package.

    The native part starts with the source art's bulk data (empty when cooked),
    then the mip count and each mip as bulk data followed by its size.
    """
    props, start = mr.props(idx)
    export = mr.pkg.exports[idx - 1]
    where = '%s.%s' % (mr.label, export['name'])
    fmt = FORMATS.get(str((props or {}).get('Format')))
    if fmt is None:
        raise ExtractError('%s: lightmap format %s' % (where, (props or {}).get('Format')))
    cur = Cursor(mr.d, start, export['offset'] + export['size'], where)
    cur.bulk()
    mips, width, height = [], None, None
    for level in range(cur.count(16)):
        bulk = cur.bulk()
        w, h = cur.take('2i')
        if level == 0:
            width, height = w, h
            if not bulk['inline'] or bulk['size'] <= 0:
                raise ExtractError('%s: top mip not in the package' % where)
        if not bulk['inline'] or bulk['size'] <= 0 or len(mips) < level:
            continue
        raw = mr.d[bulk['start']:bulk['start'] + bulk['size']]
        if bulk['flags'] & BULK_CHUNK_COMPRESSED:
            from materials import unchunk
            raw = unchunk(raw)
        # A DXT mip never records less than one block: the 2x2 and 1x1 levels
        # of a 1024 say 4x4, in the one block those sizes take.
        expected = (max(1, width >> level), max(1, height >> level))
        recorded = tuple(max(4, c) for c in expected) if fmt == 'dxt1' else expected
        if len(raw) != mip_size(fmt, *expected) or (w, h) not in (expected, recorded):
            raise ExtractError('%s: mip %d is %dx%d in %d bytes' % (where, level, w, h, len(raw)))
        mips.append(raw)
    return fmt, width, height, mips


def mip_size(fmt, w, h):
    if fmt == 'dxt1':
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
    return w * h * 4


DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PIXELFORMAT = 0x1, 0x2, 0x4, 0x1000
DDSD_MIPMAPCOUNT, DDSD_LINEARSIZE, DDSD_PITCH = 0x20000, 0x80000, 0x8
DDPF_FOURCC, DDPF_RGB, DDPF_ALPHAPIXELS = 0x4, 0x40, 0x1
DDSCAPS_TEXTURE, DDSCAPS_MIPMAP, DDSCAPS_COMPLEX = 0x1000, 0x400000, 0x8


def dds(fmt, width, height, mips):
    """A DDS file around mips exactly as stored."""
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_MIPMAPCOUNT
    if fmt == 'dxt1':
        flags |= DDSD_LINEARSIZE
        pitch = mip_size(fmt, width, height)
        pixel_format = struct.pack('<2I4s5I', 32, DDPF_FOURCC, b'DXT1', 0, 0, 0, 0, 0)
    else:
        flags |= DDSD_PITCH
        pitch = width * 4
        pixel_format = struct.pack('<2I4s5I', 32, DDPF_RGB | DDPF_ALPHAPIXELS, b'\0\0\0\0', 32,
                                   0x00ff0000, 0x0000ff00, 0x000000ff, 0xff000000)
    caps = DDSCAPS_TEXTURE | (DDSCAPS_MIPMAP | DDSCAPS_COMPLEX if len(mips) > 1 else 0)
    header = struct.pack('<7I', 124, flags, height, width, pitch, 0, len(mips)) + b'\0' * 44 \
        + pixel_format + struct.pack('<5I', caps, 0, 0, 0, 0)
    return b'DDS ' + header + b''.join(mips)

"""Regression checks for the baked lighting extract.

    uv run --no-project --python 3.12 --with numpy --with lzallright \\
        -m unittest test_lightmaps      (from this directory)

The parser tests build their bytes by hand and need no game assets. The atlas
and coordinate tests read the tutorial's extract when it exists and skip
otherwise: they check the data against itself, which is the only witness of
whether the layout was read right.
"""
import base64
import json
import math
import os
import struct
import unittest

import lightmaps as L
import static_mesh
from common import ExtractError

EXTRACT = os.path.join(os.path.dirname(os.path.abspath(__file__)), *[os.pardir] * 4,
                       '_local', 'me-reference', 'level-extract', 'sp00_tutorial')


def bulk(payload, count, flags=0):
    return struct.pack('<4i', flags, count, len(payload), 0) + payload


def texture_ref(textures=(11, 12, 13, 14), uv_scale=(0.25, 0.5), uv_bias=(0.125, 0.75)):
    out = struct.pack('<ii', L.TEXTURE, 1) + b'\x07' * 16
    for k, t in enumerate(textures):
        out += struct.pack('<i3f', t, 1.0 + k, 2.0 + k, 3.0 + k)
    return out + struct.pack('<4f', *uv_scale, *uv_bias)


def vertex_ref(vertices):
    samples = bytes(range(vertices * L.VERTEX_SAMPLE_SIZE))
    out = struct.pack('<ii', L.VERTEX, 0) + struct.pack('<i', 5) + bulk(samples, vertices)
    out += b''.join(struct.pack('<3f', k, k, k) for k in range(4))
    return out + bulk(b'\0' * 4 * vertices, vertices)


def lod(ref, shadow_maps=(), shadow_buffers=()):
    return (struct.pack('<i', len(shadow_maps)) + b''.join(struct.pack('<i', s) for s in shadow_maps)
            + struct.pack('<i', len(shadow_buffers)) + b''.join(struct.pack('<i', s) for s in shadow_buffers) + ref)


class LightMapRefTests(unittest.TestCase):
    def parse(self, data):
        return L.parse_component_tail(data, 0, len(data), 'test')

    def test_a_texture_lightmap_reads_to_the_end_of_the_export(self):
        lods = self.parse(struct.pack('<i', 1) + lod(texture_ref()))
        ref = lods[0]
        self.assertEqual(ref['kind'], L.TEXTURE)
        # The 4th texture is the cooked-out simple lightmap: never carried.
        self.assertEqual(ref['textures'], [11, 12, 13])
        self.assertEqual(ref['scales'], [[1.0, 2.0, 3.0], [2.0, 3.0, 4.0], [3.0, 4.0, 5.0]])
        self.assertEqual((ref['uv_scale'], ref['uv_bias']), ([0.25, 0.5], [0.125, 0.75]))

    def test_a_vertex_lightmap_carries_three_samples_a_vertex(self):
        ref = self.parse(struct.pack('<i', 1) + lod(vertex_ref(5)))[0]
        self.assertEqual(ref['kind'], L.VERTEX)
        self.assertEqual(ref['samples']['count'], 5)
        self.assertEqual(len(ref['scales']), 3)

    def test_no_lightmap_and_no_lod_are_both_read(self):
        self.assertEqual(self.parse(struct.pack('<i', 1) + lod(struct.pack('<i', L.NONE)))[0]['kind'], L.NONE)
        self.assertEqual(self.parse(struct.pack('<i', 0)), [])

    def test_shadow_maps_before_the_lightmap_are_skipped(self):
        ref = self.parse(struct.pack('<i', 1) + lod(texture_ref(), (3, 4), (9,)))[0]
        self.assertEqual(ref['textures'], [11, 12, 13])

    def test_bytes_left_over_mean_the_layout_was_misread(self):
        data = struct.pack('<i', 1) + lod(texture_ref()) + b'\0\0\0\0'
        with self.assertRaises(ExtractError):
            self.parse(data)

    def test_a_vertex_sample_block_of_the_wrong_size_is_refused(self):
        broken = struct.pack('<ii', L.VERTEX, 0) + struct.pack('<i', 5) + bulk(b'\0' * 13, 1)
        broken += b'\0' * 48 + bulk(b'', 0)
        with self.assertRaises(ExtractError):
            self.parse(struct.pack('<i', 1) + lod(broken))


class ModelComponentTests(unittest.TestCase):
    def element(self, ref, nodes):
        return (ref + struct.pack('<ii', 1, 2) + struct.pack('<i', len(nodes))
                + struct.pack('<%dH' % len(nodes), *nodes) + struct.pack('<i', 0) + struct.pack('<i', 0))

    def test_every_node_maps_to_its_own_elements_lightmap(self):
        data = struct.pack('<iii', 42, 0, 2) + self.element(texture_ref(textures=(1, 2, 3, 4)), [3, 5]) \
            + self.element(struct.pack('<i', L.NONE), [7]) + struct.pack('<H', 0) + struct.pack('<i3H', 3, 3, 5, 7)
        component = L.parse_model_component_tail(data, 0, len(data), 'test')
        self.assertEqual(component['model'], 42)
        self.assertEqual([e['nodes'] for e in component['elements']], [[3, 5], [7]])
        self.assertEqual(component['elements'][0]['lightmap']['textures'], [1, 2, 3])
        self.assertEqual(component['elements'][1]['lightmap']['kind'], L.NONE)


class ConversionTests(unittest.TestCase):
    def test_vertex_samples_come_out_red_green_blue(self):
        raw = bytes([10, 20, 30, 255, 40, 50, 60, 255])  # B G R A, twice
        self.assertEqual(base64.b64decode(L.vertex_samples_rgb(raw)), bytes([30, 20, 10, 60, 50, 40]))

    def test_the_binormal_survives_the_axis_map(self):
        # [ME:CONFIRMED LocalVertexFactory.usf] UE's binormal is cross(Z, X) * w.
        def pack(v, w=0.0):
            return bytes(round((c + 1.0) * 127.5) for c in v) + bytes([255 if w > 0 else 0])
        ux, uz = (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)
        for w in (1.0, -1.0):
            packed = pack(ux)[:3] + b'\x80' + pack(uz, w)
            tx, ty, tz, tw = static_mesh.godot_tangent(packed)
            binormal_ue = [c * w for c in cross(uz, ux)]
            expected = (binormal_ue[0], binormal_ue[2], binormal_ue[1])   # the axis map
            normal = (uz[0], uz[2], uz[1])
            godot = [c * tw for c in cross(normal, (tx, ty, tz))]
            for a, b in zip(godot, expected):
                self.assertAlmostEqual(a, b, places=2)

    def test_a_dds_is_its_header_and_the_mips_unchanged(self):
        mips = [b'\x01' * L.mip_size('dxt1', 8, 4), b'\x02' * L.mip_size('dxt1', 4, 2)]
        out = L.dds('dxt1', 8, 4, mips)
        self.assertEqual(out[:4], b'DDS ')
        size, _flags, height, width, _pitch, _depth, count = struct.unpack_from('<7I', out, 4)
        self.assertEqual((size, height, width, count), (124, 4, 8, 2))
        self.assertEqual(out[84:88], b'DXT1')
        self.assertEqual(out[128:], b''.join(mips))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


@unittest.skipUnless(os.path.exists(os.path.join(EXTRACT, 'manifest.json')), 'no tutorial extract')
class ExtractedTutorialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(EXTRACT, 'manifest.json'), encoding='utf-8') as fh:
            cls.manifest = json.load(fh)
        with open(os.path.join(EXTRACT, 'meshes.json'), encoding='utf-8') as fh:
            cls.meshes = json.load(fh)

    def allocations(self):
        out = {}
        for p in self.manifest['placements']:
            lm = p.get('lightmap')
            if lm and lm['kind'] == 'texture':
                out.setdefault(lm['textures'][0], []).append(lm)
        for f in self.manifest['bsp']:
            lm = f.get('lightmap')
            if lm:
                out.setdefault(lm['textures'][0], []).append(lm)
        return out

    def test_allocations_in_an_atlas_do_not_overlap_read_x_then_y(self):
        # The vertex shader adds ShadowCoordinateScaleBias.wz, which the engine
        # fills so the result is bias (x, y). Read the other way round, the
        # rectangles overlap all over every atlas.
        overlaps = 0
        for allocations in self.allocations().values():
            # Shared allocations (one bake for several placements) are the same
            # rectangle, not an overlap.
            rects = sorted({(a['uv_bias'][0], a['uv_bias'][1], a['uv_bias'][0] + a['uv_scale'][0],
                             a['uv_bias'][1] + a['uv_scale'][1]) for a in allocations})
            for i in range(len(rects)):
                for k in range(i + 1, len(rects)):
                    a, b = rects[i], rects[k]
                    if min(a[2], b[2]) - max(a[0], b[0]) > 1e-4 and min(a[3], b[3]) - max(a[1], b[1]) > 1e-4:
                        overlaps += 1
        self.assertEqual(overlaps, 0)

    def test_the_lightmap_coordinates_of_every_lightmapped_mesh_stay_in_its_rectangle(self):
        # The set LightMapCoordinateIndex names packs the mesh into 0..1, each
        # element in its own patch; the others tile. Pick the wrong one and a
        # placement samples its neighbours' light.
        outside = []
        used = {p['mesh'] for p in self.manifest['placements'] if (p.get('lightmap') or {}).get('kind') == 'texture'}
        for name in used:
            record = self.meshes[name]
            raw = base64.b64decode(record['uvs'][record['lightmap_uv_set']])
            values = struct.unpack('<%df' % (len(raw) // 4), raw)
            if values and (min(values) < -0.01 or max(values) > 1.01):
                outside.append(name)
        self.assertEqual(outside, [])

    def test_every_vertex_lightmap_has_a_sample_per_vertex(self):
        for p in self.manifest['placements']:
            lm = p.get('lightmap')
            if lm and lm['kind'] == 'vertex':
                samples = len(base64.b64decode(lm['samples'])) // 9
                self.assertEqual(samples, self.meshes[p['mesh']]['vertex_count'], p['name'])

    def test_every_atlas_named_was_written(self):
        written = set(os.listdir(os.path.join(EXTRACT, 'lightmaps')))
        for key in self.allocations():
            self.assertIn(key + '.dds', written)

    def test_lightmapped_bsp_faces_carry_a_coordinate_per_vertex(self):
        lit = [f for f in self.manifest['bsp'] if f.get('lightmap')]
        self.assertGreater(len(lit), 0)
        for f in lit:
            self.assertEqual(len(f['lightmap_uvs']), len(f['vertices']))
            self.assertTrue(all(-0.01 <= c <= 1.01 for uv in f['lightmap_uvs'] for c in uv))


if __name__ == '__main__':
    unittest.main()

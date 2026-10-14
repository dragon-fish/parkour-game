"""Regression checks for how the tone mapping settings resolve; no game assets required.

    uv run --no-project --python 3.12 --with numpy --with lzallright \\
        -m unittest test_environment      (from this directory)
"""
import struct
import unittest

import environment as E
from mapdump import MapReader


def block(fields=None, ms=None, bs=None):
    return {'fields': fields or {}, 'ms': ms or {}, 'bs': bs or {}}


class ToneMapTests(unittest.TestCase):
    def test_what_is_not_stored_takes_the_struct_defaults(self):
        t = E.tone_map(block(), block())
        self.assertEqual(t['highlights'], [1.0, 1.0, 1.0])
        self.assertEqual((t['exposure_high'], t['exposure_low']), (1.65, 0.85))
        self.assertEqual((t['exposure_speed_up'], t['exposure_speed_down']), (3.5, 4.5))

    def test_the_modifier_adds_on_and_its_curve_slopes_are_one_less(self):
        # [ME:CONFIRMED TM1 0x00c0f820] out = in + mod; Ms = in + mod - 1.
        t = E.tone_map(block({'Scene_ExposureHigh': 1.5}, ms={0: (0.5, 0.5, 0.5)}, bs={0: (0.1, 0.1, 0.1)}),
                       block({'Scene_ExposureHigh': 0.25}, ms={0: (1.5, 1.0, 1.0)}, bs={0: (0.2, 0.0, 0.0)}))
        self.assertEqual(t['exposure_high'], 1.75)
        self.assertEqual(t['curve_m'][0], [1.0, 0.5, 0.5])
        self.assertAlmostEqual(t['curve_b'][0][0], 0.3)
        # An element the modifier leaves out is its class default, slope 1.
        self.assertEqual(t['curve_m'][1], [0.0, 0.0, 0.0])

    def test_inside_a_volume_a_modifier_field_left_at_zero_takes_the_worlds(self):
        world = block({'Scene_ExposureLow': 0.25})
        own = block({'Scene_ExposureHigh': 0.5})
        t = E.tone_map(block(), own, world, world)
        self.assertEqual(t['exposure_high'], 1.65 + 0.5)
        self.assertEqual(t['exposure_low'], 0.85 + 0.25)

    def test_no_scene_effect_grades_nothing(self):
        t = E.tone_map(block({'bEnableSceneEffect': False, 'Scene_MidTones': (0.9, 0.9, 0.9),
                              'Scene_Desaturation': 0.4}), block())
        self.assertEqual(t['midtones'], [1.0, 1.0, 1.0])
        self.assertEqual(t['desaturation'], 0.0)

    def test_a_hull_is_its_outward_planes(self):
        cube = {'vertices': [[x, y, z] for x in (0, 1) for y in (0, 1) for z in (0, 1)],
                'triangles': [0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5, 0, 4, 5, 0, 5, 1,
                              2, 3, 7, 2, 7, 6, 0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3]}
        planes = E._planes({'basis': [[2, 0, 0], [0, 1, 0], [0, 0, 1]], 'position': [10, 0, 0]}, cube)

        def inside(p):
            return all(n[0] * p[0] + n[1] * p[1] + n[2] * p[2] - n[3] <= 1e-6 for n in planes)
        self.assertTrue(inside((11.0, 0.5, 0.5)))
        self.assertFalse(inside((12.5, 0.5, 0.5)))
        self.assertFalse(inside((10.5, 1.5, 0.5)))


class _Package:
    """The few members MapReader and the volume reader touch, over hand-built bytes."""

    def __init__(self):
        self.names, self.exports, self.d = [], [], bytearray()

    def index(self, name):
        if name not in self.names:
            self.names.append(name)
        return self.names.index(name)

    @property
    def name_count(self):
        return len(self.names)

    def name(self, i):
        return self.names[i]

    def class_of(self, export):
        return export['class']

    def add(self, name, cls, outer, payload):
        self.exports.append({'name': name, 'class': cls, 'outer_idx': outer, 'archetype': 0,
                             'offset': len(self.d), 'size': len(payload)})
        self.d += payload
        return len(self.exports)


def _tag(pkg, name, typ, payload, struct_name=None):
    head = struct.pack('<2i', pkg.index(name), 0) + struct.pack('<2i', pkg.index(typ), 0)
    if typ == 'BoolProperty':
        return head + struct.pack('<2i', 0, 0) + payload
    head += struct.pack('<2i', len(payload), 0)
    if struct_name:
        head += struct.pack('<2i', pkg.index(struct_name), 0)
    return head + payload


def _end(pkg):
    return struct.pack('<2i', pkg.index('None'), 0)


def _volume_package(enabled=True, shape='hull'):
    """A level holding one PostProcessVolume whose Settings struct stores more
    tags than the volume does, and its BrushComponent, whose first ConvexElem
    stores more than the component does: both read as their inner chain when
    the calibration counts tags. `shape` 'none' stores no shape on the
    component, 'brush' a Brush and nothing else."""
    pkg = _Package()
    pkg.index('None')
    level = pkg.add('PersistentLevel', 'Level', 0, b'\0' * 8)
    cube = [(x, y, z) for x in (-50.0, 50.0) for y in (-50.0, 50.0) for z in (-50.0, 50.0)]
    tris = [0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5, 0, 4, 5, 0, 5, 1, 2, 3, 7, 2, 7, 6, 0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3]
    elem = (_tag(pkg, 'VertexData', 'ArrayProperty', struct.pack('<i', 8) + b''.join(struct.pack('<3f', *v) for v in cube))
            + _tag(pkg, 'PermutedVertexData', 'ArrayProperty', struct.pack('<i', 0))
            + _tag(pkg, 'FaceTriData', 'ArrayProperty', struct.pack('<%di' % (len(tris) + 1), len(tris), *tris))
            + _tag(pkg, 'EdgeDirections', 'ArrayProperty', struct.pack('<i', 0))
            + _end(pkg))
    geom = _tag(pkg, 'ConvexElems', 'ArrayProperty', struct.pack('<i', 1) + elem) + _end(pkg)
    stored = {'hull': _tag(pkg, 'BrushAggGeom', 'StructProperty', geom, 'KAggregateGeom'), 'none': b'',
              'brush': _tag(pkg, 'Brush', 'ObjectProperty', struct.pack('<i', level))}[shape]
    component = stored + _tag(pkg, 'CachedPhysBrushDataVersion', 'IntProperty', struct.pack('<i', 1)) + _end(pkg)
    settings = b''.join(_tag(pkg, 'Haze%d' % k, 'FloatProperty', struct.pack('<f', k)) for k in range(12))
    settings += _tag(pkg, 'Scene_ExposureHigh', 'FloatProperty', struct.pack('<f', 1.25)) + _end(pkg)
    comp_idx = len(pkg.exports) + 2
    volume = (_tag(pkg, 'Priority', 'FloatProperty', struct.pack('<f', 2.5))
              + _tag(pkg, 'Settings', 'StructProperty', settings, 'PostProcessSettings')
              + (b'' if enabled else _tag(pkg, 'bEnabled', 'BoolProperty', struct.pack('<i', 0)))
              + _tag(pkg, 'BrushComponent', 'ObjectProperty', struct.pack('<i', comp_idx))
              + _tag(pkg, 'Location', 'StructProperty', struct.pack('<3f', 100.0, 200.0, 300.0), 'Vector')
              + _end(pkg))
    pkg.add('PostProcessVolume_1', 'PostProcessVolume', level, volume)
    pkg.add('BrushComponent_5', 'BrushComponent', comp_idx - 1, component)
    reader = MapReader.__new__(MapReader)
    reader.pkg, reader.d, reader.label = pkg, bytes(pkg.d), 'Test_Lgts.me1'
    return reader


class PostProcessVolumeReadTests(unittest.TestCase):
    def read(self, enabled=True, shape='hull', report=None):
        return E.post_process_volumes(None, _volume_package(enabled, shape), E.settings_block(None, None), report)

    def test_a_volume_is_read_from_its_own_chain_not_its_settings(self):
        volume = self.read()[0]
        self.assertEqual(volume['priority'], 2.5)
        self.assertEqual(volume['tone_map']['exposure_high'], 1.25)
        self.assertEqual([len(hull) for hull in volume['planes']], [12])

    def test_a_disabled_volume_is_carried_disabled(self):
        # [ME:CONFIRMED TM1 0x00c15ee0] the first ENABLED volume holding the
        # view applies; no Kismet in these levels toggles one on.
        self.assertFalse(self.read(enabled=False)[0]['enabled'])

    def test_a_volume_with_no_shape_never_applies_and_is_listed(self):
        report = {}
        self.assertEqual(self.read(shape='none', report=report), [])
        self.assertEqual(report['post_process_volumes_shapeless'], ['Test_Lgts.me1.PostProcessVolume_1'])

    def test_a_brush_that_yields_no_hull_is_a_misread(self):
        with self.assertRaises(E.ExtractError):
            self.read(shape='brush')


if __name__ == '__main__':
    unittest.main()


class CharacterShadowTests(unittest.TestCase):
    """Which lights a pawn's shadow environment takes in, and in what units."""

    def test_a_sun_counts_its_live_brightness_in_linear_colour_not_its_bake(self):
        light = E.character_shadow_light('DirectionalLight', {'Brightness': 2.0, 'LightColor': ('color', 1.0, 0.5, 0.0)}, {})
        self.assertEqual(light['kind'], 'sun')
        self.assertAlmostEqual(light['intensity'][1], 2.0 * 0.5 ** 2.2, places=4)
        self.assertTrue(light['traced'])

    def test_a_light_off_the_composite_dynamic_channel_is_not_seen(self):
        tagged = {'LightingChannels': {'CompositeDynamic': False, 'Dynamic': True}}
        self.assertIsNone(E.character_shadow_light('DirectionalLight', {}, tagged))
        self.assertIsNone(E.character_shadow_light('SkyLight', {}, {'bCastCompositeShadow': False}))
        self.assertIsNone(E.character_shadow_light('PointLight', {}, {}))

    def test_a_sky_light_is_its_two_hemispheres(self):
        light = E.character_shadow_light('SkyLight', {'Brightness': 0.5, 'LowerBrightness': 0.25,
                                                      'LowerColor': ('color', 1.0, 1.0, 1.0)}, {})
        self.assertEqual(light['upper'], [0.5, 0.5, 0.5])
        self.assertEqual(light['lower'], [0.25, 0.25, 0.25])

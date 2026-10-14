"""Regression checks for how the tone mapping settings resolve; no game assets required.

    uv run --no-project --python 3.12 --with numpy --with lzallright \\
        -m unittest test_environment      (from this directory)
"""
import unittest

import environment as E


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


if __name__ == '__main__':
    unittest.main()

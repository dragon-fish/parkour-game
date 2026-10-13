"""Regression checks for the particle emitter extract; no game assets required.

    uv run --no-project --python 3.12 --with numpy --with lzallright \\
        -m unittest test_particles      (from this directory)
"""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import particles as P


class FakePackage:
    """Exports as (name, class, outer index) and nothing else."""

    def __init__(self, exports):
        self.exports = [{'name': n, 'class': c, 'outer_idx': o, 'archetype': 0} for n, c, o in exports]
        self.imports = []

    def class_of(self, export):
        return export['class']


def fake_reader(exports):
    return SimpleNamespace(pkg=FakePackage(exports), label='Fake.me1')


def patched(props_by_index):
    """object_props and resolve answering from a table instead of a package."""
    return (patch.object(P, 'object_props', side_effect=lambda _p, _r, i: props_by_index[i]),
            patch.object(P, 'resolve', side_effect=lambda _p, r, i: (r, i)))


class CurveTests(unittest.TestCase):
    def test_outside_the_keys_the_end_values_hold(self):
        points = [{'in': 0.2, 'out': (1.0,), 'arrive': (0.0,), 'leave': (0.0,), 'mode': None},
                  {'in': 0.8, 'out': (3.0,), 'arrive': (0.0,), 'leave': (0.0,), 'mode': None}]
        self.assertEqual(P._curve_eval(points, 0.0), (1.0,))
        self.assertEqual(P._curve_eval(points, 1.0), (3.0,))
        self.assertAlmostEqual(P._curve_eval(points, 0.5)[0], 2.0)

    def test_the_leaving_points_mode_decides_the_segment(self):
        points = [{'in': 0.0, 'out': (0.0,), 'arrive': (0.0,), 'leave': (0.0,), 'mode': 'CIM_Constant'},
                  {'in': 1.0, 'out': (1.0,), 'arrive': (0.0,), 'leave': (0.0,), 'mode': None}]
        self.assertEqual(P._curve_eval(points, 0.99), (0.0,))

    def test_hermite_tangents_are_slopes_scaled_by_the_segment(self):
        # Flat tangents: the curve eases, half way is half way, a quarter is
        # 5/32 of the rise (h01 at 0.25).
        points = [{'in': 0.0, 'out': (0.0,), 'arrive': (0.0,), 'leave': (0.0,), 'mode': 'CIM_CurveAuto'},
                  {'in': 2.0, 'out': (1.0,), 'arrive': (0.0,), 'leave': (0.0,), 'mode': 'CIM_CurveAuto'}]
        self.assertAlmostEqual(P._curve_eval(points, 1.0)[0], 0.5)
        self.assertAlmostEqual(P._curve_eval(points, 0.5)[0], 5.0 / 32.0)
        # A slope of 1 on both ends over a span of 2 rising by 2 is a line.
        line = [dict(points[0], out=(0.0,), leave=(1.0,)), dict(points[1], out=(2.0,), arrive=(1.0,))]
        self.assertAlmostEqual(P._curve_eval(line, 0.5)[0], 0.5)


class DistributionTests(unittest.TestCase):
    def test_a_mirrored_component_takes_minus_its_max(self):
        reader = fake_reader([('DistributionVectorUniform_0', 'DistributionVectorUniform', 0)])
        flags = P.StaticArray({2: 'EDVMF_Mirror'})
        table = {1: {'Min': (1.0, 2.0, 3.0), 'Max': (10.0, 20.0, 30.0), 'MirrorFlags': flags}}
        a, b = patched(table)
        with a, b:
            dist = P.distribution(None, P.Ref(reader, 1))
        self.assertEqual(dist['kind'], 'uniform')
        self.assertEqual(dist['min'], [1.0, 2.0, -30.0])
        self.assertEqual(dist['max'], [10.0, 20.0, 30.0])

    def test_locked_axes_stand_for_x_whatever_blockaxes_says(self):
        reader = fake_reader([('DistributionVectorConstantCurve_0', 'DistributionVectorConstantCurve', 0)])
        curve = {'Points': [{'InVal': 0.0, 'OutVal': (0.15, 0.0, 0.0)}, {'InVal': 1.0, 'OutVal': (2.0, 0.0, 0.0)}]}
        a, b = patched({1: {'ConstantCurve': curve, 'LockedAxes': 'EDVLF_XYZ', 'bLockAxes': False}})
        with a, b:
            dist = P.distribution(None, P.Ref(reader, 1))
        self.assertEqual(dist['samples'][0], [0.15, 0.15, 0.15])
        self.assertEqual(dist['samples'][-1], [2.0, 2.0, 2.0])
        self.assertEqual(len(dist['samples']), P.CURVE_SAMPLES)

    def test_a_static_array_element_written_alone_is_its_own_index(self):
        # MirrorFlags[0] reads like any value until [1] shows it is an array.
        elements = P.StaticArray({0: 'EDVMF_Same', 2: 'EDVMF_Mirror'})
        self.assertEqual(elements.as_list('EDVMF_Different'), ['EDVMF_Same', 'EDVMF_Different', 'EDVMF_Mirror'])


class UnitTests(unittest.TestCase):
    def uniform(self, low, high, cls='DistributionVectorUniform'):
        return {'class': cls, 'kind': 'uniform', 'min': low, 'max': high}

    def test_a_velocity_box_takes_the_levels_axis_map_and_metres(self):
        # UE (x, y, z) uu -> Godot (x, z, y) m: the map with determinant -1.
        dist = P.convert('Velocity', 'StartVelocity', self.uniform([-10.0, -2.0, 15.0], [-5.0, 2.0, 25.0]))
        self.assertEqual(dist['min'], [-0.1, 0.15, -0.02])
        self.assertEqual(dist['max'], [-0.05, 0.25, 0.02])

    def test_an_acceleration_curve_is_converted_sample_by_sample(self):
        dist = {'class': 'DistributionVectorConstantCurve', 'kind': 'curve',
                'points': [{'in': 0.0, 'out': [-20.0, 0.0, 75.0], 'mode': None}],
                'samples': [[-20.0, 0.0, 75.0], [100.0, 0.0, 0.0]]}
        out = P.convert('AccelerationOverLifetime', 'AccelOverLife', dist)
        self.assertEqual(out['samples'], [[-0.2, 0.75, 0.0], [1.0, 0.0, 0.0]])
        self.assertEqual(out['points'][0]['out'], [-0.2, 0.75, 0.0])

    def test_a_sprite_size_is_metres_on_its_own_axes(self):
        dist = P.convert('Size', 'StartSize', self.uniform([75.0, 50.0, 25.0], [100.0, 100.0, 100.0]))
        self.assertEqual(dist['min'], [0.75, 0.5, 0.25])

    def test_a_colour_is_left_alone(self):
        dist = {'class': 'DistributionVectorConstant', 'kind': 'constant', 'value': [1.357, 1.357, 1.357]}
        self.assertEqual(P.convert('ColorOverLife', 'ColorOverLife', dist), dist)


class MaterialTests(unittest.TestCase):
    def test_the_smoke_graph_reads_as_two_products_under_a_depth_fade(self):
        # M_FX_LevelFX_Smoke_CheapSmoke_01's graph, node for node.
        reader = fake_reader([
            ('Multiply_0', 'MaterialExpressionMultiply', 0),                   # 1 emissive
            ('VertexColor_0', 'MaterialExpressionVertexColor', 0),             # 2
            ('ParticleSubUV_0', 'MaterialExpressionParticleSubUV', 0),         # 3
            ('ConstantClamp_0', 'MaterialExpressionConstantClamp', 0),         # 4 opacity
            ('DepthBiasedAlpha_0', 'MaterialExpressionDepthBiasedAlpha', 0),   # 5
            ('Multiply_1', 'MaterialExpressionMultiply', 0),                   # 6
            ('Constant_0', 'MaterialExpressionConstant', 0),                   # 7
            ('T_Smoke', 'Texture2D', 0),                                       # 8
        ])
        link = lambda i, *channels: {'Expression': P.Ref(reader, i), **{'Mask' + c: True for c in channels}}
        table = {
            1: {'A': link(2, 'R', 'G', 'B'), 'B': link(3, 'G')},
            2: {}, 3: {'Texture': P.Ref(reader, 8)},
            4: {'Input': link(5), 'Max': 15.0},
            5: {'Alpha': link(6), 'Bias': link(7), 'BiasScale': 400.0},
            6: {'A': link(3, 'A'), 'B': link(2, 'A')},
            7: {'R': 0.5},
        }
        textures = []
        with patch.object(P, 'object_props', side_effect=lambda _p, _r, i: table[i]):
            emissive = P._term(None, reader, 1, None, textures)
            opacity = P._term(None, reader, 4, None, textures)
        self.assertEqual(emissive['factors'], [
            {'kind': 'particle_color', 'channels': 'RGB'},
            {'kind': 'texture', 'texture': 'T_Smoke', 'channels': 'G', 'sub_uv': True}])
        self.assertEqual(opacity['factors'], [
            {'kind': 'texture', 'texture': 'T_Smoke', 'channels': 'A', 'sub_uv': True},
            {'kind': 'particle_color', 'channels': 'A'}])
        self.assertEqual(opacity['depth_fade'], {'bias': 0.5, 'bias_scale': 400.0})
        self.assertEqual(opacity['clamp'], [0.0, 15.0])

    def test_a_node_it_cannot_read_refuses_the_whole_term(self):
        reader = fake_reader([('Fresnel_0', 'MaterialExpressionFresnel', 0)])
        with patch.object(P, 'object_props', side_effect=lambda _p, _r, i: {}):
            self.assertIsNone(P._term(None, reader, 1, None, []))


class EmitterTests(unittest.TestCase):
    def collect(self, groups):
        exports = [('PersistentLevel', 'Level', 0)]
        table = {}
        for k, group in enumerate(groups):
            actor = 2 + 2 * k
            exports += [('Emitter_%d' % k, 'Emitter', 1), ('ParticleSystemComponent_%d' % k, 'ParticleSystemComponent', 0)]
            table[actor] = {'Location': (100.0, 200.0, 300.0), 'Rotation': (0, 16384, 0), 'Group': group}
            table[actor + 1] = {'Template': 'stand-in'}
        reader = fake_reader(exports)
        for k in range(len(groups)):
            table[2 + 2 * k]['ParticleSystemComponent'] = P.Ref(reader, 3 + 2 * k)
            table[3 + 2 * k]['Template'] = P.Ref(reader, 99)
        templates = SimpleNamespace(get=lambda ref: 'PS_FX_LevelFX_Smoke_VentSmoke_01_Big')
        report = {'counts': {}}
        a, b = patched(table)
        with a, b:
            out = P.collect_emitters(None, reader, templates, report)
        return out, report

    def test_an_emitter_is_placed_in_godot_space(self):
        out, report = self.collect([None])
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]['position'], [1.0, 3.0, 2.0])
        self.assertEqual(out[0]['template'], 'PS_FX_LevelFX_Smoke_VentSmoke_01_Big')
        self.assertTrue(out[0]['auto_activate'], 'bAutoActivate defaults to true')
        # A quarter turn of yaw in UE turns Godot's +X onto +Z.
        self.assertAlmostEqual(out[0]['basis'][0][2], 1.0, places=5)
        self.assertEqual(report['counts']['emitters'], 1)

    def test_the_physx_only_group_is_left_out(self):
        out, report = self.collect([P.PHYSX_ONLY_GROUP, None])
        self.assertEqual(len(out), 1)
        self.assertEqual(report['counts']['emitters_physx_only'], 1)


if __name__ == '__main__':
    unittest.main()

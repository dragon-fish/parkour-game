"""Regression checks for reading a material that covers nothing; no game assets
required. The expression graph is a stand-in for a package's exports."""
import unittest
from unittest import mock

import materials


class FakePackage:
    def __init__(self, nodes):
        self.exports = [{'name': 'n%d' % i, 'class': nodes[i][0]} for i in sorted(nodes)]

    @staticmethod
    def class_of(export):
        return export['class']


class FakeReader:
    """Export i is nodes[i]: (class, props, {input: expression index})."""

    def __init__(self, nodes):
        self.nodes = nodes
        self.pkg = FakePackage(nodes)

    def props(self, idx):
        return self.nodes[idx][1], None


def graph(root_props, opacity, *nodes):
    """A root Material (export 1) whose coverage input is export `opacity`."""
    table = {1: ('Material', root_props, {'Opacity': opacity, 'OpacityMask': opacity})}
    for i, node in enumerate(nodes, 2):
        table[i] = node
    return FakeReader(table)


def _inputs(self, idx):
    return {name: {'expr': expr, 'mask': None} for name, expr in self.mr.nodes[idx][2].items()}


def _props(self, idx):
    return self.mr.nodes[idx][1]


TRANSLUCENT = {'BlendMode': 'BLEND_Translucent', 'LightingModel': 'MLM_Unlit'}
MASKED = {'BlendMode': 'BLEND_Masked'}


@mock.patch.object(materials.Evaluator, 'props', _props)
@mock.patch.object(materials.Evaluator, 'inputs', _inputs)
class DrawsNothingTests(unittest.TestCase):
    def setUp(self):
        self.baker = materials.MaterialBaker.__new__(materials.MaterialBaker)

    def draws_nothing(self, reader):
        return self.baker.draws_nothing(reader, 1)

    def test_a_translucent_material_with_a_zero_constant_opacity_covers_nothing(self):
        # [ME:CONFIRMED] BlankBsp: a Constant left at 0, nothing else connected.
        self.assertTrue(self.draws_nothing(graph(TRANSLUCENT, 2, ('MaterialExpressionConstant', {}, {}))))

    def test_a_translucent_material_with_any_opacity_covers_something(self):
        self.assertFalse(self.draws_nothing(
            graph(TRANSLUCENT, 2, ('MaterialExpressionConstant', {'R': 0.05}, {}))))

    def test_an_unconnected_opacity_is_one(self):
        self.assertFalse(self.draws_nothing(graph(TRANSLUCENT, 0)))

    def test_arithmetic_on_constants_is_still_a_constant(self):
        self.assertTrue(self.draws_nothing(graph(
            TRANSLUCENT, 2,
            ('MaterialExpressionMultiply', {}, {'A': 3, 'B': 4}),
            ('MaterialExpressionConstant', {'R': 0.8}, {}),
            ('MaterialExpressionScalarParameter', {'ParameterName': 'Fade', 'DefaultValue': 0.0}, {}))))

    def test_what_varies_per_pixel_is_never_read_as_covering_nothing(self):
        # Each of these evaluates to some placeholder here and to a real value
        # in the game: a smoke card's vertex alpha, a soft edge's depth.
        for varying in ('MaterialExpressionVertexColor', 'MaterialExpressionTextureSample',
                        'MaterialExpressionDepthBiasedAlpha', 'MaterialExpressionFresnel',
                        'MaterialExpressionTime', 'MaterialExpressionStaticSwitchParameter'):
            reader = graph(TRANSLUCENT, 2,
                           ('MaterialExpressionMultiply', {}, {'A': 3, 'B': 4}),
                           ('MaterialExpressionConstant', {}, {}),
                           (varying, {}, {}))
            self.assertFalse(self.draws_nothing(reader), varying)

    def test_a_masked_material_clips_at_its_own_value(self):
        under = graph(MASKED, 2, ('MaterialExpressionConstant', {'R': 0.2}, {}))
        self.assertTrue(self.draws_nothing(under), 'under the default clip of a third')
        clipped_lower = graph(dict(MASKED, OpacityMaskClipValue=0.1), 2,
                              ('MaterialExpressionConstant', {'R': 0.2}, {}))
        self.assertFalse(self.draws_nothing(clipped_lower))

    def test_an_opaque_or_additive_material_is_not_judged_by_its_opacity(self):
        for blend in ('BLEND_Opaque', 'BLEND_Additive', 'BLEND_Modulate'):
            reader = graph({'BlendMode': blend}, 2, ('MaterialExpressionConstant', {}, {}))
            self.assertFalse(self.draws_nothing(reader), blend)


if __name__ == '__main__':
    unittest.main()

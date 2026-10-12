"""Regression checks for cooked ladder data; no game assets required."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import annotations


class LadderLineTests(unittest.TestCase):
    def repair(self, start, end, spline):
        steps = [(100.0, 200.0, z) for z in (0.0, 100.0, 200.0)]
        record = {'name': 'Ladder', 'start': annotations.point(start), 'end': annotations.point(end)}
        report = {}
        arrays = {'PawnLadderLocations': steps, 'SplineLocations': spline}
        with patch.object(annotations, 'vector_array', side_effect=lambda _, __, key: arrays[key]):
            annotations._ladder_from_steps(SimpleNamespace(label='test'), 1,
                                           {'Start': start, 'End': end}, record, report)
        return record, report

    def test_collapsed_cooked_line_uses_distinct_step_locations(self):
        point = (100.0, 200.0, 100.0)
        record, report = self.repair(point, point, [point] * 11)
        self.assertEqual(record['start'], [1.0, 0.0, 2.0])
        self.assertEqual(record['end'], [1.0, 2.0, 2.0])
        self.assertEqual(len(record['spline']), 3)
        self.assertEqual(report['ladders_from_steps'], ['test.Ladder'])

    def test_sound_cooked_line_is_preserved(self):
        start, end = (100.0, 200.0, 0.0), (100.0, 200.0, 200.0)
        record, report = self.repair(start, end, [start, end])
        self.assertEqual(record['start'], annotations.point(start))
        self.assertEqual(record['end'], annotations.point(end))
        self.assertEqual(report, {})


class UnbuiltBrushTests(unittest.TestCase):
    def hull(self, *spans):
        lo = [0.0, 0.0, 0.0]
        return {'vertices': [lo, [spans[0], 0.0, 0.0], [0.0, spans[1], 0.0], [0.0, 0.0, spans[2]]]}

    def test_a_room_sized_brush_is_built(self):
        self.assertTrue(annotations.built(self.hull(12.0, 4.0, 30.0)))

    def test_a_flat_brush_reaching_the_world_edge_is_not(self):
        self.assertFalse(annotations.built(self.hull(5242.9, 5242.9, 0.0)))

    def test_one_world_sized_axis_is_enough(self):
        self.assertFalse(annotations.built(self.hull(1.3, 0.9, 5242.9)))


class FallHeightTests(unittest.TestCase):
    # A 2 x 2 x 2 m brush, local and unscaled, as BrushAggGeom gives it.
    HULL = [{'vertices': [[x, y, z] for x in (-1.0, 1.0) for y in (-1.0, 1.0) for z in (-1.0, 1.0)]}]

    def volume(self, props):
        location = props['Location']
        annotation = {'position': annotations.point(location),
                      'basis': annotations.godot_basis(props.get('Rotation') or (0, 0, 0), (1.0, 1.0, 1.0)),
                      'hull': self.HULL}
        annotations.fall_height(props, annotation, 'test.TdFallHeightVolume_0')
        return annotation

    def test_center_and_offset_are_carried_in_metres(self):
        a = self.volume({'Location': (100.0, 200.0, 300.0), 'Center': (100.0, 200.0, 300.0),
                         'FallHeightOffset': 150.0})
        self.assertEqual(a['center'], [1.0, 3.0, 2.0])
        self.assertAlmostEqual(a['fall_height_offset'], 1.5)
        self.assertNotIn('starts_off', a)

    def test_an_unset_offset_is_zero(self):
        a = self.volume({'Location': (0.0, 0.0, 0.0), 'Center': (0.0, 0.0, 0.0)})
        self.assertEqual(a['fall_height_offset'], 0.0)

    def test_pre_pivot_moves_the_brush_off_the_location(self):
        # UE3: Location + R*(S*v - PrePivot). Unrotated, the brush's origin is
        # Location - PrePivot, and the cooked Center lies there.
        a = self.volume({'Location': (1000.0, 0.0, 0.0), 'PrePivot': (1000.0, 0.0, 0.0),
                         'Center': (0.0, 0.0, 0.0)})
        self.assertEqual(a['position'], [0.0, 0.0, 0.0])

    def test_a_center_outside_the_placed_brush_stops_the_extraction(self):
        with self.assertRaises(annotations.ExtractError):
            self.volume({'Location': (1000.0, 0.0, 0.0), 'Center': (0.0, 0.0, 0.0)})

    def test_a_volume_without_collision_starts_off(self):
        a = self.volume({'Location': (0.0, 0.0, 0.0), 'Center': (0.0, 0.0, 0.0), 'bCollideActors': False})
        self.assertTrue(a['starts_off'])


if __name__ == '__main__':
    unittest.main()

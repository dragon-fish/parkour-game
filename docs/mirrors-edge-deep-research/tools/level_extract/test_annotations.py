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


if __name__ == '__main__':
    unittest.main()

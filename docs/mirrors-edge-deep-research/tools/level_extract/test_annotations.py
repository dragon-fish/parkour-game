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


if __name__ == '__main__':
    unittest.main()

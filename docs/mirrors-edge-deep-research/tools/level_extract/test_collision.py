"""Regression checks for a placement's collision class; no game assets required."""
import unittest

import extract


def record(hulls, use_simple_box_collision=True, triangles=12):
    return {'simple_shapes': [{'vertices': []}] if hulls else [],
            'use_simple_box_collision': use_simple_box_collision, 'collide_triangles': triangles}


class CollisionClassTests(unittest.TestCase):
    def test_a_hull_less_mesh_blocks_nothing(self):
        # [ME:CONFIRMED decompile 0x00dbaef0] no BodySetup, no hit for a box.
        self.assertEqual(extract.collision_class({}, {}, record(False)), 'none')

    def test_a_mesh_with_hulls_collides_by_them(self):
        self.assertEqual(extract.collision_class({}, {}, record(True)), 'simple')

    def test_only_a_mesh_that_clears_the_flag_collides_by_its_triangles(self):
        self.assertEqual(extract.collision_class({}, {}, record(False, False)), 'per_poly')
        self.assertEqual(extract.collision_class({}, {}, record(True, False)), 'per_poly')
        self.assertEqual(extract.collision_class({}, {}, record(False, False, 0)), 'none')

    def test_switched_off_is_none_until_switched_on(self):
        off = {'BlockActors': False}
        self.assertEqual(extract.collision_class({}, off, record(True)), 'none')
        self.assertEqual(extract.collision_class({}, off, record(True), switched_on=True), 'simple')
        self.assertEqual(extract.collision_class({}, off, record(False), switched_on=True), 'none')


if __name__ == '__main__':
    unittest.main()

"""Regression checks for the animation-to-move-track maths; no game assets required."""
import math
import unittest

import skeletal_anim as sa


def quat_about_z(degrees):
    half = math.radians(degrees) / 2.0
    return (0.0, 0.0, math.sin(half), math.cos(half))


class RotationTests(unittest.TestCase):
    def test_a_rotator_survives_the_trip_through_a_matrix(self):
        for pitch, yaw, roll in ((0, 0, 0), (10, 80, -30), (-45, 170, 5), (20, -135, 60)):
            matrix = sa._from_rotator(*(a * 32768.0 / 180.0 for a in (pitch, yaw, roll)))
            back = sa._euler_degrees(matrix)
            for got, want in zip(back, (roll, pitch, yaw)):
                self.assertAlmostEqual(got, want, places=4)

    def test_a_quaternion_about_z_is_a_yaw(self):
        roll, pitch, yaw = sa._euler_degrees(sa._from_quat(quat_about_z(90.0)))
        self.assertAlmostEqual(yaw, 90.0, places=4)
        self.assertAlmostEqual(roll, 0.0, places=4)
        self.assertAlmostEqual(pitch, 0.0, places=4)

    def test_keys_are_evenly_spaced_and_a_rotation_takes_the_short_way(self):
        self.assertEqual(sa._key_at([(0.0, 0.0, 0.0), (10.0, 0.0, 0.0), (10.0, 4.0, 0.0)], 0.75), [10.0, 2.0, 0.0])
        a, b = quat_about_z(10.0), tuple(-c for c in quat_about_z(30.0))
        _, _, yaw = sa._euler_degrees(sa._from_quat(sa._key_at([a, b], 0.5)))
        self.assertAlmostEqual(yaw, 20.0, places=2)


class BodyPoseTests(unittest.TestCase):
    SKELETON = {'bound_to': 1, 'rot_origin': [0, 0, 0],
                'bones': [{'name': 'Root', 'parent': 0, 'position': [0.0, 0.0, 0.0], 'rotation': [0, 0, 0, 1]},
                          {'name': 'Main', 'parent': 0, 'position': [0.0, -400.0, 0.0], 'rotation': [0, 0, 0, 1]}]}

    def test_the_reference_pose_moves_nothing(self):
        tracks = {'Root': ([(0.0, 0.0, 0.0)], [(0, 0, 0, 1)]), 'Main': ([(0.0, -400.0, 0.0)], [(0, 0, 0, 1)])}
        rotation, moved = sa.body_pose(self.SKELETON, tracks, 0.5)
        self.assertEqual([round(c, 6) for c in moved], [0.0, 0.0, 0.0])
        self.assertEqual(sa._euler_degrees(rotation), [0.0, 0.0, 0.0])

    def test_the_root_carries_the_body_and_the_body_turns_about_its_own_bone(self):
        tracks = {'Root': ([(1000.0, 0.0, 0.0), (3000.0, 0.0, 0.0)], [(0, 0, 0, 1)]),
                  'Main': ([(0.0, -400.0, 0.0)], [quat_about_z(90.0)])}
        rotation, moved = sa.body_pose(self.SKELETON, tracks, 0.5)
        self.assertAlmostEqual(sa._euler_degrees(rotation)[2], 90.0, places=4)
        # A vertex AT the bone stays at the bone, carried 2000 along X: the
        # turn is about the bone and not about the mesh's origin.
        at_bone = [moved[k] + sa._apply(rotation, [0.0, -400.0, 0.0])[k] for k in range(3)]
        for got, want in zip(at_bone, (2000.0, -400.0, 0.0)):
            self.assertAlmostEqual(got, want, places=3)

    def test_the_meshs_own_turn_is_applied_to_the_flight_too(self):
        skeleton = dict(self.SKELETON, rot_origin=[0, 16384, 0])
        tracks = {'Root': ([(1000.0, 0.0, 0.0)], [(0, 0, 0, 1)])}
        _, moved = sa.body_pose(skeleton, tracks, 0.0)
        for got, want in zip(moved, (0.0, 1000.0, 0.0)):
            self.assertAlmostEqual(got, want, places=3)


if __name__ == '__main__':
    unittest.main()

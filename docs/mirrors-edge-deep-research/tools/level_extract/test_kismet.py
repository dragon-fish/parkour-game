"""Regression checks for the Kismet export; no game assets required."""
import unittest

import kismet


class TeleportTests(unittest.TestCase):
    def graph(self, out_name):
        return {'nodes': {
            'p#1': {'cls': 'SeqAct_Interp', 'matinee': 'P.me1#1', 'length': 4.0,
                    'events_at': [{'name': 'tele', 'time': 2.0}],
                    'outs': [{'name': out_name, 'to': [['p#2', 0]]}]},
            'p#2': {'cls': 'SeqAct_Teleport', 'outs': [],
                    'destinations': [{'actor': 'p.Body', 'position': [10.0, 0.0, 0.0], 'basis': []}]}}}

    def matinees(self, absolute):
        keys = {'position': [{'time': 0.0, 'value': [0.0, 0.0, 0.0]}, {'time': 4.0, 'value': [0.0, 0.0, 8.0]}],
                'absolute': absolute}
        # Turned a quarter round: the actor's own +Z is the world's +X.
        frame = {'position': [10.0, 0.0, 0.0], 'basis': [[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]]}
        return [{'name': 'P.me1#1', 'groups': [{'actors': ['P.me1.Body'], 'keys': keys}], 'frames': {'P.me1.Body': frame}}]

    def test_a_destination_is_where_its_sequence_has_put_it_when_the_event_fires(self):
        graph = self.graph('tele')
        kismet.settle_teleports(graph, self.matinees(False))
        self.assertEqual(graph['nodes']['p#2']['destinations'][0]['position'], [14.0, 0.0, 0.0])

    def test_completed_is_the_end_of_the_sequence_and_world_keys_are_places(self):
        graph = self.graph('Completed')
        kismet.settle_teleports(graph, self.matinees(True))
        self.assertEqual(graph['nodes']['p#2']['destinations'][0]['position'], [0.0, 0.0, 8.0])

    def test_an_output_that_is_no_moment_of_the_sequence_leaves_the_place_alone(self):
        graph = self.graph('Aborted')
        kismet.settle_teleports(graph, self.matinees(False))
        self.assertEqual(graph['nodes']['p#2']['destinations'][0]['position'], [10.0, 0.0, 0.0])


if __name__ == '__main__':
    unittest.main()

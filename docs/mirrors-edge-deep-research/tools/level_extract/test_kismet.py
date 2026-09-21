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


class CutsceneTests(unittest.TestCase):
    def graph(self, **interp):
        node = {'cls': 'SeqAct_Interp', '_animated': True, 'outs': [{'name': 'Completed', 'to': [['p#2', 0]]}]}
        node.update(interp)
        return {'vars': {'v#1': {'cls': 'SeqVar_Player'}, 'v#2': {'cls': 'SeqVar_Object', 'actor': 'p.Cop'}},
                'nodes': {'p#1': node,
                          'p#2': {'cls': 'SeqAct_Teleport', 'outs': [], 'vars': {'Target': ['v#1']}},
                          'p#3': {'cls': 'SeqAct_TdDisablePlayerInput', 'outs': [{'name': 'Out', 'to': [['p#4', 0]]}]},
                          'p#4': {'cls': 'SeqAct_Interp', '_animated': True, 'outs': []},
                          'p#5': {'cls': 'SeqAct_Interp', '_animated': True, 'outs': [{'name': 'Completed', 'to': [['p#6', 0]]}]},
                          'p#6': {'cls': 'SeqAct_Teleport', 'outs': [], 'vars': {'Target': ['v#2']}}}}

    def test_the_players_cutscenes_are_marked_and_a_bystanders_is_not(self):
        graph = self.graph()
        kismet.mark_cutscenes(graph)
        nodes = graph['nodes']
        self.assertTrue(nodes['p#1'].get('cutscene'), 'it teleports the player from its own output')
        self.assertTrue(nodes['p#4'].get('cutscene'), 'it is entered with the input taken away')
        self.assertFalse(nodes['p#5'].get('cutscene'), 'it moves somebody else')
        self.assertNotIn('_animated', nodes['p#5'], 'the working key does not reach the export')

    def test_a_looping_sequence_is_never_played_through(self):
        graph = self.graph(props={'bLooping': True})
        kismet.mark_cutscenes(graph)
        self.assertFalse(graph['nodes']['p#1'].get('cutscene'))


if __name__ == '__main__':
    unittest.main()

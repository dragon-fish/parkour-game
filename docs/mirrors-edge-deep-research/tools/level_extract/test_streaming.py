"""The walk from a streaming action up to what fires it; no game assets required.

Graphs are written by hand in the shape streaming.read_graph() produces.
"""
import unittest

import streaming

TRIGGER = {'name': 'Trigger_1', 'class': 'Trigger', 'position': [0.0, 0.0, 0.0], 'radius': 1.0, 'height': 1.0}


def node(cls, ups=(), **data):
    return dict({'cls': cls, 'ups': list(ups)}, **data)


def touch(name='Trigger_1'):
    return node('SeqEvent_Touch', trigger=dict(TRIGGER, name=name))


def action(levels, ups):
    return node('SeqAct_MultiLevelStreaming', ups, levels=levels, inputs=['load', 'unload'])


def summary(steps):
    return [(s['source']['trigger']['name'], s['op'], s['packages'], s['delay'], s['order'], s['through'])
            for s in steps]


class FlattenTests(unittest.TestCase):
    def test_a_touch_unloads_and_its_finished_loads(self):
        graph = {1: touch(),
                 2: action(['a'], [(1, 'Touched', 1)]),
                 3: action(['b'], [(2, 'Finished', 0)])}
        steps, report = streaming.flatten({'p': graph})
        self.assertEqual(summary(steps), [('Trigger_1', 'unload', ['a'], 0.0, 0, []),
                                          ('Trigger_1', 'load', ['b'], 0.0, 1, [])])
        self.assertEqual(report['dead_ends'], {})

    def test_a_delay_adds_up_and_its_stop_input_starts_nothing(self):
        graph = {1: touch(), 4: touch('Stopper'),
                 2: node('SeqAct_Delay', [(1, 'Touched', 0), (4, 'Touched', 1)], delay=2.5),
                 3: action(['a'], [(2, 'Finished', 0)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual(summary(steps), [('Trigger_1', 'load', ['a'], 2.5, 0, [])])

    def test_a_matinee_is_waited_for_only_out_of_completed(self):
        graph = {1: touch(),
                 2: node('SeqAct_Interp', [(1, 'Touched', 0)], length=4.0),
                 3: action(['waited'], [(2, 'Completed', 1)]),
                 4: action(['at_once'], [(2, 'Out', 1)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual({(s['packages'][0], s['delay']) for s in steps}, {('waited', 4.0), ('at_once', 0.0)})

    def test_a_remote_event_is_followed_into_another_package(self):
        persistent = {1: node('SeqEvent_RemoteEvent', event='go'),
                      2: action(['a'], [(1, 'Out', 0)])}
        music = {1: touch('InTheMusicPackage'),
                 2: node('SeqAct_ActivateRemoteEvent', [(1, 'Touched', 0)], event='go')}
        steps, report = streaming.flatten({'p': persistent, 'mus': music})
        self.assertEqual(summary(steps), [('InTheMusicPackage', 'load', ['a'], 0.0, 0, [])])
        self.assertEqual(steps[0]['source']['package'], 'mus')
        self.assertEqual(report['unsent'], [])

    def test_an_event_nobody_sends_is_reported(self):
        graph = {1: node('SeqEvent_RemoteEvent', event='never'),
                 2: action(['a'], [(1, 'Out', 0)])}
        steps, report = streaming.flatten({'p': graph})
        self.assertEqual(steps, [])
        self.assertEqual(report['unsent'], ['never'])

    def test_a_gate_is_walked_through_its_in_and_named(self):
        graph = {1: touch('Through'), 4: touch('Opener'),
                 2: node('SeqAct_Gate', [(1, 'Touched', 0), (4, 'Touched', 1)]),
                 3: action(['a'], [(2, 'Out', 0)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual(summary(steps), [('Through', 'load', ['a'], 0.0, 0, ['SeqAct_Gate'])])

    def test_the_save_switch_is_not_named(self):
        graph = {1: touch(),
                 2: node('SeqAct_DisableLoadFromLastCheckpoint', [(1, 'Touched', 0)]),
                 3: action(['a'], [(2, 'Out', 1)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual(steps[0]['through'], [])

    def test_a_sub_sequence_is_left_by_the_input_that_activates_it(self):
        graph = {1: touch('Right'), 5: touch('Wrong'),
                 2: node('Sequence', [(1, 'Touched', 0), (5, 'Touched', 1)], finishes={}),
                 3: node('SeqEvent_SequenceActivated', port=(2, 0)),
                 4: action(['roof'], [(3, 'Out', 0)])}
        steps, report = streaming.flatten({'p': graph})
        self.assertEqual(summary(steps), [('Right', 'load', ['roof'], 0.0, 0, [])])
        self.assertEqual(report['unhandled_roots'], {})

    def test_a_sub_sequence_is_entered_by_the_output_the_signal_left_it_by(self):
        graph = {1: touch(),
                 2: node('SeqEvent_SequenceActivated', port=(4, 0)),
                 3: node('SeqAct_FinishSequence', [(2, 'Out', 0)]),
                 4: node('Sequence', [(1, 'Touched', 0)], finishes={'Done': 3}),
                 5: action(['a'], [(4, 'Done', 0)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual(summary(steps), [('Trigger_1', 'load', ['a'], 0.0, 0, [])])

    def test_a_cutscene_is_not_waited_for(self):
        graph = {1: touch(),
                 2: node('SeqAct_TdIntoCutscene', [(1, 'Touched', 0)]),
                 3: node('SeqAct_Interp', [(2, 'Out', 0)], length=130.0),
                 4: action(['a'], [(3, 'Completed', 0)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual(steps[0]['delay'], 0.0)

    def test_a_loop_ends(self):
        graph = {1: touch(),
                 2: node('SeqAct_Switch', [(1, 'Touched', 0), (3, 'Finished', 0)]),
                 3: node('SeqAct_Delay', [(2, 'Link 1', 0)], delay=1.0),
                 4: action(['a'], [(3, 'Finished', 0)])}
        steps, _ = streaming.flatten({'p': graph})
        self.assertEqual(summary(steps), [('Trigger_1', 'load', ['a'], 1.0, 0, ['SeqAct_Switch'])])

    def test_an_event_with_no_actor_behind_it_is_reported_not_built(self):
        graph = {1: node('SeqEvt_TdPlayerDeath'),
                 2: node('SeqEvt_TdCheckpointLoaded'),
                 3: action(['a'], [(1, 'Out', 0), (2, 'Out', 0)])}
        steps, report = streaming.flatten({'p': graph})
        self.assertEqual(steps, [])
        self.assertEqual(report['unhandled_roots'], {'SeqEvt_TdPlayerDeath': 1})
        self.assertEqual(report['restores'], 1)


class PackageKeyTests(unittest.TestCase):
    # The same table is in tests/test_me_package_key.gd: two implementations
    # of one rule, and a key spelt two ways is a package that never shows.
    def test_keys(self):
        for given, wanted in (('Convoy_Roof-Conv_slc_lgts', 'convoy_roof-conv_slc_lgts'),
                              ('Convoy_Roof.me1', 'convoy_roof'),
                              ('Stormdrain_StdP_Art.ME1', 'stormdrain_stdp_art'),
                              ('boat_bac', 'boat_bac')):
            self.assertEqual(streaming.package_key(given), wanted)
        self.assertFalse(streaming.has_geometry('convoy_sb01_mus'))
        self.assertFalse(streaming.has_geometry('convoy_roof_aud'))
        self.assertTrue(streaming.has_geometry('convoy_roof_art'))


if __name__ == '__main__':
    unittest.main()

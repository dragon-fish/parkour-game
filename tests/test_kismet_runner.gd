extends ParkourTest

# What the original's nodes MEAN, on graphs written by hand in the shape the
# extractor's kismet.py produces. Structural: which output fires, in what
# order, after what state -- the things that were wrong when the graph was
# read as though it held none.

const META := PackagePresence.PACKAGE_META


## A node of the graph. `outs` is [[name, [[target, input], ...]], ...].
func _n(cls: String, outs: Array = [], extra: Dictionary = {}) -> Dictionary:
	var built: Array = []
	for out: Array in outs:
		built.append({name = out[0], to = out[1]})
	var node := {cls = cls, package = "p", name = cls, ins = [], outs = built}
	node.merge(extra, true)
	return node


## A probe: an unknown class, so reaching it is counted in `unknown`.
func _probe(name: String) -> Dictionary:
	return _n("Probe_" + name)


func _reached(runner: KismetRunner, name: String) -> int:
	return runner.unknown.get("Probe_" + name, 0)


func _runner(nodes: Dictionary, variables: Dictionary = {}, with_presence: bool = false) -> Dictionary:
	var graph := KismetGraph.new()
	graph.nodes = nodes
	graph.variables = variables
	var root := Node3D.new()
	var runner := KismetRunner.new()
	runner.graph = graph
	var presence: PackagePresence = null
	if with_presence:
		presence = PackagePresence.new()
		presence.snapshots = {"Start": PackedStringArray(["a"]), "Later": PackedStringArray(["b"])}
		presence.start = "Start"
		presence.managed = PackedStringArray(["a", "b"])
		runner.streamed = PackedStringArray(["a", "b"])
		presence.add_child(runner)
		root.add_child(presence)
	else:
		root.add_child(runner)
	add_child_autofree(root)
	await step(2)
	if not with_presence:
		runner._start_level("")
	return {runner = runner, presence = presence, root = root}


func _event(runner: KismetRunner, id: String) -> void:
	runner._fire_event(id, [])
	runner._drain()


func test_a_gate_that_starts_shut_passes_nothing_until_opened() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["gate", 0]]]], {props = {MaxTriggerCount = 0}}),
		"open": _n("SeqEvent_RemoteEvent", [["Out", [["gate", 1]]]]),
		"gate": _n("SeqAct_Gate", [["Out", [["through", 0]]]], {props = {bOpen = false}}),
		"through": _probe("through"),
	})
	_event(rig.runner, "go")
	assert_eq(_reached(rig.runner, "through"), 0, "a shut gate is not a way through")
	_event(rig.runner, "open")
	_event(rig.runner, "go")
	assert_eq(_reached(rig.runner, "through"), 1, "opened, it is")


func test_a_gate_closes_itself_after_its_count() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["gate", 0]]]], {props = {MaxTriggerCount = 0}}),
		"gate": _n("SeqAct_Gate", [["Out", [["through", 0]]]], {props = {AutoCloseCount = 1}}),
		"through": _probe("through"),
	})
	_event(rig.runner, "go")
	_event(rig.runner, "go")
	assert_eq(_reached(rig.runner, "through"), 1, "open by default, shut after one")


func test_an_event_fires_once_unless_it_says_otherwise() -> void:
	var rig := await _runner({
		"once": _n("SeqEvent_RemoteEvent", [["Out", [["a", 0]]]]),
		"always": _n("SeqEvent_RemoteEvent", [["Out", [["b", 0]]]], {props = {MaxTriggerCount = 0}}),
		"a": _probe("a"), "b": _probe("b"),
	})
	for i in 3:
		_event(rig.runner, "once")
		_event(rig.runner, "always")
	assert_eq(_reached(rig.runner, "a"), 1, "UE3's MaxTriggerCount defaults to 1, not to unlimited")
	assert_eq(_reached(rig.runner, "b"), 3)


func test_a_switch_alternates_and_a_linked_int_routes_it() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["lever", 0]]]], {props = {MaxTriggerCount = 0}}),
		"lever": _n("SeqAct_Switch", [["Link 1", [["up", 0]]], ["Link 2", [["down", 0]]]],
				{props = {LinkCount = 2, bLooping = true}}),
		"up": _probe("up"), "down": _probe("down"),
		"route": _n("SeqEvent_RemoteEvent", [["Out", [["router", 0]]]], {props = {MaxTriggerCount = 0}}),
		"router": _n("SeqAct_Switch", [["Link 1", [["one", 0]]], ["Link 2", [["two", 0]]]],
				{props = {LinkCount = 2, IncrementAmount = 0}, vars = {Index = ["which"]}}),
		"set": _n("SeqEvent_RemoteEvent", [["Out", [["setter", 0]]]]),
		"setter": _n("SeqAct_SetInt", [["Out", []]], {vars = {Target = ["which"], Value = ["two_value"]}}),
		"one": _probe("one"), "two": _probe("two"),
	}, {"which": {cls = "SeqVar_Int", value = {IntValue = 1}}, "two_value": {cls = "SeqVar_Int", value = {IntValue = 2}}})
	for i in 3:
		_event(rig.runner, "go")
	assert_eq([_reached(rig.runner, "up"), _reached(rig.runner, "down")], [2, 1], "up, down, up")
	_event(rig.runner, "route")
	_event(rig.runner, "set")
	_event(rig.runner, "route")
	_event(rig.runner, "route")
	assert_eq([_reached(rig.runner, "one"), _reached(rig.runner, "two")], [1, 2],
			"with no increment the outlet is whatever the Int says")


func test_a_delay_waits_and_a_stopped_one_never_finishes() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["wait", 0], ["doomed", 0]]]]),
		"stop": _n("SeqEvent_RemoteEvent", [["Out", [["doomed", 1]]]]),
		"wait": _n("SeqAct_Delay", [["Finished", [["done", 0]]], ["Aborted", []]], {props = {Duration = 0.1}}),
		"doomed": _n("SeqAct_Delay", [["Finished", [["never", 0]]], ["Aborted", [["aborted", 0]]]], {props = {Duration = 0.1}}),
		"done": _probe("done"), "never": _probe("never"), "aborted": _probe("aborted"),
	})
	_event(rig.runner, "go")
	_event(rig.runner, "stop")
	assert_eq(_reached(rig.runner, "done"), 0, "not yet")
	await step(12)
	assert_eq(_reached(rig.runner, "done"), 1)
	assert_eq(_reached(rig.runner, "never"), 0, "a stopped Delay ignores its own timer coming home")
	assert_eq(_reached(rig.runner, "aborted"), 1)


func test_a_remote_event_crosses_packages_whatever_its_case() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["send", 0]]]]),
		"send": _n("SeqAct_ActivateRemoteEvent", [["Out", [["after", 0]]]], {props = {EventName = "BigDoorClosed"}}),
		"hear": _n("SeqEvent_RemoteEvent", [["Out", [["heard", 0]]]], {package = "other", props = {EventName = "bigdoorclosed"}}),
		"heard": _probe("heard"), "after": _probe("after"),
	})
	_event(rig.runner, "go")
	assert_eq(_reached(rig.runner, "heard"), 1)
	assert_eq(_reached(rig.runner, "after"), 1, "and the sender carries on")


func test_a_sub_sequence_is_entered_by_its_port_and_left_by_its_finish() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["sub", 1]]]]),
		"sub": {cls = "Sequence", package = "p", name = "Sub", ins = ["A", "B"], ports = ["in_a", "in_b"],
				outs = [{name = "Done", to = [["after", 0]], from = "finish"}]},
		"in_a": _n("SeqEvent_SequenceActivated", [["Out", [["wrong", 0]]]]),
		"in_b": _n("SeqEvent_SequenceActivated", [["Out", [["finish", 0]]]]),
		"finish": _n("SeqAct_FinishSequence", [], {sequence = "sub"}),
		"wrong": _probe("wrong"), "after": _probe("after"),
	})
	_event(rig.runner, "go")
	assert_eq(_reached(rig.runner, "wrong"), 0, "input B is not input A")
	assert_eq(_reached(rig.runner, "after"), 1)


func test_a_matinee_takes_its_time_and_fires_its_event_track_one_way() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["door", 0]]]]),
		"back": _n("SeqEvent_RemoteEvent", [["Out", [["door", 1]]]]),
		"door": _n("SeqAct_Interp", [["Completed", [["completed", 0]]], ["Aborted", []],
				["Open", [["opened", 0]]], ["Close", [["closed", 0]]]],
				{length = 0.2, events_at = [
					{name = "Open", time = 0.0, forwards = true, backwards = false},
					{name = "close", time = 0.1, forwards = false, backwards = true}]}),
		"completed": _probe("completed"), "opened": _probe("opened"), "closed": _probe("closed"),
	})
	_event(rig.runner, "go")
	assert_eq(_reached(rig.runner, "opened"), 1, "a key at the start fires on the start")
	assert_eq(_reached(rig.runner, "completed"), 0, "and the sequence has not run yet")
	await step(15)
	assert_eq(_reached(rig.runner, "completed"), 1)
	assert_eq(_reached(rig.runner, "closed"), 0, "a backwards-only key stays quiet going forwards")
	_event(rig.runner, "back")
	await step(15)
	assert_eq(_reached(rig.runner, "closed"), 1, "and fires on the way back, whatever its case")
	assert_eq(_reached(rig.runner, "completed"), 2, "with no Reversed output the way back Completes too")


func test_a_class_nobody_has_taught_it_is_passed_through_and_counted() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["ai", 0]]]]),
		"ai": _n("SeqAct_AIMoveToActor", [["Out", [["out", 0]]], ["Failed", [["failed", 0]]], ["Finished", [["finished", 0]]]]),
		"out": _probe("out"), "failed": _probe("failed"), "finished": _probe("finished"),
	})
	_event(rig.runner, "go")
	assert_eq([_reached(rig.runner, "out"), _reached(rig.runner, "finished"), _reached(rig.runner, "failed")], [1, 1, 0])
	assert_eq(rig.runner.unknown.get("SeqAct_AIMoveToActor", 0), 1, "what is missing can be read off, not guessed at")


func test_streaming_finishes_when_the_level_has_settled_and_wakes_the_new_package() -> void:
	var rig := await _runner({
		"go": _n("SeqEvent_RemoteEvent", [["Out", [["unload", 1]]]]),
		"unload": _n("SeqAct_MultiLevelStreaming", [["Finished", [["load", 0]]]], {levels = ["a"]}),
		"load": _n("SeqAct_MultiLevelStreaming", [["Finished", [["door", 0]]]], {levels = ["b"]}),
		"door": _probe("door"),
		"hello": _n("SeqEvent_LevelLoaded", [["Loaded and Visible", [["woke", 0]]]], {package = "b"}),
		"woke": _probe("woke"),
		"asleep": _n("SeqEvent_RemoteEvent", [["Out", [["dreamt", 0]]]], {package = "b", props = {EventName = "x"}}),
		"dreamt": _probe("dreamt"),
	}, {}, true)
	var presence: PackagePresence = rig.presence
	assert_true(presence.present.has("a") and not presence.present.has("b"), "the start snapshot")
	_event(rig.runner, "asleep")
	assert_eq(_reached(rig.runner, "dreamt"), 0, "a package that is not loaded has no Kismet")
	_event(rig.runner, "go")
	await step(3)
	assert_true(presence.present.has("b") and not presence.present.has("a"), "unloaded, then loaded")
	assert_eq(_reached(rig.runner, "door"), 1, "the door waited for the load's Finished")
	assert_eq(_reached(rig.runner, "woke"), 1, "and the package that arrived had its LevelLoaded")


func test_a_respawn_forgets_what_the_last_life_did() -> void:
	var rig := await _runner({
		"once": _n("SeqEvent_RemoteEvent", [["Out", [["gate", 2], ["a", 0]]]]),
		"gate": _n("SeqAct_Gate", [["Out", []]]),
		"a": _probe("a"),
	}, {}, true)
	_event(rig.runner, "once")
	_event(rig.runner, "once")
	assert_eq(_reached(rig.runner, "a"), 1)
	assert_false(rig.runner._state["gate"]["open"], "the gate was shut")
	rig.presence.restore("Start")
	assert_false(rig.runner._state.has("gate"), "and is as the level was built again")
	_event(rig.runner, "once")
	assert_eq(_reached(rig.runner, "a"), 2, "as is the event's one firing")

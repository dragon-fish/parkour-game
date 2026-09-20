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
		"door": _n("SeqAct_Interp", [["Completed", [["completed", 0]]], ["Aborted", [["reversed", 0]]],
				["Open", [["opened", 0]]], ["Close", [["closed", 0]]]],
				{length = 0.2, events_at = [
					{name = "Open", time = 0.0, forwards = true, backwards = false},
					{name = "close", time = 0.1, forwards = false, backwards = true}]}),
		"completed": _probe("completed"), "reversed": _probe("reversed"),
		"opened": _probe("opened"), "closed": _probe("closed"),
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
	assert_eq(_reached(rig.runner, "completed"), 1, "the way back does NOT complete: a door wired Completed -> Reverse would never rest")
	assert_eq(_reached(rig.runner, "reversed"), 1, "it ends on the second output, whatever this build labels it")


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


func test_a_collision_type_means_what_ue3_means_by_it() -> void:
	# A wall is solid only when it BLOCKS; a volume that hurts listens when it
	# blocks or touches. Steam is both, switched by one action.
	var nodes := {}
	for type: String in ["COLLIDE_NoCollision", "COLLIDE_TouchAll", "COLLIDE_BlockAll", "COLLIDE_BlockWeapons", ""]:
		var props := {CollisionType = type, bCollideActors = true} if type != "" else {}
		nodes["ev_" + type] = _n("SeqEvent_RemoteEvent", [["Out", [["set_" + type, 0]]]])
		nodes["set_" + type] = _n("SeqAct_ChangeCollision", [["Out", []]], {props = props, vars = {Target = ["wall", "steam"]}})
	var rig := await _runner(nodes, {"wall": {cls = "SeqVar_Object", actor = "p.Wall"}, "steam": {cls = "SeqVar_Object", actor = "p.Steam"}})
	var wall := StaticBody3D.new()
	wall.set_meta(KismetRunner.ACTOR_META, "p.Wall")
	var steam := Area3D.new()
	steam.set_meta(KismetRunner.ACTOR_META, "p.Steam")
	rig.root.add_child(wall)
	rig.root.add_child(steam)
	rig.runner.bind(rig.root)
	var expected := {"COLLIDE_NoCollision": [false, false], "COLLIDE_TouchAll": [false, true],
		"COLLIDE_BlockAll": [true, true], "COLLIDE_BlockWeapons": [false, false], "": [true, true]}
	for type: String in expected:
		_event(rig.runner, "ev_" + type)
		assert_eq([wall.collision_layer != 0, steam.collision_layer != 0], expected[type],
				"%s: [wall solid, steam hurts]; the leftover bCollideActors beside it decides nothing" % (type if type != "" else "unwritten (CustomDefault)"))


func test_what_starts_off_is_off_until_kismet_says_and_again_after_a_respawn() -> void:
	var rig := await _runner({
		"on": _n("SeqEvent_RemoteEvent", [["Out", [["set", 0]]]]),
		"set": _n("SeqAct_ChangeCollision", [["Out", []]], {props = {CollisionType = "COLLIDE_TouchAll"}, vars = {Target = ["crush"]}}),
	}, {"crush": {cls = "SeqVar_Object", actor = "p.Crush"}}, true)
	rig.runner.graph.actors = {"p.Crush": {cls = "PhysicsVolume", package = "p", starts_off = true}}
	var crush := Area3D.new()
	crush.set_meta(KismetRunner.ACTOR_META, "p.Crush")
	rig.root.add_child(crush)
	rig.runner.bind(rig.root)
	assert_eq(crush.collision_layer, 0, "a door's crush volume does not hurt an open doorway")
	_event(rig.runner, "on")
	assert_ne(crush.collision_layer, 0, "it hurts while the door comes down")
	rig.presence.restore("Start")
	assert_eq(crush.collision_layer, 0, "and a respawn finds the doorway safe again")


func test_the_actions_on_an_actor_run_and_do_what_they_say() -> void:
	var nodes := {
		"hide": _n("SeqEvent_RemoteEvent", [["Out", [["hidden", 0]]]]),
		"hidden": _n("SeqAct_ToggleHidden", [["Out", []]], {vars = {Target = ["thing"]}}),
		"show": _n("SeqEvent_RemoteEvent", [["Out", [["hidden", 1]]]]),
		"off": _n("SeqEvent_RemoteEvent", [["Out", [["toggle", 1]]]]),
		"flip": _n("SeqEvent_RemoteEvent", [["Out", [["toggle", 2]]]]),
		"toggle": _n("SeqAct_Toggle", [["Out", []]], {vars = {Target = ["thing"], Bool = ["flag"]}, events = ["deaf"]}),
		"deaf": _n("SeqEvent_RemoteEvent", [["Out", [["heard", 0]]]], {props = {MaxTriggerCount = 0}}),
		"heard": _probe("heard"),
		"kill": _n("SeqEvent_RemoteEvent", [["Out", [["destroy", 0]]]]),
		"destroy": _n("SeqAct_Destroy", [["Out", []]], {vars = {Target = ["thing"]}}),
		"lift": _n("SeqEvent_RemoteEvent", [["Out", [["in_lift", 0]]]]),
		"in_lift": _n("SeqAct_TdInElevator", [["Out", [["rode", 0]]]]),
		"rode": _probe("rode"),
		"dice": _n("SeqEvent_RemoteEvent", [["Out", [["random", 0]]]], {props = {MaxTriggerCount = 0}}),
		"random": _n("SeqAct_RandomSwitch", [["Link 1", [["r", 0]]], ["Link 2", [["r", 0]]]], {props = {LinkCount = 2, bAutoDisableLinks = true}}),
		"r": _probe("r"),
		"ask": _n("SeqEvent_RemoteEvent", [["Out", [["compare", 0]]]]),
		"compare": _n("SeqCond_CompareInt", [["A <= B", [["le", 0]]], ["A > B", [["gt", 0]]], ["A == B", [["eq", 0]]]],
				{vars = {A = ["three"]}, props = {ValueB = 3}}),
		"le": _probe("le"), "gt": _probe("gt"), "eq": _probe("eq"),
	}
	var rig := await _runner(nodes, {"thing": {cls = "SeqVar_Object", actor = "p.Thing"},
		"flag": {cls = "SeqVar_Bool", value = {bValue = true}}, "three": {cls = "SeqVar_Int", value = {IntValue = 3}}})
	var thing := StaticBody3D.new()
	thing.set_meta(KismetRunner.ACTOR_META, "p.Thing")
	var picture := MeshInstance3D.new()
	picture.name = "Mesh"
	picture.visible = false
	thing.add_child(picture)
	rig.root.add_child(thing)
	rig.runner.bind(rig.root)
	var runner: KismetRunner = rig.runner

	_event(runner, "show")
	assert_true(picture.visible, "a placement the original starts hidden has its MESH hidden: that is what is shown")
	_event(runner, "hide")
	assert_false(picture.visible)

	_event(runner, "off")
	assert_eq(thing.collision_layer, 0, "turned off")
	assert_false(runner._value("flag", true), "and the linked Bool with it")
	_event(runner, "deaf")
	assert_eq(_reached(runner, "heard"), 0, "and the linked event no longer listens")
	_event(runner, "flip")
	assert_ne(thing.collision_layer, 0, "toggled back on")
	_event(runner, "deaf")
	assert_eq(_reached(runner, "heard"), 1)

	_event(runner, "kill")
	assert_eq(thing.collision_layer, 0, "destroyed: gone from the level, the node kept for the respawn")
	_event(runner, "lift")
	assert_eq(_reached(runner, "rode"), 1, "with no player to restrict it still passes on")
	for i in 3:
		_event(runner, "dice")
	assert_eq(_reached(runner, "r"), 2, "each link once, then nothing: auto-disabled and not looping")
	_event(runner, "ask")
	assert_eq([_reached(runner, "le"), _reached(runner, "gt"), _reached(runner, "eq")], [1, 0, 1], "3 against 3")


func test_a_press_fires_every_stage_the_original_gives_it() -> void:
	# A valve's stages. One level hangs its effect on Finished, the next on
	# Start; a press that named the stages it knew lost the water valve.
	var rig := await _runner({
		"valve": _n("SeqEvent_TdUsed", [["Start", [["started", 0]]], ["Looping", []], ["Last turn", []],
				["Finished", [["finished", 0]]], ["Aborted", [["aborted", 0]]]], {originator = "p.Valve"}),
		"started": _probe("started"), "finished": _probe("finished"), "aborted": _probe("aborted"),
	})
	rig.runner._on_used("p.Valve")
	assert_eq([_reached(rig.runner, "started"), _reached(rig.runner, "finished"), _reached(rig.runner, "aborted")], [1, 1, 0])
	rig.runner._on_used("p.Valve")
	assert_eq(_reached(rig.runner, "started"), 1, "and a press is ONE firing of the event, whatever its stages")


func test_a_sub_sequence_can_be_entered_as_often_as_it_is_called() -> void:
	# A lift's "open the car doors": once at the bottom, once at the top.
	var rig := await _runner({
		"call": _n("SeqEvent_RemoteEvent", [["Out", [["doors", 0]]]], {props = {MaxTriggerCount = 0}}),
		"doors": {cls = "Sequence", package = "p", name = "Doors", ins = ["open"], ports = ["enter"], outs = []},
		"enter": _n("SeqEvent_SequenceActivated", [["Out", [["opened", 0]]]]),
		"opened": _probe("opened"),
	})
	_event(rig.runner, "call")
	_event(rig.runner, "call")
	assert_eq(_reached(rig.runner, "opened"), 2, "a sub-sequence is a subroutine, not a one-shot")

extends ParkourTest

# Structural only: which packages are in the level after a restore and after a
# trigger, that a package which is not is neither drawn nor solid, and that
# the original's order -- unload, THEN load -- survives two steps falling due
# on the same tick. No numbers of the feel are asserted here.

const KEY_META := PackagePresence.PACKAGE_META


func _body(root: Node, name: String, package: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.set_meta(KEY_META, package)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	root.add_child(body)
	return body


func _trigger(presence: Node, source: String, steps: Array[Dictionary]) -> StreamingTrigger:
	var trigger := StreamingTrigger.new()
	trigger.name = source
	trigger.source = source
	trigger.steps = steps
	presence.add_child(trigger)
	return trigger


func _rig(triggers: Dictionary = {}) -> Dictionary:
	var root := Node3D.new()
	var rig := {root = root,
		roof = _body(root, "Roof", "roof"),
		shell = _body(root, "Shell", "roof_shell"),
		hall = _body(root, "Hall", "hall"),
		sky = _body(root, "Sky", "sky")}
	var presence := PackagePresence.new()
	presence.name = "Streaming"
	presence.snapshots = {
		"Start": PackedStringArray(["roof", "roof_shell", "roof_aud"]),
		"Hall": PackedStringArray(["hall"]),
	}
	presence.start = "Start"
	# `sky` is no one's to stream: it must survive everything below.
	presence.managed = PackedStringArray(["roof", "roof_shell", "hall"])
	root.add_child(presence)
	for source: String in triggers:
		rig[source] = _trigger(presence, source, triggers[source])
	rig.presence = presence
	add_child_autofree(root)
	return rig


func _in_level(body: StaticBody3D) -> bool:
	return body.visible and body.can_process() and body.collision_layer != 0


func test_the_level_opens_on_the_start_snapshot() -> void:
	var rig := _rig()
	await step(2)
	assert_true(_in_level(rig.roof), "the start snapshot names the roof")
	assert_true(_in_level(rig.shell), "and its shell")
	assert_false(_in_level(rig.hall), "the hall is not loaded at the start")
	assert_false(rig.hall.visible, "a package that is not in the level is not drawn")
	assert_eq(rig.hall.collision_layer, 0, "nor solid")
	assert_false(rig.hall.can_process(), "and whatever scripts it carries are stopped")
	assert_true(_in_level(rig.sky), "a package nobody streams is always there")
	assert_eq(rig.presence.present_count(), 2, "audio packages in a snapshot govern nothing")


func test_a_restore_takes_the_checkpoints_own_snapshot() -> void:
	var rig := _rig()
	await step(2)
	rig.presence.restore("Hall")
	assert_true(_in_level(rig.hall), "the hall's checkpoint loads the hall")
	assert_false(_in_level(rig.roof), "and nothing of the roof")
	assert_false(_in_level(rig.shell), "whose shell would stand in the hall")
	assert_true(_in_level(rig.sky), "the rest of the level is untouched")


func test_a_trigger_unloads_before_it_loads() -> void:
	# Listed load-first on purpose: the order is the steps' own, not the list's.
	var steps: Array[Dictionary] = [
		{op = "load", packages = PackedStringArray(["hall", "roof_shell"]), delay = 0.0, order = 1},
		{op = "unload", packages = PackedStringArray(["roof", "roof_shell"]), delay = 0.0, order = 0},
	]
	var rig := _rig({"door": steps})
	await step(2)
	rig.door.fired.emit(rig.door)
	await step(1)
	assert_false(_in_level(rig.roof), "the roof was unloaded")
	assert_true(_in_level(rig.hall), "the hall was loaded")
	assert_true(_in_level(rig.shell), "what the later step loads stays, though the earlier one unloaded it")
	assert_eq(rig.presence.last_source, "door", "the HUD is told who did it")


func test_a_delayed_step_waits_and_a_respawn_drops_it() -> void:
	var steps: Array[Dictionary] = [
		{op = "unload", packages = PackedStringArray(["roof"]), delay = 0.2, order = 0},
	]
	var rig := _rig({"button": steps})
	await step(2)
	rig.button.fired.emit(rig.button)
	await step(3)
	assert_true(_in_level(rig.roof), "0.2 s have not passed")
	await step(15)
	assert_false(_in_level(rig.roof), "now they have")

	rig.presence.restore("Start")
	rig.button.fired.emit(rig.button)
	await step(3)
	rig.presence.reset_for_respawn()
	await step(20)
	assert_true(_in_level(rig.roof), "a step still waiting belongs to the life that set it off")


func test_a_trigger_fires_once_per_life_and_not_from_an_absent_package() -> void:
	var rig := _rig({"once": [] as Array[Dictionary]})
	await step(2)
	var trigger: StreamingTrigger = rig.once
	watch_signals(trigger)
	trigger._fire()
	trigger._fire()
	assert_signal_emit_count(trigger, "fired", 1, "a second touch in the same life does nothing")
	trigger.reset_for_respawn()
	trigger._fire()
	assert_signal_emit_count(trigger, "fired", 2, "a respawn brings it back")
	trigger.reset_for_respawn()
	trigger.process_mode = Node.PROCESS_MODE_DISABLED
	trigger._fire()
	assert_signal_emit_count(trigger, "fired", 2, "a trigger whose package is not in the level cannot fire")

extends ParkourTest

# Structural only: which packages are in the level after a restore and after
# a load or an unload, that a package which is not is neither drawn nor solid,
# and that whoever asked for the change is told when it is through.

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


func _rig() -> Dictionary:
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
	assert_false(rig.hall.visible, "a package that is not in the level is not drawn")
	assert_eq(rig.hall.collision_layer, 0, "nor solid")
	assert_false(rig.hall.can_process(), "and whatever scripts it carries are stopped")
	assert_true(_in_level(rig.sky), "a package nobody streams is always there")
	assert_eq(rig.presence.present_count(), 2, "audio packages in a snapshot govern nothing")


func test_a_restore_takes_the_checkpoints_own_snapshot() -> void:
	var rig := _rig()
	await step(2)
	watch_signals(rig.presence)
	rig.presence.restore("Hall")
	assert_true(_in_level(rig.hall), "the hall's checkpoint loads the hall")
	assert_false(_in_level(rig.roof), "and nothing of the roof")
	assert_false(_in_level(rig.shell), "whose shell would stand in the hall")
	assert_true(_in_level(rig.sky), "the rest of the level is untouched")
	assert_signal_emitted(rig.presence, "restoring")
	assert_signal_emitted_with_parameters(rig.presence, "restored", ["Hall"])


func test_loading_and_unloading_say_what_changed_and_when_it_is_through() -> void:
	var rig := _rig()
	await step(2)
	watch_signals(rig.presence)
	rig.presence.unload_packages(PackedStringArray(["roof", "never_loaded"]), "test")
	assert_false(_in_level(rig.roof))
	assert_true(_in_level(rig.shell), "only what was named goes")
	assert_signal_emitted_with_parameters(rig.presence, "changed", [[] as Array[String], ["roof"] as Array[String]])
	rig.presence.load_packages(PackedStringArray(["hall"]), "test")
	assert_true(_in_level(rig.hall))
	assert_true(rig.presence.is_settled())
	assert_signal_emit_count(rig.presence, "settled", 2, "once per change, even one that switched nothing over frames")


func test_a_change_is_spread_over_frames_nearest_first() -> void:
	var root := Node3D.new()
	var near := _body(root, "Near", "hall")
	var far := _body(root, "Far", "hall")
	far.position = Vector3(100.0, 0.0, 0.0)
	var presence := PackagePresence.new()
	presence.snapshots = {"Start": PackedStringArray([])}
	presence.start = "Start"
	presence.managed = PackedStringArray(["hall"])
	presence.nodes_per_frame = 1
	root.add_child(presence)
	add_child_autofree(root)
	await step(3)
	assert_false(_in_level(near) or _in_level(far), "neither is loaded at the start")
	presence.load_packages(PackedStringArray(["hall"]), "test")
	assert_true(_in_level(near), "what is nearest is there on the first frame")
	assert_false(_in_level(far), "the far end follows")
	assert_false(presence.is_settled())
	await wait_for_signal(presence.settled, 1.0)
	assert_true(_in_level(far))

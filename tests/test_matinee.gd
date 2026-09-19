extends ParkourTest

# A level's movement sequences are things a life uses up: a platform that has
# fallen stays fallen. A respawn has to put them back, or the level can no
# longer be finished.

func _rig() -> Dictionary:
	var root := Node3D.new()
	var target := Node3D.new()
	target.name = "Target"
	target.position = Vector3(1.0, 2.0, 3.0)
	root.add_child(target)
	var matinee := Matinee.new()
	matinee.name = "Drop"
	matinee.length = 0.1
	matinee.tracks = [{
		targets = [NodePath("../Target")],
		local = false,
		pos_times = PackedFloat32Array([0.0, 0.1]),
		pos_values = PackedVector3Array([Vector3.ZERO, Vector3(0.0, -2.0, 0.0)]),
		pos_arrive = PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		pos_leave = PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		pos_modes = PackedByteArray([1, 1]),
		rot_times = PackedFloat32Array(), rot_values = PackedVector3Array(),
		rot_arrive = PackedVector3Array(), rot_leave = PackedVector3Array(),
		rot_modes = PackedByteArray(),
		scl_times = PackedFloat32Array(), scl_values = PackedVector3Array(),
		scl_arrive = PackedVector3Array(), scl_leave = PackedVector3Array(),
		scl_modes = PackedByteArray(),
	}]
	root.add_child(matinee)
	get_tree().root.add_child(root)
	return {root = root, target = target, matinee = matinee}

func test_a_played_sequence_moves_its_target_and_a_respawn_puts_it_back() -> void:
	var rig := _rig()
	await step(1)
	rig.matinee.play()
	await step(12)
	assert_almost_eq(rig.target.global_position.y, 0.0, 0.01, "the sequence did not carry its target")
	get_tree().call_group(Arena.RESET_ON_RESPAWN, "reset_for_respawn")
	assert_almost_eq(rig.target.global_position.y, 2.0, 0.001, "a respawn left the target where the sequence put it")
	rig.matinee.play()
	await step(12)
	assert_almost_eq(rig.target.global_position.y, 0.0, 0.01, "the sequence could not be played again after a respawn")
	rig.root.queue_free()
	await step(1)

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


func test_a_target_carried_off_between_two_plays_is_played_where_it_now_stands() -> void:
	# A lift's doors: opened and shut at the bottom, carried up by the car,
	# opened again at the top.
	var rig := _rig()
	await step(1)
	rig.matinee.play()
	await step(12)
	rig.matinee.drive("reverse")
	await step(12)
	assert_almost_eq(rig.target.global_position.y, 2.0, 0.01, "shut again, where it began")
	rig.target.global_position += Vector3(0.0, 40.0, 0.0)
	rig.matinee.play()
	await step(12)
	assert_almost_eq(rig.target.global_position.y, 40.0, 0.01, "it was played where the car had left it, not hauled back down")
	rig.root.queue_free()
	await step(1)


func test_a_replay_from_the_end_still_starts_from_the_start() -> void:
	var rig := _rig()
	await step(1)
	rig.matinee.play()
	await step(12)
	rig.matinee.play()
	await step(12)
	assert_almost_eq(rig.target.global_position.y, 0.0, 0.01, "replayed from its end it must not take the end for its start")
	rig.root.queue_free()
	await step(1)


func test_an_absolute_track_puts_its_target_where_the_key_says() -> void:
	# UE3's IMF_World: a key is a place in the world. The subway's tunnel
	# pieces stand a pitch apart and enter one loop a second apart; read as
	# offsets from where each stood, every piece was thrown down the line by
	# the whole of its own key.
	var rig := _rig()
	rig.matinee.length = 4.0
	rig.matinee.start_position = 3.0
	rig.matinee.tracks[0]["absolute"] = true
	rig.matinee.tracks[0]["pos_times"] = PackedFloat32Array([0.0, 4.0])
	rig.matinee.tracks[0]["pos_values"] = PackedVector3Array([Vector3(0.0, 0.0, 400.0), Vector3(0.0, 0.0, 0.0)])
	rig.target.position = Vector3(0.0, 0.0, 100.0)   # where the key at 3 s is
	await step(1)
	rig.matinee.play()
	await step(1)
	assert_almost_eq(rig.target.global_position.z, 100.0 - 100.0 / 60.0, 0.5, "entered at 3 s it is where it stood, not 300 m from it")
	await step(30)
	assert_almost_eq(rig.target.global_position.z, 100.0 - 100.0 * 31.0 / 60.0, 1.0, "and moves along the keys from there")
	rig.root.queue_free()
	await step(1)


func test_what_rides_an_absolute_track_is_not_carried_twice_by_the_next_sequence() -> void:
	# The Edge's helicopter: one sequence flies it in, the next hovers it, both
	# keyed in the world, and what is SEEN is a second actor riding the first.
	# Captured where the fly-in had left it, the hover carried it the whole way
	# again and held it twice as far from the origin as the roof is.
	var rig := _rig()
	var track: Dictionary = rig.matinee.tracks[0]
	track["absolute"] = true
	# What it rides stands at the origin; it stands where the rig built it.
	track["pivots"] = [Transform3D.IDENTITY]
	track["pos_values"] = PackedVector3Array([Vector3(90.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0)])
	var hover := Matinee.new()
	hover.length = 0.1
	hover.tracks = [track.duplicate(true)]
	hover.tracks[0]["pos_values"] = PackedVector3Array([Vector3(100.0, 0.0, 0.0), Vector3(100.0, 1.0, 0.0)])
	rig.root.add_child(hover)
	await step(1)
	var built: Vector3 = rig.target.global_position
	rig.matinee.play()
	await step(12)
	assert_almost_eq(rig.target.global_position.x, built.x + 100.0, 0.01, "test setup: the fly-in arrived")
	hover.play()
	await step(12)
	assert_almost_eq(rig.target.global_position.x, built.x + 100.0, 0.01, "the hover holds it where the keys say, not 100 m further on")
	assert_almost_eq(rig.target.global_position.y, built.y + 1.0, 0.01)
	rig.root.queue_free()
	await step(1)

extends ParkourTest

# Which curtain a respawn draws is the one thing the player reads it by: black
# is a death, white is a reset they asked for. The colours themselves are
# tuning; that the two paths draw DIFFERENT ones, and that neither can loop, is
# not.

func _arena() -> Arena:
	var a: Arena = preload("res://scenes/main.tscn").instantiate()
	add_child_autofree(a)
	return a

func _lethal_at(arena: Arena, at: Vector3) -> DeathVolume:
	var volume := DeathVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 6.0)
	shape.shape = box
	volume.add_child(shape)
	arena.add_child(volume)
	volume.global_position = at
	return volume

func test_walking_into_a_lethal_volume_respawns_the_player() -> void:
	var arena := _arena()
	await step(2)
	var spawn: Vector3 = arena.spawn_point.global_position
	_lethal_at(arena, spawn + Vector3(40.0, 0.0, 0.0))
	arena.player.global_position = spawn + Vector3(40.0, 0.0, 0.0)
	await step(60)
	assert_lt(arena.player.global_position.distance_to(spawn), 3.0, \
		"the body was left in the volume that was supposed to kill it")

func test_a_lethal_volume_does_not_play_the_topple_cutscene() -> void:
	# The whole reason a level marks a shaft lethal is to skip the fall. A four
	# second performance of dying hands back the seconds the volume just saved,
	# and there is no floor down there to topple onto anyway.
	var arena := _arena()
	await step(2)
	var spawn: Vector3 = arena.spawn_point.global_position
	_lethal_at(arena, spawn + Vector3(40.0, 0.0, 0.0))
	arena.player.global_position = spawn + Vector3(40.0, 0.0, 0.0)
	await step(90)
	assert_ne(arena.player.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"a lethal volume started the death that a real fall earns")

func test_a_lethal_volume_around_the_spawn_does_not_loop() -> void:
	# An author who drops a shaft over a checkpoint should get a stuck player,
	# not a hung game. Two separate things keep it from looping and only one of
	# them is the guard: a body that respawns INSIDE the volume never left it,
	# so Area3D has no entry to report. It dies once and then stands there.
	var arena := _arena()
	await step(2)
	_lethal_at(arena, arena.spawn_point.global_position)
	await step(10)
	assert_true(arena._death_sequence.is_covering(), "test setup: the volume never fired")
	await step(180)
	assert_true(is_instance_valid(arena.player), "the loop took the player with it")
	assert_false(arena._death_sequence.is_covering(), \
		"the curtain never lifted: something is drawing a fresh one every frame")

func test_falling_out_of_the_world_is_a_death_and_a_reset_is_not() -> void:
	# Both draw a curtain now; what separates them is the colour, and the
	# player learns the difference without being told.
	var arena := _arena()
	await step(2)
	arena.player.global_position = Vector3(0.0, -arena.config.pawn.fall_recovery_depth - 5.0, 0.0)
	await step(2)
	assert_true(arena._death_sequence.is_covering(), \
		"falling out of the world still teleported the body with no curtain")
	assert_eq(arena.player.screen_effects.tint_color(), Color.BLACK, \
		"falling out of the world did not read as a death")

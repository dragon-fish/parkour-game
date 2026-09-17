extends ParkourTest

# Arena.rescue_below_hp turns every route to death into a white-curtain
# respawn. Asserted here: that each of the three routes is actually
# intercepted, and that zero leaves the ordinary behaviour alone.

var _arena: Arena

func after_each() -> void:
	if is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null

func _arena_with(threshold: float) -> Arena:
	var a: Arena = preload("res://scenes/main.tscn").instantiate()
	a.rescue_below_hp = threshold
	add_child_autofree(a)
	await step(2)
	_arena = a
	return a

func test_a_wound_below_the_threshold_is_rescued() -> void:
	var arena: Arena = await _arena_with(30.0)
	var player: Player = arena.player
	assert_gt(player.health.hp, 30.0, "test setup: the player did not start healthy")
	player.take_damage(80.0, Health.Cause.HAZARD)
	await step(2)
	assert_true(arena.rescued_count > 0, "dropping below the threshold did not rescue")

func test_zero_leaves_the_ordinary_behaviour_alone() -> void:
	# A level that never sets the field must behave exactly as before.
	var arena: Arena = await _arena_with(0.0)
	var player: Player = arena.player
	player.take_damage(80.0, Health.Cause.HAZARD)
	await step(2)
	assert_eq(arena.rescued_count, 0, "a level with rescue off performed a rescue")

func test_entering_fall_uncontrolled_is_rescued() -> void:
	# THE ROUTE THAT ACTUALLY FIRES IN THIS LEVEL. Falling into the void is
	# well past the uncontrolled height, so the ragdoll takes over while
	# health is still full -- the health threshold never gets a chance.
	var arena: Arena = await _arena_with(30.0)
	var player: Player = arena.player
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	await step(2)
	assert_true(arena.rescued_count > 0,
		"the ragdoll was allowed to take over in a level where she cannot die")

func test_falling_out_of_the_level_is_rescued_not_killed() -> void:
	var arena: Arena = await _arena_with(30.0)
	var player: Player = arena.player
	player.global_position = Vector3(0.0, arena.fall_out_height - 10.0, 0.0)
	await step(2)
	assert_true(arena.rescued_count > 0, "falling out of the level was not rescued")

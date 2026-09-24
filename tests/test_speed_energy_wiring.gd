extends ParkourTest

# Driven-state tests: a real player on a real floor, with input scripted
# rather than typed. Verifies that the curve actually governs ground speed --
# the component's own maths is already covered by test_speed_energy.gd.

func _world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	return world

func test_top_speed_is_not_reachable_in_one_second() -> void:
	# The first judgement criterion in the research's own checklist: if
	# holding forward for two seconds reaches full speed, it is not this game,
	# because speed stops being an asset that can be lost.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 60:
		await step(1)
	var speed: float = world["player"].horizontal_speed()
	assert_true(speed < 5.4, "one second of running already reached %f m/s" % speed)
	assert_gt(speed, 4.5, "one second of running did not even reach the 1.0 s knot")
	TestWorld.teardown(world)
	await step(1)

func test_seven_seconds_of_running_reaches_the_confirmed_top_speed() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 430:
		await step(1)
	assert_almost_eq(world["player"].horizontal_speed(), 7.2, 0.15, "did not reach 7.2 m/s")
	TestWorld.teardown(world)
	await step(1)

func test_stopping_bleeds_the_energy_back_off() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 430:
		await step(1)
	var banked: float = world["player"].speed_energy.energy
	assert_gt(banked, 6.5, "never banked a full budget")
	world["input"].state.move = Vector2.ZERO
	for i in 120:
		await step(1)
	assert_true(world["player"].speed_energy.energy < banked * 0.5, "energy survived two seconds of standing still")
	TestWorld.teardown(world)
	await step(1)

func test_the_walk_modifier_caps_speed_and_banks_almost_nothing() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	world["input"].state.walk_held = true
	for i in 180:
		await step(1)
	assert_true(world["player"].horizontal_speed() < 0.8, "the walk modifier did not cap speed")
	TestWorld.teardown(world)
	await step(1)

func test_energy_does_not_accumulate_while_shoved_against_a_wall() -> void:
	# The project-added guard: without it, holding forward into geometry for
	# seven seconds banks a full budget and hands it over the instant the
	# obstruction clears.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	await step(1)
	wall.global_position = Vector3(0.0, 2.0, -1.5)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
	assert_true(world["player"].speed_energy.energy < 1.0, "banked energy while going nowhere")
	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_energy_survives_a_jump_intact() -> void:
	# The headline claim of the airborne design (10.1 mechanic 2): speed
	# earned before take-off carries across the flight whole -- this is WHY
	# _update_speed_energy() returns early when not grounded. Pin it with a
	# driven-state assertion instead of resting entirely on that early return.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# A MID-curve level, not a full budget: a bug that let energy either
	# accumulate OR decay while airborne would show either direction.
	input.state.move = Vector2(0.0, 1.0)
	for i in 60:
		await step(1)
	var banked: float = player.speed_energy.energy
	var cap_before: float = player.speed_cap()
	assert_gt(banked, 0.1, "banked no energy before the jump -- test setup is wrong")
	var ceiling_energy: float = player.config.pawn.speed_curve[player.config.pawn.speed_curve.size() - 1].x
	assert_true(banked < ceiling_energy, "banked a full budget -- test setup is wrong, this must be a MID-curve level")

	input.press_jump()
	await step(1)
	assert_true(player.move_manager.current_name == Move.JUMP, "the jump did not leave the ground")

	var saw_airborne := false
	var last_airborne_energy := banked
	for i in 200:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
		saw_airborne = true
		assert_almost_eq(player.speed_energy.energy, banked, 0.0001, "energy moved while airborne")
		assert_almost_eq(player.speed_cap(), cap_before, 0.0001, "speed_cap() moved while airborne")
		last_airborne_energy = player.speed_energy.energy
	assert_true(saw_airborne, "never observed an airborne tick -- test setup is wrong")
	assert_almost_eq(last_airborne_energy, banked, 0.0001, "energy was not held intact across the whole flight")
	TestWorld.teardown(world)
	await step(1)

func test_energy_survives_a_coyote_jump_intact() -> void:
	# Same invariant as the test above, exercised through the THIRD take-off
	# site -- FallingMove's own consume_jump() branch, the coyote-time jump.
	# DO NOT let this site go untested just because it is easy to miss: it
	# opportunistically checks that the boost actually lands too, since that
	# is exactly the code this test exists to exercise.
	#
	# The coyote branch hands off to JUMP the same tick it fires, the same way
	# WalkingMove's own jump branch always has -- neither applies this tick's
	# gravity, since that belongs to JumpMove's own first physics_update() one
	# tick later.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	for i in 60:
		await step(1)
	var banked: float = player.speed_energy.energy
	assert_gt(banked, 0.1, "banked no energy before the drop -- test setup is wrong")

	# Simulate walking off a ledge (no jump key involved yet): teleport clear
	# of the floor, the same trick test_falling_move_integration.gd uses.
	player.global_position.y += 1.0
	await step(1)
	assert_true(player.move_manager.current_name == Move.FALLING, \
		"teleporting up did not send the player airborne -- test setup is wrong")
	var speed_before_takeoff: float = player.horizontal_speed()

	# Press jump WELL WITHIN the coyote window (config.pawn.coyote_time =
	# 0.12 s, ~7 ticks at this one tick in) so FallingMove's own
	# consume_jump() branch fires, not WalkingMove's.
	input.press_jump()
	await step(1)
	assert_true(player.move_manager.current_name == Move.JUMP, \
		"the coyote-time jump did not hand off to Jump")
	var expected_vy: float = player.config.pawn.base_jump_z
	assert_almost_eq(player.velocity.y, expected_vy, 0.05, \
		"velocity.y does not show a fresh coyote-jump impulse -- did the branch actually fire?")
	assert_gt(player.horizontal_speed(), speed_before_takeoff, \
		"jump_add_xy was not applied at the coyote-jump site")

	var saw_airborne := false
	var last_airborne_energy := banked
	for i in 200:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
		saw_airborne = true
		assert_almost_eq(player.speed_energy.energy, banked, 0.0001, "energy moved while airborne after a coyote jump")
		last_airborne_energy = player.speed_energy.energy
	assert_true(saw_airborne, "never observed an airborne tick -- test setup is wrong")
	assert_almost_eq(last_airborne_energy, banked, 0.0001, "energy was not held intact across a coyote-jump flight")
	TestWorld.teardown(world)
	await step(1)

func test_letting_go_brakes_the_budget_down_with_the_body() -> void:
	# A stop is a mistake paid for in full: once the body has braked to a
	# halt there is nothing left to tap W back into.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
	world["input"].state.move = Vector2.ZERO
	for i in 40:
		await step(1)
	assert_almost_eq(world["player"].horizontal_speed(), 0.0, 0.01, "test setup: never stopped")
	assert_lt(world["player"].speed_energy.energy, 0.05, "the budget outlived the stop")
	TestWorld.teardown(world)
	await step(1)

func test_running_into_a_wall_empties_the_budget() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	var player: Player = world["player"]
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
	assert_gt(player.speed_energy.energy, 3.0, "test setup: never banked")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	var ahead: Vector3 = -player.global_transform.basis.z
	wall.global_position = player.global_position + ahead * 1.5
	wall.look_at(player.global_position, Vector3.UP)
	for i in 30:
		await step(1)
	assert_lt(player.speed_energy.energy, 0.5, "the budget survived running into a wall")
	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)

extends ParkourTest

# DO NOT measure energy_accumulate_speed_ratio against the STANDING cap:
# CrouchMove holds the body to 40% of it, so a crouched run could never cross
# that threshold while turning keeps draining energy -- a one-way ratchet
# bottoming out at speed_min_base_velocity * crouched_pct = 0.04 m/s, with no
# route back except standing up.

func _world() -> Dictionary:
	return TestWorld.build(get_tree(), MovementConfig.new())

func test_a_crouched_run_can_still_bank_energy() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Drop straight into Crouch with no energy banked, which is the state a
	# drained player is in, and hold a direction.
	player.speed_energy.energy = 0.0
	player.move_manager.start(Move.CROUCH)
	input.state.move = Vector2(0.0, 1.0)
	input.state.crouch_held = true
	for i in 90:
		await step(1)

	assert_true(player.move_manager.current_name == Move.CROUCH, \
		"test setup is wrong: did not stay crouched")
	assert_gt(player.speed_energy.energy, 0.1, \
		"a crouched run banked no energy at all")
	assert_gt(player.horizontal_speed(), 0.05, \
		"a crouched run stayed pinned at the floor speed")

	TestWorld.teardown(world)
	await step(1)

func test_a_crouched_turn_does_not_ratchet_the_player_to_a_standstill() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)

	player.move_manager.start(Move.CROUCH)
	input.state.crouch_held = true
	# Six hard flicks: exactly the pattern that ratchets the budget to nothing
	# with no route back if energy accounting compares against the wrong cap.
	for f in 6:
		for i in 6:
			player.rotate_y(deg_to_rad(15.0))
			await step(1)
		for i in 30:
			await step(1)

	assert_true(player.move_manager.current_name == Move.CROUCH, "left the crouch")
	assert_gt(player.horizontal_speed(), 0.05, \
		"crouched turning ratcheted the player down to a standstill (%f m/s)" \
			% player.horizontal_speed())

	TestWorld.teardown(world)
	await step(1)

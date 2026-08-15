extends TestCase

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(10)
	world["config"] = cfg
	return world

func test_jump_leaves_the_ground() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	check(player.state_machine.current_name == &"Ground", "precondition: should start grounded")
	input.press_jump()
	await step(3)
	check(player.state_machine.current_name == &"Air", "jump did not enter Air")
	check_greater(player.velocity.y, 0.0, "jump did not produce upward velocity")

	TestWorld.teardown(world)
	await step(1)

func test_player_returns_to_ground_after_a_jump() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.press_jump()
	await step(3)
	input.release_jump()
	await step(180)

	check(player.state_machine.current_name == &"Ground", \
		"player never landed, state = %s" % player.state_machine.current_name)
	check_greater(player.last_landing_speed, 0.0, "landing speed was not recorded")

	TestWorld.teardown(world)
	await step(1)

func test_air_control_is_weaker_than_ground_control() -> void:
	var cfg := MovementConfig.new()

	# Ground run-up: how much speed is gained in 10 ticks from rest, grounded.
	var ground_world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(ground_world)
	await step(2)
	var ground_player: Player = ground_world["player"]
	ground_world["input"].state.move = Vector2(0.0, 1.0)
	await step(10)
	var ground_gain := ground_player.horizontal_speed()
	TestWorld.teardown(ground_world)
	await step(1)

	# Air run-up: same 10 ticks of forward input, but airborne from rest.
	var air_world := TestWorld.build(tree, cfg)
	await step(1)
	air_world["floor"].global_position = Vector3(0.0, -60.0, 0.0)
	air_world["player"].global_position = Vector3(0.0, 0.0, 0.0)
	await step(2)
	var air_player: Player = air_world["player"]
	air_world["input"].state.move = Vector2(0.0, 1.0)
	await step(10)
	var air_gain := air_player.horizontal_speed()
	TestWorld.teardown(air_world)
	await step(1)

	check_greater(ground_gain, air_gain, \
		"air control must be weaker than ground control (ground %f vs air %f)" % [ground_gain, air_gain])

func test_coyote_time_allows_a_jump_just_after_leaving_ground() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Force the player off the floor without jumping, then jump within the
	# coyote window.
	player.global_position = Vector3(0.0, 3.0, 0.0)
	await step(2)
	check(player.state_machine.current_name == &"Air", "precondition: should be airborne")

	input.press_jump()
	await step(1)
	check_greater(player.velocity.y, 0.0, "coyote jump did not fire")

	TestWorld.teardown(world)
	await step(1)

extends TestCase

# Landing is where the "speed is hard to earn, easy to lose" rule bites. These
# assert the ORDERING of outcomes, never the amounts, so tuning cannot break them.

func _airborne_world(cfg: MovementConfig, drop_height: float) -> Dictionary:
	var world := TestWorld.build(tree, cfg)
	await step(1)
	world["floor"].global_position = Vector3(0.0, -0.5, 0.0)
	world["player"].global_position = Vector3(0.0, drop_height, 0.0)
	await step(15)
	return world

## Runs the player up to speed on the ground, then drops it from `height` with
## crouch either held (roll) or not, and returns the horizontal speed on landing.
func _speed_after_drop(height: float, crouch: bool) -> float:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)

	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)

	# Lift the runner to the drop height without changing its horizontal motion.
	player.global_position = Vector3(player.global_position.x, height, player.global_position.z)
	await step(2)
	input.state.crouch_held = crouch

	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	var speed := player.horizontal_speed()
	TestWorld.teardown(world)
	await step(1)
	return speed

func test_a_plain_landing_costs_speed() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(90)
	var running_speed := player.horizontal_speed()

	player.global_position = Vector3(player.global_position.x, 12.0, player.global_position.z)
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check_greater(running_speed, player.horizontal_speed(), \
		"a plain landing from height must cost horizontal speed")
	TestWorld.teardown(world)
	await step(1)

func test_rolling_keeps_more_speed_than_a_plain_landing() -> void:
	await step(1)
	var plain := await _speed_after_drop(12.0, false)
	var rolled := await _speed_after_drop(12.0, true)
	check_greater(rolled, plain, "rolling must preserve more speed than landing flat")

func test_a_higher_fall_costs_more_speed() -> void:
	await step(1)
	var shallow := await _speed_after_drop(4.0, false)
	var deep := await _speed_after_drop(16.0, false)
	check_greater(shallow, deep, "a deeper fall must cost more speed than a shallow one")

func test_the_roll_flag_reports_which_landing_happened() -> void:
	await step(1)
	var cfg := MovementConfig.new()
	var world := await _airborne_world(cfg, 12.0)
	var player: Player = world["player"]
	world["input"].state.crouch_held = true
	for i in 400:
		await step(1)
		if player.state_machine.current_name == &"Ground":
			break
	check(player.last_landing_rolled, "a crouched landing from height should be flagged as a roll")
	TestWorld.teardown(world)
	await step(1)

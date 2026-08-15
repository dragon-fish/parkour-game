extends TestCase

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(15)
	return world

func test_player_starts_grounded() -> void:
	var world := await _spawn()
	check(world["player"].state_machine.current_name == &"Ground", \
		"player did not settle into Ground, got %s" % world["player"].state_machine.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_forward_input_accelerates_the_player() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	await step(30)

	check_greater(player.horizontal_speed(), 0.5, "player did not accelerate under forward input")
	TestWorld.teardown(world)
	await step(1)

func test_sprint_reaches_a_higher_speed_than_walk() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	await step(90)
	var walk_speed := player.horizontal_speed()

	input.state.sprint_held = true
	await step(90)
	var sprint_speed := player.horizontal_speed()

	check_greater(sprint_speed, walk_speed, "sprinting was not faster than walking")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_input_brings_the_player_to_rest() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	await step(60)
	check_greater(player.horizontal_speed(), 1.0, "precondition: player should be moving")

	input.state.move = Vector2.ZERO
	await step(60)
	check(player.horizontal_speed() < 0.2, \
		"friction did not stop the player, speed = %f" % player.horizontal_speed())
	TestWorld.teardown(world)
	await step(1)

func test_leaving_the_floor_edge_does_not_start_with_a_downward_jolt() -> void:
	var world := await _spawn()
	var player: Player = world["player"]

	# The test floor is a 200x200 slab; teleport the player just past its
	# edge without jumping, so GroundState's non-jump exit path (walking off
	# a ledge) is what fires, not the jump path.
	player.global_position.x = 150.0
	await step(2)

	check(player.state_machine.current_name == &"Air", \
		"precondition: should have left the floor, got %s" % player.state_machine.current_name)
	check(player.velocity.y > -1.0, \
		"leaving the floor edge produced a downward jolt, velocity.y = %f" % player.velocity.y)

	TestWorld.teardown(world)
	await step(1)

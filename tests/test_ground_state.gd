extends TestCase

const TICK := 1.0 / 60.0

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(10)
	world["config"] = cfg
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

class_name TestStandingJump
extends TestCase

# Measured in the original: a jump taken while running picks up about 4 km/h
# of horizontal speed, and a jump from a standstill picks up NOTHING. All
# three take-off sites used to add JumpAddXY unconditionally, so standing
# still and pressing jump drifted forward at 1 m/s.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_a_standing_jump_gains_no_horizontal_speed() -> void:
	var world := TestWorld.build(tree, MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	check(player.horizontal_speed() < 0.01, "test setup: not actually standing still")

	input.press_jump()
	await step(3)
	check(player.move_manager.current_name == Move.JUMP, "the standing jump never took off")
	check(player.horizontal_speed() < 0.01, \
		"a standing jump drifted forward at %.2f m/s" % player.horizontal_speed())

	TestWorld.teardown(world)
	await step(1)

func test_a_running_jump_still_gains_its_nudge() -> void:
	var world := TestWorld.build(tree, MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# Walk-modifier speed, low enough that the nudge is clearly visible against
	# it rather than lost in the noise of a full sprint.
	input.state.move = Vector2(0.0, 1.0)
	input.state.walk_held = true
	for i in 60:
		await step(1)
	var before: float = player.horizontal_speed()
	input.press_jump()
	await step(2)
	check(player.move_manager.current_name == Move.JUMP, "the running jump never took off")
	check_greater(player.horizontal_speed(), before + 0.2, \
		"a running jump lost its forward nudge (%.2f -> %.2f m/s)" \
			% [before, player.horizontal_speed()])

	TestWorld.teardown(world)
	await step(1)

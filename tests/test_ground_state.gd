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
	var cfg: MovementConfig = player.config

	# The test floor is a 200x200 slab; teleport the player just past its
	# edge without jumping, so GroundState's non-jump exit path (walking off
	# a ledge) is what fires, not the jump path.
	player.global_position.x = 150.0
	await step(2)

	check(player.state_machine.current_name == &"Air", \
		"precondition: should have left the floor, got %s" % player.state_machine.current_name)

	# GroundState must zero its downward floor-snap bias (velocity.y =
	# -floor_snap_speed) before handing off to Air, instead of letting Air
	# add gravity on top of a bias that was never cleared. Express the bound
	# against cfg rather than a literal number so raising gravity or
	# floor_snap_speed by hand in the F1 panel can never break this test.
	#
	# Correct behaviour after this test's exact step(2): the bias is cleared
	# on the tick the ledge is detected, so Air applies exactly one gravity
	# tick on top of zero: velocity.y = -g*t.
	# Regressed behaviour (the bias leaking into Air): velocity.y =
	# -(f + g*t), where f = floor_snap_speed.
	# A threshold of -(g*t + f/2) sits strictly between the two at ANY
	# tuning:
	#   correct passes:   -g*t        > -(g*t + f/2)  <=>  0  > -f/2   (true for any f > 0)
	#   regressed fails:  -(f + g*t)  > -(g*t + f/2)  <=>  -f > -f/2   (false for any f > 0)
	var tick := 1.0 / Engine.physics_ticks_per_second
	var jolt_threshold: float = -(cfg.gravity * tick + cfg.floor_snap_speed * 0.5)
	check(player.velocity.y > jolt_threshold, \
		"leaving the floor edge produced a downward jolt, velocity.y = %f (threshold %f)" \
			% [player.velocity.y, jolt_threshold])

	TestWorld.teardown(world)
	await step(1)

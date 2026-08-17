class_name TestTurnDeceleration
extends TestCase

func _world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func _run_up(world: Dictionary, ticks: int) -> void:
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in ticks:
		await step(1)

func test_turning_costs_banked_speed_energy() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	check_greater(before, 6.5, "never banked a full budget")
	# A hard left: the wish direction swings 90 degrees in one tick.
	world["input"].state.move = Vector2(-1.0, 0.0)
	await step(1)
	var after: float = world["player"].speed_energy.energy
	check(after < before - 3.0, "a 90 degree turn cost almost nothing (%f -> %f)" % [before, after])
	TestWorld.teardown(world)
	await step(1)

func test_running_straight_costs_nothing() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	for i in 60:
		await step(1)
	check_greater(world["player"].speed_energy.energy, before - 0.01, \
		"running in a straight line bled energy")
	TestWorld.teardown(world)
	await step(1)

func test_releasing_and_repressing_a_direction_is_not_a_turn() -> void:
	# wish_direction() returns the zero vector with no input. Treating the
	# transition through zero as a heading change would charge the player for
	# every momentary key release.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	var before: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2.ZERO
	await step(1)
	world["input"].state.move = Vector2(0.0, 1.0)
	await step(1)
	# One tick of no input does bleed a little through ordinary decay, but it
	# must be nothing like a turn's own cost.
	check_greater(world["player"].speed_energy.energy, before - 0.5, \
		"passing through zero input was charged as a turn")
	TestWorld.teardown(world)
	await step(1)

func test_turning_in_the_air_is_free() -> void:
	# Turn cost is a ground mechanic: air_control is 0.025, so there is barely
	# any turning to charge for, and charging for it would double-punish a
	# jump the player is already committed to.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	world["input"].press_jump()
	await step(1)
	world["input"].release_jump()
	for i in 10:
		await step(1)
	var before: float = world["player"].speed_energy.energy
	world["input"].state.move = Vector2(-1.0, 0.0)
	for i in 10:
		await step(1)
	check_approx(world["player"].speed_energy.energy, before, 0.01, "turning in the air cost energy")
	TestWorld.teardown(world)
	await step(1)

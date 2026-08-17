class_name TestSpeedEnergyWiring
extends TestCase

# Driven-state tests: a real player on a real floor, with input scripted
# rather than typed. Verifies that the curve actually governs ground speed --
# the component's own maths is already covered by test_speed_energy.gd.

func _world() -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
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
	check(speed < 5.4, "one second of running already reached %f m/s" % speed)
	check_greater(speed, 4.5, "one second of running did not even reach the 1.0 s knot")
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
	check_approx(world["player"].horizontal_speed(), 7.2, 0.15, "did not reach 7.2 m/s")
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
	check_greater(banked, 6.5, "never banked a full budget")
	world["input"].state.move = Vector2.ZERO
	for i in 120:
		await step(1)
	check(world["player"].speed_energy.energy < banked * 0.5, "energy survived two seconds of standing still")
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
	check(world["player"].horizontal_speed() < 0.8, "the walk modifier did not cap speed")
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
	tree.root.add_child(wall)
	await step(1)
	wall.global_position = Vector3(0.0, 2.0, -1.5)
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in 300:
		await step(1)
	check(world["player"].speed_energy.energy < 1.0, "banked energy while going nowhere")
	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)

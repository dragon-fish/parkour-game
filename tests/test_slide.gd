class_name TestSlide
extends TestCase

func _world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func _run_up(world: Dictionary, ticks: int) -> void:
	world["input"].state.move = Vector2(0.0, 1.0)
	for i in ticks:
		await step(1)

func test_entering_a_slide_never_adds_speed() -> void:
	# The single behavioural difference from this project's old slide, and the
	# one that changes what the whole level teaches: the original has no
	# acceleration term anywhere in TdMove_Slide.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	var before: float = world["player"].horizontal_speed()
	world["input"].press_crouch()
	await step(1)
	await step(1)
	check(world["player"].horizontal_speed() <= before + 0.001, \
		"the slide added speed (%f -> %f)" % [before, world["player"].horizontal_speed()])
	TestWorld.teardown(world)
	await step(1)

func test_chaining_slides_cannot_ratchet_speed_upward() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	var peak: float = world["player"].horizontal_speed()
	for cycle in 6:
		world["input"].press_crouch()
		for i in 20:
			await step(1)
		world["input"].release_crouch()
		for i in 20:
			await step(1)
		peak = maxf(peak, world["player"].horizontal_speed())
	check(peak <= world["player"].config.pawn.ground_speed + 0.01, \
		"chained slides climbed past the ground ceiling (%f)" % peak)
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_ends_once_speed_decays_to_the_abort_speed() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 200)
	world["input"].press_crouch()
	await step(1)
	world["input"].state.move = Vector2.ZERO
	for i in 240:
		await step(1)
	check(world["player"].move_manager.current_name != Move.SLIDE, \
		"the slide never ended")
	TestWorld.teardown(world)
	await step(1)

func test_a_slide_cannot_outlast_the_abort_time() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(2)
	await _run_up(world, 430)
	world["input"].press_crouch()
	await step(1)
	# SlideAbortTime = 2.0 s. Give it a generous margin and it must be gone.
	for i in 150:
		await step(1)
	check(world["player"].move_manager.current_name != Move.SLIDE, \
		"the slide outlasted SlideAbortTime")
	TestWorld.teardown(world)
	await step(1)

func test_the_slide_declares_the_confirmed_friction_multiplier() -> void:
	var config := MovementConfig.new()
	check_approx(config.slide.friction_modifier, 0.1, 0.0001, \
		"slide friction_modifier is not the confirmed 0.1")

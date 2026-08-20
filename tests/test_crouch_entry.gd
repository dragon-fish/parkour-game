extends ParkourTest

# WalkingMove's own table has always listed "grounded, not moving -> Crouch"
# as one of GBA_Crouch's five outlets, but no code implemented that row: a
# press below the slide entry speed short-circuited and was left buffered, so
# standing still and pressing crouch did nothing whatsoever.

func _world() -> Dictionary:
	return TestWorld.build(get_tree(), MovementConfig.new())

func test_pressing_crouch_while_standing_crouches() -> void:
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	assert_true(player.move_manager.current_name == Move.WALKING, "test setup: not walking")
	assert_true(player.horizontal_speed() < player.config.slide.slide_abort_speed, \
		"test setup: moving too fast for this to be the standing case")

	input.press_crouch()
	await step(3)
	assert_true(player.move_manager.current_name == Move.CROUCH, \
		"crouching from a standstill did nothing")

	input.release_crouch()
	await step(5)
	assert_true(player.move_manager.current_name == Move.WALKING, \
		"releasing crouch did not stand back up")

	TestWorld.teardown(world)
	await step(1)

func test_a_fast_crouch_still_slides_rather_than_crouching() -> void:
	# The other half: the new branch must not have stolen the slide.
	var world := _world()
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	for i in 120:
		await step(1)
	assert_gt(player.horizontal_speed(), player.config.slide.slide_abort_speed, \
		"test setup: never got up to slide speed")

	input.press_crouch()
	await step(3)
	assert_true(player.move_manager.current_name == Move.SLIDE, \
		"a crouch at speed no longer opens a slide")

	TestWorld.teardown(world)
	await step(1)

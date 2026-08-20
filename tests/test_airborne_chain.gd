extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

func _airborne_world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	return world

func test_a_jump_starts_in_the_jump_state() -> void:
	var world := _airborne_world()
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	world["input"].press_jump()
	await step(2)
	assert_true(player.move_manager.current_name == Move.JUMP, \
		"leaving the ground did not enter Jump (got %s)" % player.move_manager.current_name)
	TestWorld.teardown(world)
	await step(1)

func test_jump_becomes_falling_at_the_measured_threshold() -> void:
	# I3: 单行线。速度掉破 EnterToFallingZSpeed 即转 Falling，且不可逆。
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	world["input"].press_jump()
	await step(2)
	assert_true(player.move_manager.current_name == Move.JUMP, "test setup: not in Jump")
	for i in 200:
		await step(1)
		if player.move_manager.current_name != Move.JUMP:
			break
	assert_true(player.move_manager.current_name == Move.FALLING, \
		"Jump never handed off to Falling")
	assert_gt(cfg.pawn.enter_to_falling_z_speed + 0.5, player.velocity.y, \
		"handed off before the descent threshold")
	TestWorld.teardown(world)
	await step(1)

extends ParkourTest

# DEBUG CHEAT. Not a game mechanic -- it exists because this project has no
# checkpoints, so reaching a spot deep in a level otherwise means replaying the
# whole route to it. Pinned anyway, because the two things it must not do are
# both easy to break: leave collision on, and leave the fall counter armed.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_noclip_flies_along_the_view_and_ignores_geometry() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	# A wall dead ahead, tall enough that nothing could vault or step it.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	wall.global_position = Vector3(0.0, 3.0, player.global_position.z - 3.0)
	await step(1)

	player.toggle_noclip()
	assert_true(player.noclip, "T did not turn noclip on")
	input.state.move = Vector2(0.0, 1.0)
	var start_z: float = player.global_position.z
	await step(60)

	# One second at NOCLIP_SPEED, straight through where the wall is.
	var travelled: float = start_z - player.global_position.z
	assert_gt(travelled, Player.NOCLIP_SPEED * 0.8, \
		"noclip did not fly at anything like its own speed (%.2f m)" % travelled)
	assert_true(player.global_position.z < wall.global_position.z - 0.5, \
		"noclip was stopped by geometry it is supposed to pass through")
	assert_true(player.move_manager.current_name == Move.WALKING, \
		"noclip left the move manager somewhere other than Walking")

	wall.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_the_flight_itself_is_not_counted_as_a_fall() -> void:
	# The counter measures from the last launch point, so a flight up to the
	# rooftops and back down would otherwise be scored as a drop from the
	# rooftops -- an instant death the moment the cheat is switched off.
	#
	# NOT a claim that noclip makes the player immune: switching it off while
	# genuinely high up SHOULD kill on landing, which the second half checks.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var ground_y: float = player.global_position.y

	var died := {"hit": false}
	player.died_from_fall.connect(func() -> void: died["hit"] = true)

	# Up to the rooftops and back down, all under noclip.
	player.toggle_noclip()
	player.global_position.y = ground_y + cfg.pawn.falling_uncontrolled_height + 20.0
	await step(5)
	player.global_position.y = ground_y + 0.3
	await step(5)
	player.toggle_noclip()

	for i in 120:
		await step(1)
		if player.grounded and player.move_manager.current_name == Move.WALKING:
			break
	assert_true(not died["hit"], 		"the noclip flight itself was scored as a fatal fall")

	TestWorld.teardown(world)
	await step(1)

func test_noclip_does_not_make_a_real_fall_survivable() -> void:
	# The other side of the same coin: the reset must not leave the player
	# permanently immune to the drop they are actually in.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	var died := {"hit": false}
	player.died_from_fall.connect(func() -> void: died["hit"] = true)

	player.toggle_noclip()
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 20.0
	await step(5)
	player.toggle_noclip()

	for i in 400:
		await step(1)
		if died["hit"]:
			break
	assert_true(died["hit"], 		"a genuine fall after noclip did not kill -- the counter never re-armed")

	TestWorld.teardown(world)
	await step(1)

func test_jump_and_crouch_fly_straight_up_and_down() -> void:
	# Altitude as its own control, independent of where the view points --
	# aiming at a rooftop and holding forward is much fiddlier than just
	# rising to it.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	player.toggle_noclip()
	var start_y: float = player.global_position.y

	input.state.jump_held = true
	await step(30)
	var risen: float = player.global_position.y - start_y
	assert_gt(risen, Player.NOCLIP_SPEED * 0.4, \
		"holding jump under noclip did not climb (%.2f m)" % risen)

	input.state.jump_held = false
	input.state.crouch_held = true
	var top_y: float = player.global_position.y
	await step(15)
	assert_true(player.global_position.y < top_y - 1.0, \
		"holding crouch under noclip did not descend")

	input.state.crouch_held = false
	player.toggle_noclip()
	TestWorld.teardown(world)
	await step(1)

extends ParkourTest

# I1/I2/I4 (spec §3). Uncontrolled falling is a STATE, not a flag.
# [ME:CONFIRMED] The original gives it ControllerState = PlayerDying and
# strips every probe except soft landing, so nothing the player does can
# convert it into a grab, a vault or a wall run. A boolean cannot enforce
# that -- the probes simply keep running.

const TestWorld = preload("res://tests/world_fixture.gd")

func _falling_world() -> Dictionary:
	return TestWorld.build(get_tree(), MovementConfig.new())

func test_a_deep_fall_enters_the_uncontrolled_state() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 3.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	assert_true(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"a fall past the threshold did not enter FallUncontrolled")
	TestWorld.teardown(world)
	await step(1)

func test_the_uncontrolled_state_runs_no_probes() -> void:
	# I1. The config is the enforcement point, so assert it directly: a future
	# edit that switches one of these back on fails here rather than being
	# discovered as "I grabbed a ledge while dying".
	var cfg := MovementConfig.new()
	assert_true(not cfg.fall_uncontrolled.check_for_grab, "uncontrolled falling can grab")
	assert_true(not cfg.fall_uncontrolled.check_for_vault_over, "uncontrolled falling can vault")
	assert_true(not cfg.fall_uncontrolled.check_for_wall_climb, "uncontrolled falling can wall run")

func test_it_is_a_one_way_door() -> void:
	# I4. Regaining height mid-air must not hand control back.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 3.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	assert_true(player.move_manager.current_name == Move.FALL_UNCONTROLLED, "test setup: never entered")
	player.velocity.y = 8.0
	await step(5)
	assert_true(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"climbing back up escaped the uncontrolled state")
	TestWorld.teardown(world)
	await step(1)

func test_the_screen_shows_the_fall_and_shows_how_bad_it_is() -> void:
	# spec §6. Crossing the 10 m line must be visibly distinct from an
	# ordinary fall you could still walk away from -- the screen must start
	# reading before impact, not only go grey on impact, when there would be
	# nothing left to tell the player. This is what spec §4's deviation 3
	# ("the player cannot see what happened") requires.
	#
	# The reading is by SPEED, not by elapsed time, which is what makes a 40 m
	# drop look worse than one that barely cleared the line -- so this asserts
	# the RELATIONSHIP (faster is stronger), not the particular curve.
	#
	# Verified to go red both ways: with _drive_screen_effects() removed the
	# first check below fails, and with the clearing exit() removed the last
	# two do.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	assert_true(player.screen_effects != null, \
		"test setup is wrong: this player has no ScreenEffects to drive")

	# Lifted far higher than the threshold needs, so the readings below are all
	# taken with plenty of fall still left rather than racing the ground.
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 60.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	assert_true(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"test setup is wrong: the staged fall never entered FallUncontrolled")

	# Roughly the speed a fall reaches at the 10 m line.
	player.velocity.y = -18.0
	await step(1)
	var near_the_line: float = player.screen_effects.desaturation
	var near_the_line_blur: float = player.screen_effects.blur
	assert_gt(near_the_line, 0.0, \
		"losing control showed nothing on screen at all")

	# Roughly the speed a 40 m drop reaches.
	player.velocity.y = -36.0
	await step(1)
	assert_gt(player.screen_effects.desaturation, near_the_line, \
		"a much faster fall did not desaturate any harder")
	assert_gt(player.screen_effects.blur, near_the_line_blur, \
		"a much faster fall did not blur any harder")

	# Ride it into the ground. Nothing here listens for died_from_fall (that is
	# Arena's job, and there is no Arena in this world), so whatever the state
	# leaves behind on its way out is what stays on screen.
	for i in 600:
		await step(1)
		if player.move_manager.current_name != Move.FALL_UNCONTROLLED:
			break
	assert_true(player.move_manager.current_name != Move.FALL_UNCONTROLLED, \
		"test setup is wrong: the fall never reached the ground")
	assert_almost_eq(player.screen_effects.desaturation, 0.0, 0.0001, \
		"the fall left the screen desaturated after it ended")
	assert_almost_eq(player.screen_effects.blur, 0.0, 0.0001, \
		"the fall left the screen blurred after it ended")

	TestWorld.teardown(world)
	await step(1)

func test_the_view_stops_responding_the_moment_control_is_lost() -> void:
	# [ME:CONFIRMED] ControllerState = PlayerDying, and the CDO for this move
	# carries no bConstrainLook at all -- the original's view does not stop
	# because the MOVE clamps it, but because the CONTROLLER stops reading
	# input. Player's input gate is that layer: ignoring `_input` inside the
	# move is not enough, because the camera is driven from
	# Player._physics_process().
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	# High enough that the flick below finishes well before touchdown: the
	# gate is released on exit, so a test that lands mid-flick would measure
	# the free view of the tick AFTER the fall, not the locked view during it.
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 40.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	assert_true(player.move_manager.current_name == Move.FALL_UNCONTROLLED, "test setup: never entered")

	var yaw_before: float = player.rotation.y
	# A hard sustained flick must not spin the view at all while control is
	# lost.
	for i in 20:
		input.state.look = Vector2(400.0, 0.0)
		await step(1)
	assert_true(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"test setup: landed before the flick finished")
	assert_almost_eq(player.rotation.y, yaw_before, 0.0001, \
		"the view still turned while control was already lost")

	TestWorld.teardown(world)
	await step(1)

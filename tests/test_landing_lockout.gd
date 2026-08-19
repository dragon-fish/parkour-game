class_name TestLandingLockout
extends TestCase

# ✅ 2.00 s is MEASURED, not designed: six hard landings in the original,
# timed from the last Falling frame to the first Walking frame, read
# 2.03 / 2.00 / 2.00 / 2.00 / 2.00 / 2.02 (spec §时间轴).

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_lockout_is_the_measured_two_seconds() -> void:
	var cfg := MovementConfig.new()
	check_approx(cfg.landing.lockout_time, 2.0, 0.0001, \
		"the hard-landing lockout is not the measured 2.00 s")

func test_a_hard_unrolled_landing_enters_landing() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	# Above hard_landing_height, below the death threshold, no roll input.
	player.global_position.y += cfg.pawn.hard_landing_height + 1.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.LANDING:
			break
	check(player.move_manager.current_name == Move.LANDING, \
		"a hard unrolled landing did not enter Landing")
	TestWorld.teardown(world)
	await step(1)

func test_a_soft_landing_skips_it_entirely() -> void:
	# Below hard_landing_height there is no penalty at all (03 §3.1), so there
	# must be no lockout either.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position.y += cfg.pawn.hard_landing_height - 2.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	for i in 240:
		await step(1)
		if player.grounded and player.move_manager.current_name != Move.FALLING:
			break
	check(player.move_manager.current_name != Move.LANDING, \
		"a landing below the hard threshold was locked out")
	TestWorld.teardown(world)
	await step(1)

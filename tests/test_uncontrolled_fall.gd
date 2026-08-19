class_name TestUncontrolledFall
extends TestCase

# I1/I2/I4 (spec §3). Uncontrolled falling is a STATE, not a flag: the original
# gives it ControllerState = PlayerDying and strips every probe except soft
# landing, so nothing the player does can convert it into a grab, a vault or a
# wall run. A boolean cannot enforce that -- the probes simply keep running.

const TestWorld = preload("res://tests/world_fixture.gd")

func _falling_world() -> Dictionary:
	return TestWorld.build(tree, MovementConfig.new())

func test_a_deep_fall_enters_the_uncontrolled_state() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
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
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"a fall past the threshold did not enter FallUncontrolled")
	TestWorld.teardown(world)
	await step(1)

func test_the_uncontrolled_state_runs_no_probes() -> void:
	# I1. The config is the enforcement point, so assert it directly: a future
	# edit that switches one of these back on fails here rather than being
	# discovered as "I grabbed a ledge while dying".
	var cfg := MovementConfig.new()
	check(not cfg.fall_uncontrolled.check_for_grab, "uncontrolled falling can grab")
	check(not cfg.fall_uncontrolled.check_for_vault_over, "uncontrolled falling can vault")
	check(not cfg.fall_uncontrolled.check_for_wall_climb, "uncontrolled falling can wall run")

func test_it_is_a_one_way_door() -> void:
	# I4. Regaining height mid-air must not hand control back.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
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
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, "test setup: never entered")
	player.velocity.y = 8.0
	await step(5)
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"climbing back up escaped the uncontrolled state")
	TestWorld.teardown(world)
	await step(1)

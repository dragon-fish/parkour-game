extends ParkourTest

# A temporary gravity multiplier for free flight. ✅ The research doc (05 §5.4):
# 局部重力修改在ME里反复出现（swing、barge、coil），是它"飘但可控"的重要来源，
# Godot 复刻务必保留这个手法. Built player-level once, consumed by the airborne
# gravity sites, so swing/barge/coil never each grow their own copy.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _airborne_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.global_position.y += 6.0
	player.move_manager.start(Move.FALLING)
	await step(1)
	return player

func test_the_window_scales_gravity_and_expires() -> void:
	var player: Player = await _airborne_player()
	var g: float = player.config.pawn.gravity
	assert_almost_eq(player.effective_gravity(), g, 0.001, "no window, yet gravity is scaled")
	player.apply_gravity_window(0.75, 0.5)
	assert_almost_eq(player.effective_gravity(), g * 0.75, 0.001, "the window did not scale gravity")
	await step(int(0.5 * 60.0) + 2)
	assert_almost_eq(player.effective_gravity(), g, 0.001, "the window never expired")

func test_a_falling_body_actually_falls_slower_under_the_window() -> void:
	# The consumer, not just the accessor: two identical drops, one windowed,
	# compared by velocity gained over the same ticks.
	var player: Player = await _airborne_player()
	await step(10)
	var plain_gain: float = -player.velocity.y
	TestWorld.teardown(_world)
	_world = {}
	await step(1)
	player = await _airborne_player()
	player.apply_gravity_window(0.5, 2.0)
	await step(10)
	var windowed_gain: float = -player.velocity.y
	assert_almost_eq(windowed_gain, plain_gain * 0.5, plain_gain * 0.1,
		"10 windowed ticks gained %.2f m/s against %.2f plain" % [windowed_gain, plain_gain])

func test_reset_clears_the_window() -> void:
	var player: Player = await _airborne_player()
	player.apply_gravity_window(0.5, 5.0)
	player.reset_state()
	assert_almost_eq(player.effective_gravity(), player.config.pawn.gravity, 0.001,
		"a respawn carried the old life's gravity window")

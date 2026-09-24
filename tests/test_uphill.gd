extends ParkourTest

# Running up an incline: the flat speed is kept rather than projected away, and
# the budget bleeds to base speed (PawnConfig.uphill_bleed_angle_deg).

const TestWorld = preload("res://tests/world_fixture.gd")
const INCLINE_DEG := 35.0

var _world: Dictionary = {}

func after_each() -> void:
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

func _on_the_slope() -> Player:
	_world = TestWorld.build_on_slope(get_tree(), MovementConfig.new(), deg_to_rad(INCLINE_DEG))
	await step(30)
	var player: Player = _world["player"]
	player.speed_energy.energy = 7.0
	_world["input"].state.move = Vector2(0.0, 1.0)  # forward is uphill here
	return player

func test_running_uphill_travels_at_the_speed_it_reports() -> void:
	var player: Player = await _on_the_slope()
	await step(20)
	var from: Vector3 = player.global_position
	var reported := 0.0
	for i in 30:
		await step(1)
		reported += player.horizontal_speed()
	var travelled: float = Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	var expected: float = reported / 60.0
	assert_gt(player.global_position.y, from.y + 0.5, "test setup: the body did not climb")
	assert_gt(travelled, expected * 0.9,
		"the slope took the flat speed away: %.2f m travelled against %.2f reported" % [travelled, expected])

func test_running_uphill_bleeds_to_base_speed_and_no_further() -> void:
	var player: Player = await _on_the_slope()
	await step(240)  # past the 3 s decay
	assert_almost_eq(player.speed_cap(), player.config.pawn.speed_max_base_velocity, 0.15,
		"the climb did not settle the ceiling at base speed")

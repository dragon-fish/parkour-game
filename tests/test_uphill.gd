extends ParkourTest

# Running up an incline: the flat speed is kept rather than projected away --
# the walking physics rebuilds the velocity from the horizontal displacement
# and steps up the slope (PawnPhysics.phys_walking).

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


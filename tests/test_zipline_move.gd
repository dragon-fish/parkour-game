extends ParkourTest

# 05 §5.5: caught from the air, ridden with no speed cap, left by crouching.
# Numbers are not asserted (they are the CDO's, and tunable); shapes are.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _line: InterestLine = null

func after_each() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

## A straight cable from `from` to `to`, world space.
func _cable(from: Vector3, to: Vector3) -> InterestLine:
	var line := InterestLine.new()
	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	line.curve = curve
	get_tree().root.add_child(line)
	return line

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## Jump apex is ~0.98 m above the standing centre (0.95), so a cable at 2.3
## is inside reach_radius (0.6) at the top of a standing jump.
const CABLE_Y := 2.3

## Jumps under a level 12 m cable running +z and waits to be hanging.
func _riding_player() -> Player:
	var player: Player = await _standing_player()
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y, 11.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the cable")
	return player

func test_walking_through_the_volume_does_not_catch_it() -> void:
	var player: Player = await _standing_player()
	# Low enough that the standing capsule is inside the volume.
	_line = _cable(Vector3(0.0, 1.3, -3.0), Vector3(0.0, 1.3, 3.0))
	await step(10)
	assert_ne(player.move_manager.current_name, Move.ZIPLINE, \
		"a zipline may only be caught from the air")

func test_jumping_into_the_volume_catches_it() -> void:
	var player: Player = await _riding_player()
	assert_eq(player.move_manager.current_name, Move.ZIPLINE)
	assert_false(player.grounded, "riding a cable is not standing on the ground")

func test_the_body_hangs_below_the_cable() -> void:
	var player: Player = await _riding_player()
	await step(12)  # past fade_in_time
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var cable_at: Vector3 = _line.sample(zip.ride_offset())["position"]
	assert_almost_eq(player.global_position.y, cable_at.y - player.config.zipline.hang_offset, 0.02, \
		"the body is not hanging hang_offset below the cable")
	assert_almost_eq(player.global_position.x, cable_at.x, 0.02)
	assert_almost_eq(player.global_position.z, cable_at.z, 0.02)

func test_falling_too_fast_cannot_catch_it() -> void:
	var player: Player = await _standing_player()
	_line = _cable(Vector3(0.0, 4.0, -3.0), Vector3(0.0, 4.0, 3.0))
	# From 12 m the body passes the cable at ~15 m/s, well over fall_limit.
	player.global_position = Vector3(0.0, 12.0, 0.0)
	var caught := false
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			caught = true
	assert_false(caught, "a body falling faster than fall_limit must not catch the cable")

func test_the_ride_travels_away_from_the_end_it_was_caught_at() -> void:
	var player: Player = await _riding_player()
	var before: float = player.global_position.z
	await step(20)
	assert_gt(player.global_position.z, before + 0.3, "the ride did not move along the cable")

func test_speed_never_drops_below_the_floor_and_keeps_rising() -> void:
	var player: Player = await _riding_player()
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var cfg: ZiplineConfig = player.config.zipline
	assert_true(zip.ride_speed() >= cfg.min_velocity - 0.001, "the ride started under min_velocity")
	var earlier: float = zip.ride_speed()
	await step(20)
	assert_gt(zip.ride_speed(), earlier, "a level cable must still accelerate (min_acceleration)")

func test_a_downhill_cable_accelerates_harder_than_a_level_one() -> void:
	var player: Player = await _riding_player()
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var level_accel: float = zip.ride_acceleration()
	_line.queue_free()
	TestWorld.teardown(_world)
	_world = {}
	await step(1)
	player = await _standing_player()
	# 30 degrees down over 12 m of run.
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y - 12.0 * tan(deg_to_rad(30.0)), 11.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the sloped cable")
	zip = player.move_manager.move_for(Move.ZIPLINE)
	assert_gt(zip.ride_acceleration(), level_accel + 0.5, "slope did not add acceleration")

func test_the_body_faces_along_the_cable() -> void:
	var player: Player = await _riding_player()
	await step(12)
	# The cable runs +z; Godot's forward is -z, so facing +z is yaw PI.
	assert_almost_eq(absf(wrapf(player.rotation.y, -PI, PI)), PI, 0.02, \
		"the body is not facing along the cable")

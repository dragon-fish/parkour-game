extends ParkourTest

# Q part-way up a wall kick (TdMove_180Turn): spin to face back the way you
# came, hang there for DisableMovementTime, and either kick off the wall or
# drop. The hang is the feature -- DisableMovementTime is a real field across
# the original's move library that this project had never implemented.

const TestWorld = preload("res://tests/world_fixture.gd")

## Freed after every test. Without this the walls pile up in the shared scene
## root and the NEXT test's run-up meets geometry it never placed -- which is
## how a clean per-file run and a broken full-suite run happen at once.
var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	if _world.has("wall"):
		(_world["wall"] as Node).queue_free()
	TestWorld.teardown(_world)
	_world = {}


func _world_with_wall_ahead(height: float) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, height, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	# Base resting ON the floor (whose top is y = 0), so `height` is the wall's
	# real height above the ground and a test can reason about it directly.
	wall.global_position = Vector3(0.0, height * 0.5, -2.5)
	world["wall"] = wall
	_world = world
	return world

## Runs the player into the wall, waits for the climb, then presses Q.
func _turning(world: Dictionary) -> Player:
	var player: Player = world["player"]
	player.global_position = Vector3(0.0, 1.5, -1.55)
	player.velocity = Vector3(0.0, 2.0, -6.0)
	player.move_manager.start(Move.JUMP)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_CLIMB, \
		"the climb never started, so there is nothing to turn out of")
	(world["input"] as ScriptedInputSource).press_turn()
	await step(1)
	return player

# --- the confirmed numbers ---------------------------------------------------

func test_the_confirmed_values_are_in_place() -> void:
	var config := MovementConfig.new()
	assert_almost_eq(config.turn_180.disable_movement_time, 0.3, 0.0001, \
		"DisableMovementTime is not 0.3")
	assert_almost_eq(config.turn_180.redo_move_time, 0.5, 0.0001, "RedoMoveTime is not 0.5")
	assert_almost_eq(config.turn_180.friction_modifier, 0.3, 0.0001, \
		"FrictionModifier is not 0.3")
	assert_almost_eq(config.turn_180.wall_kick_speed_out, 3.0, 0.0001, \
		"WallKickVelocity2D is not 300 uu/s")
	assert_almost_eq(config.turn_180.wall_kick_speed_up, 5.8, 0.0001, \
		"WallKickVelocityZ is not 580 uu/s")

func test_the_view_is_clamped_to_the_confirmed_fan() -> void:
	# MinLookConstraint = (-10000, -16384, 0): -16384 of 65536 is a quarter
	# turn, and 10000 is 55 degrees.
	var config := MovementConfig.new()
	assert_true(config.turn_180.constrain_look, "the turn does not clamp the view at all")
	assert_almost_eq(config.turn_180.max_look_constraint.x, deg_to_rad(55.0), 0.001, \
		"the pitch clamp is not 55 degrees")
	assert_almost_eq(config.turn_180.max_look_constraint.y, deg_to_rad(90.0), 0.001, \
		"the yaw clamp is not 90 degrees")

# --- entry and the window ----------------------------------------------------

func test_q_during_a_climb_starts_the_turn() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"Q during a wall climb did not start the turn")

func test_the_body_holds_still_for_the_whole_window() -> void:
	# "During which you are not subject to gravity" -- the owner's own
	# description, and DisableMovementTime is the field behind it. A body still
	# carrying its climb would leave the window before the window ended.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	var held := player.global_position
	await step(10)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"the turn ended early -- the window is 0.3 s, which is 18 ticks")
	assert_almost_eq(player.velocity.length(), 0.0, 0.0001, \
		"the body was still moving inside the window")
	assert_almost_eq(player.global_position.distance_to(held), 0.0, 0.0001, \
		"the body drifted inside the window")

func test_the_body_comes_all_the_way_round() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	var facing_before := player.rotation.y
	# turn_time is 0.2 s, which is 12 ticks; 15 leaves margin without reaching
	# the 18-tick end of the window.
	await step(15)
	var turned: float = absf(wrapf(player.rotation.y - facing_before, -PI, PI))
	assert_almost_eq(turned, PI, 0.02, "the body did not come round half a turn")

func test_letting_the_window_lapse_drops_the_player() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	await step(25)
	assert_eq(player.move_manager.current_name, Move.FALLING, \
		"the window lapsed without handing back to a fall")

# --- the kick ----------------------------------------------------------------

func test_space_inside_the_window_kicks_off_the_wall() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	await step(14)
	(world["input"] as ScriptedInputSource).press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"space inside the window did not kick off the wall")
	assert_almost_eq(player.velocity.y, player.config.turn_180.wall_kick_speed_up, 0.35, \
		"the kick did not leave at WallKickVelocityZ")

func test_the_kick_throws_the_player_away_from_the_wall() -> void:
	# The wall is at -Z and the player has turned to face +Z, so the kick has
	# to send them the way they are now looking. Getting this backwards would
	# fire them into the wall they just turned away from.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	await step(14)
	(world["input"] as ScriptedInputSource).press_jump()
	await step(1)
	assert_gt(player.velocity.z, 0.0, "the kick sent the player back into the wall")

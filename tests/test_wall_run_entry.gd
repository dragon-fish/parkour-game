class_name TestWallRunEntry
extends TestCase

# Task 11: wall running has no duration cap anymore -- a run ends when
# horizontal speed decays past wall_running_min_speed, when vertical speed
# falls past wall_running_velocity_stop_limit, or on touching the ground.
# Duration is momentum's business, exactly like the original.

const TestWorld = preload("res://tests/world_fixture.gd")

func _world_with_wall(wall_yaw: float) -> Dictionary:
	var world := TestWorld.build(tree, MovementConfig.new())
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	tree.root.add_child(wall)
	world["wall"] = wall
	world["wall_yaw"] = wall_yaw
	return world

func test_a_wall_run_has_no_duration_cap() -> void:
	# The original has no such parameter: TdMove_WallRun's own listing has
	# entry conditions, friction, acceleration and deceleration, and no time
	# limit anywhere. Duration is momentum's business.
	var config := MovementConfig.new()
	for property in config.wall_run.get_property_list():
		check(not String(property.name).contains("duration"), \
			"a duration cap survived on WallRunConfig: %s" % property.name)

func test_the_confirmed_entry_thresholds_are_in_place() -> void:
	var config := MovementConfig.new()
	check_approx(config.wall_run.wall_running_min_speed, 2.0, 0.0001, "min speed is not 200 uu/s")
	check_approx(config.wall_run.wall_running_forward_max_start_angle, deg_to_rad(57.0), 0.001, \
		"forward entry angle is not 57 degrees")
	check_approx(config.wall_run.wall_running_strafe_start_angle, deg_to_rad(60.0), 0.001, \
		"strafe entry angle is not 60 degrees")
	check_approx(config.wall_run.redo_move_time, 0.15, 0.0001, "RedoMoveTime is not 0.15")
	check_approx(config.wall_run.wall_running_horisontal_friction, 0.05, 0.0001, \
		"wall friction is not 0.05")

func test_a_faster_entry_stays_on_the_wall_longer() -> void:
	# The whole point of removing the timer: speed has to buy something on the
	# wall, and duration is what it buys.
	var slow := await _measure_wall_ticks(4.0)
	var fast := await _measure_wall_ticks(7.0)
	check_greater(fast, slow, "a faster entry did not last longer (%d vs %d ticks)" % [fast, slow])

## Drives a player into a wall at `entry_speed` and returns how many ticks the
## wall run lasted. Implemented with a direct velocity assignment rather than
## by running the speed curve up first, so the two cases differ ONLY in entry
## speed.
##
## The player is deliberately lifted off the ground (rather than left resting
## from TestWorld.place()) before the velocity is assigned: FallingMove is the
## ONLY move that ever queries for a wall (see its own note -- WalkingMove
## never checks), so the wall-run entry gate simply never runs while the
## player is grounded. Mirrors the up-teleport pattern
## tests/test_falling_move_integration.gd already uses to reliably force a
## WALKING -> FALLING transition in exactly one tick.
func _measure_wall_ticks(entry_speed: float) -> int:
	var world := _world_with_wall(0.0)
	# Positioned BEFORE the first physics step, not after: the wall's own
	# default pose (origin, unrotated) overlaps where the player spawns, and a
	# single physics tick with the wall still there is enough for
	# move_and_slide()'s own depenetration to shove the player sideways --
	# confirmed directly by isolating it (moving the wall far away left the
	# drift identical either way, which is what pointed at a SEPARATE cause
	# below instead).
	world["wall"].global_position = Vector3(1.0, 3.0, 0.0)
	world["wall"].rotation = Vector3(0.0, PI * 0.5, 0.0)
	var player: Player = world["player"]
	await step(1)
	TestWorld.place(world)
	# Settling takes much longer than the couple of ticks it looks like it
	# should: confirmed directly (by instrumenting this exact sequence with no
	# wall at all, isolating it from anything this task touches) that
	# FallingMove's landing check reads a STALE is_on_floor() flag left over
	# from the single chaotic physics tick before place() ever moves anything
	# -- the very first spawn, still overlapping the default floor at the
	# origin -- and reports a false landing at roughly y=1.34 for exactly one
	# tick before falling again for real. The genuine landing (a stable
	# y=0.900189, matching the capsule's true resting height) does not land
	# until tick ~20. Pre-existing fixture behaviour, not something this task
	# introduced or should fix here; 30 ticks gives comfortable margin over it.
	await step(30)
	check(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: player did not settle onto the floor before the drop")

	player.global_position.y += 0.5
	await step(1)
	check(player.move_manager.current_name == Move.FALLING, \
		"test setup is wrong: the up-teleport did not send the player airborne")

	# Heading is parallel to the wall's face (the wall's near face is a plane
	# in Y/Z after the 90-degree yaw above; running along -Z is a STRAFE-style
	# approach, well clear of the forward/strafe hysteresis band around the
	# incidence angle's 57-60 degree gap).
	player.velocity = Vector3(0.0, player.velocity.y, -entry_speed)
	var ticks := 0
	for i in 400:
		await step(1)
		if player.move_manager.current_name == Move.WALL_RUN:
			ticks += 1
		elif ticks > 0:
			break
	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)
	return ticks

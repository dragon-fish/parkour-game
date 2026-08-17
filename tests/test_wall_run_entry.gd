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

func test_a_wall_run_ends_when_vertical_speed_sinks_past_the_stop_limit() -> void:
	# Distinguishes the vertical stop-limit exit from the horizontal one.
	# Left to decay naturally this takes ~2.9 s (174 ticks) at a 7.2 m/s
	# entry -- the horizontal exit (~1.04 s) always fires first in ordinary
	# play, which is fine (the original also ends runs primarily on
	# horizontal decay; the vertical limit is a backstop) but means this path
	# would otherwise never be exercised by anything. Forced directly here:
	# velocity.y is set below the limit while horizontal speed is kept high,
	# so if the run ends, it can only be this condition -- not decay, which
	# is independently confirmed still comfortably above wall_running_min_speed
	# on the very same tick.
	var world := _world_with_wall(0.0)
	# x = 0.95 -> near face at 0.45 (thickness 1.0 halved), the midpoint of the
	# only window that both clears the capsule (radius 0.4, so near face must
	# exceed that or the body overlaps the wall) and stays inside the probe's
	# own reach (wall_running_forward_check_distance, 0.5). Confirmed directly:
	# x = 1.0 (near face exactly AT the 0.5 reach boundary) intermittently
	# failed to attach at all -- wall_query() returned invalid, most likely a
	# floating-point coin flip on an exact tangency. 0.95 leaves real margin
	# on both sides (0.05 m each), mirroring the same tight window
	# tools/arena_builder.gd's own zig-zag corridor derivation now works within.
	world["wall"].global_position = Vector3(0.95, 3.0, 0.0)
	world["wall"].rotation = Vector3(0.0, PI * 0.5, 0.0)
	var player: Player = await _attach_to_wall(world, 7.0)

	var stop_limit: float = player.config.wall_run.wall_running_velocity_stop_limit
	var min_speed: float = player.config.wall_run.wall_running_min_speed
	player.velocity = Vector3(0.0, stop_limit - 1.0, player.velocity.z)
	await step(1)

	check(Vector2(player.velocity.x, player.velocity.z).length() >= min_speed, \
		"test setup is wrong: horizontal speed decayed enough on its own to also explain this exit")
	check(player.move_manager.current_name == Move.FALLING, \
		"a vertical speed past the stop limit did not end the wall run")

	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)

## Settles the player onto the floor, lifts it airborne, and drives it into
## `world`'s wall at `entry_speed`, returning once WALL_RUN is confirmed
## active. Factored out of _measure_wall_ticks() so
## test_a_wall_run_ends_when_vertical_speed_sinks_past_the_stop_limit() can
## reach the same attached state without duplicating the settle/lift dance.
func _attach_to_wall(world: Dictionary, entry_speed: float) -> Player:
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
	# in Y/Z after the 90-degree yaw the caller applies, running along -Z is a
	# STRAFE-style approach, well clear of the forward/strafe hysteresis band
	# around the incidence angle's 57-60 degree gap).
	player.velocity = Vector3(0.0, player.velocity.y, -entry_speed)
	await step(1)
	check(player.move_manager.current_name == Move.WALL_RUN, \
		"test setup is wrong: the player never attached to the wall")
	return player

## Drives a player into a wall at `entry_speed` and returns how many ticks the
## wall run lasted. Implemented with a direct velocity assignment rather than
## by running the speed curve up first, so the two cases differ ONLY in entry
## speed.
func _measure_wall_ticks(entry_speed: float) -> int:
	var world := _world_with_wall(0.0)
	# Positioned BEFORE the first physics step, not after: the wall's own
	# default pose (origin, unrotated) overlaps where the player spawns, and a
	# single physics tick with the wall still there is enough for
	# move_and_slide()'s own depenetration to shove the player sideways --
	# confirmed directly by isolating it (moving the wall far away left the
	# drift identical either way, which is what pointed at a SEPARATE cause
	# below instead).
	world["wall"].global_position = Vector3(0.95, 3.0, 0.0)
	world["wall"].rotation = Vector3(0.0, PI * 0.5, 0.0)
	var player: Player = await _attach_to_wall(world, entry_speed)
	# _attach_to_wall() already confirmed WALL_RUN is active for one tick;
	# count that one and keep counting until it ends.
	var ticks := 1
	for i in 400:
		await step(1)
		if player.move_manager.current_name == Move.WALL_RUN:
			ticks += 1
		else:
			break
	world["wall"].queue_free()
	TestWorld.teardown(world)
	await step(1)
	return ticks

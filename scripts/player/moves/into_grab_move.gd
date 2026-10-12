class_name IntoGrabMove
extends PhysicsMove

# The original's TdMove_IntoGrab (MOVE_IntoGrab 14): the reach for a ledge.
# [ME:CONFIRMED decompile script TdMove_IntoGrab.uc; CanDoMoveNative
# 0x011f9c30 and CheckAutoMoves 0x012063f0 read, N4 §2.6, N5 §11]
#
# Entered from CheckAutoMoves when the hand-plant search found a top and the
# native gate below admits it -- never through the script's CanDoMove, so
# RedoMoveTime does not apply. The reach is a PLM_Fall precise location: the
# body keeps falling under the world's gravity (rising first, if it was) while
# the precise location carries it across at max(300 uu/s, its horizontal
# speed) to the hang point -- the ledge, out by the body's box reach and 92.8
# uu down. Once falling past a hang point below it within a frame's reach, the
# vertical speed is set to land on it; falling below the hang point fails the
# reach (Falling). Reaching it hands to Grab if the body faces the wall within
# 40 degrees, otherwise to Falling.
#
# While reaching, the search runs again every frame (this move's own
# CheckAutoMoves, which never vaults) and re-aims at a new ledge once the body
# is more than 32 uu from the hang point -- after asking the native gate about
# the OLD ledge, as the original does.

## The vertical speed the reach started with.
var into_grab_speed: float = 0.0
var prepare_to_grab: bool = false
var sloped_ledge: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_uncontrolled_falling = true

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func _into_cfg() -> IntoGrabConfig:
	return cfg as IntoGrabConfig

func _grab() -> GrabMove:
	return player.move_manager.move_for(GRAB) as GrabMove

## TdMove_IntoGrab.CanDoMove (asked by nothing on the player's paths but kept).
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	return player.movement_state != INTO_CLIMB

## UTdMove_IntoGrab::CanDoMoveNative. [ME:CONFIRMED decompile 0x011f9c30]
func can_do_move_native() -> bool:
	var c: IntoGrabConfig = _into_cfg()
	if player.statuses != null and player.statuses.is_move_blocked(INTO_GRAB):
		return false
	if player.evade_timer > 0.0:
		return false
	var ledge: Vector3 = player.move_ledge_location
	var here: Vector3 = player.global_position
	var v: Vector3 = player.velocity
	var ledge_z: float = ledge.y - c.grab_desired_ledge_offset_z
	var to := Vector3(ledge.x - here.x, ledge_z - here.y, ledge.z - here.z)
	# 0.005 per uu/s: full reach from 200 uu/s toward the hang point.
	var k: float = clampf(Vector3(v.x, 0.0, v.z).dot(PawnPhysics.safe_normal_2d(to)) * (0.005 / UU), 0.4, 1.0)
	var reach: float = c.into_grab_max_distance * k
	if to.length_squared() > reach * reach:
		return false
	if not (v.y < 0.0 or (ledge.y <= here.y + player.collision_half_height() \
			and player.movement_state == WALL_CLIMB)):
		return false
	if ledge.y - here.y < 0.0:
		return false
	if player.move_ledge_normal.y < c.grab_min_grabable_z_normal:
		return false
	if (-player.move_normal).dot(player.facing()) < cos(c.into_grab_max_angle):
		return false
	if v.dot(-player.move_normal) < c.into_grab_min_initial_align_speed:
		return false
	if v.y < 0.0 and ledge_z > here.y:
		return false
	return player.movement_volume_at(ledge) == null

## UTdMove_IntoGrab's CheckAutoMoves (0x012063f0), replacing the base's: the
## search again, the native gate, and the re-aim.
func check_auto_moves() -> void:
	var v: Vector3 = player.velocity
	var still: float = 1e-4 * UU
	if absf(v.x) < still and absf(v.y) < still and absf(v.z) < still:
		return
	if player.old_movement_state == GRAB_TRANSFER:
		return
	var hit: Dictionary = player.traces.find_auto_move_ledge(player.global_position, player.facing(),
		MoveTraces.HAND_PLANT_CHECK_DISTANCE, true, edge_in_vel_dir())
	player.move_ledge_result = hit["result"]
	if player.move_ledge_result != MoveTraces.LEDGE_TOP:
		return
	if not can_do_move_native():
		return
	var here: Vector3 = player.global_position
	var at: Vector3 = player.move_location
	if Vector2(here.x - at.x, here.z - at.z).length() <= _into_cfg().min_grab_ledge_adjust_distance:
		return
	player.move_ledge_location = hit["ledge_location"]
	player.move_ledge_normal = hit["ledge_normal"]
	player.move_normal = hit["move_normal"]
	var target: Vector3 = _hang_point()
	precise_location = target
	player.move_location = target

## The hang point: the ledge, out along the wall's flat normal by the radius
## and the box's reach, GrabDesiredLedgeOffset.Z down.
func _hang_point() -> Vector3:
	var r: float = player.collision_radius()
	var n2: Vector3 = PawnPhysics.safe_normal_2d(player.move_normal)
	var target: Vector3 = player.move_ledge_location + n2 * (r + player.traces.calculate_relative_extent(r))
	target.y -= _into_cfg().grab_desired_ledge_offset_z
	return target

## The hang point for a ledge on a wall of normal `wall_normal`, for the debug
## overlay: R + the relative extent is the square box's reach off the wall.
static func hang_point_for(ledge: Vector3, wall_normal: Vector3, radius: float, offset_z: float) -> Vector3:
	var target: Vector3 = ledge + PawnPhysics.safe_normal_2d(wall_normal) * MoveTraces.box_reach(wall_normal, radius)
	target.y -= offset_z
	return target

## TdMove_IntoGrab.StartMove.
func enter(previous: StringName) -> void:
	sloped_ledge = player.move_ledge_normal.y < 0.999
	var grab: GrabMove = _grab()
	grab.sloped_ledge = sloped_ledge
	var wanted: Vector3 = _hang_point()
	if previous == WALL_CLIMB:
		var gravity: float = absf(player.gravity_z()) / UU
		var needed_height: float = (player.move_ledge_location.y
			- (player.global_position.y + player.collision_half_height())) / UU
		var needed_speed: float = sqrt(float(maxi(0, int(4.0 * (needed_height + 4.0) * gravity))))
		player.velocity.y = float(mini(int(needed_speed), int(player.velocity.y / UU))) * UU
	player.move_location = wanted
	if previous == GRAB_TRANSFER:
		reached_precise_location()
	else:
		set_precise_location(wanted, maxf(_into_cfg().into_grab_align_speed, player.horizontal_speed()), PLM_FALL)
		set_precise_rotation(UE.dir_yaw(-player.move_normal), 0.2)
	into_grab_speed = player.velocity.y
	grab.current_folded_type = GrabMove.FoldedType.NONE
	check_for_folded_hang()
	prepare_to_grab = false

## TdMove_IntoGrab.CheckForFoldedHang: a catch on a flat top level with the
## chest, moving in slowly, with nothing under the hang point and room to heave
## over crouched, hangs folded (knees up) -- the vertical speed held to -300 ..
## 150 uu/s.
func check_for_folded_hang() -> void:
	var c: IntoGrabConfig = _into_cfg()
	var grab: GrabMove = _grab()
	var here: Vector3 = player.global_position
	var ledge: Vector3 = player.move_ledge_location
	var vel_2d: float = player.horizontal_speed()
	var distance_2d: float = Vector2(ledge.x - here.x, ledge.z - here.z).length()
	if sloped_ledge:
		return
	if into_grab_speed > c.hang_folded_into_grab_z_speed_threshold:
		return
	if into_grab_speed < -1200.0 * UU:
		return
	if vel_2d < c.hang_folded_into_grab_speed_2d_threshold:
		return
	if distance_2d > c.hang_folded_max_distance:
		return
	if player.move_ledge_normal.y < 0.98:
		return
	if ledge.y > here.y + c.hang_folded_upper_delta_distance:
		return
	if ledge.y < here.y - c.hang_folded_lower_delta_distance:
		return
	if grab.current_folded_type == GrabMove.FoldedType.START:
		return
	if not grab.is_facing_ledge():
		return
	var start: Vector3 = player.move_location
	var end: Vector3 = start - Vector3.UP * (player.collision_half_height() + 1.0 * UU)
	var extent: Vector3 = player.collision_extent()
	extent.y = 0.0
	if player.traces.movement_trace_for_blocking(end, start, extent):
		return
	var floor_location: Vector3 = here - Vector3.UP * player.collision_half_height()
	floor_location = find_floor_over_ledge(98.0 * UU, floor_location,
		config.pawn.max_step_height + 4.0 * UU)
	if floor_location.y < ledge.y - 4.0 * UU:
		return
	floor_location.y = ledge.y + 4.0 * UU
	if not can_heave_over_ledge_crouched(98.0 * UU, floor_location, floor_location.y):
		return
	grab.enable_folded_hang()
	player.velocity.y = clampf(float(int(player.velocity.y / UU)) * UU,
		float(int(c.hang_folded_downward_speed_limit / UU)) * UU,
		float(int(c.hang_folded_into_grab_z_speed_threshold / UU)) * UU)

## TdMove_IntoGrab.ReachedPreciseLocation: the catch.
func reached_precise_location() -> void:
	var grab: GrabMove = _grab()
	if not grab.can_do_move():
		player.move_manager.set_move(FALLING)
		return
	var c: IntoGrabConfig = _into_cfg()
	prepare_to_grab = true
	player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(-player.move_normal))
	player.global_position = player.move_location
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	grab.set_grab_type(grab.check_wall_leg_placement())
	grab.previous_grab_type = grab.grab_type
	if grab.current_folded_type == GrabMove.FoldedType.START:
		pass
	elif player.old_movement_state == WALL_CLIMB and _wall_climb_double_jumped():
		grab.grab_from_vertical_wallrun = true
		play_slot_anim(&"hanghardstartvertical", 1.0, 0.2, 0.8 if sloped_ledge else 0.2)
	elif grab.is_hanging_free():
		play_slot_anim(&"HangFreeHardStart", 1.0, 0.1, 0.2)
		grab.start_looking_at_ledge_time = 0.5
		grab.stop_looking_at_ledge_time = 1.0
	elif not sloped_ledge and into_grab_speed < c.hang_impact_min_z_speed:
		if into_grab_speed < c.hang_hard_impact_min_z_speed:
			play_slot_anim(&"HangHardStart3", 1.0, 0.1, 0.8 if sloped_ledge else 0.2)
			grab.start_looking_at_ledge_time = 1.6
			grab.stop_looking_at_ledge_time = 2.0
			grab.grab_from_high_z_speed = true
		else:
			play_slot_anim(&"HangHardStart2", 1.0, 0.1, 0.2)
			grab.start_looking_at_ledge_time = 0.8
			grab.stop_looking_at_ledge_time = 1.2
	else:
		play_slot_anim(&"HangHardStart", 1.0, 0.1, 0.2)
		grab.start_looking_at_ledge_time = 0.5
		grab.stop_looking_at_ledge_time = 1.0
	grab.reset_camera_look(0.15)
	player.move_manager.set_move(GRAB)

func _wall_climb_double_jumped() -> bool:
	var climb = player.move_manager.move_for(WALL_CLIMB)
	return climb != null and climb.performed_double_jump

func failed_to_reach_precise_location() -> void:
	player.move_manager.set_move(FALLING)

## TdMove_IntoGrab.StopMove.
func exit() -> void:
	var grab: GrabMove = _grab()
	if grab.current_folded_type != GrabMove.FoldedType.START:
		grab.current_folded_type = GrabMove.FoldedType.NONE
	if player.pending_movement_state != GRAB and grab.current_folded_type == GrabMove.FoldedType.START:
		player.anim_slot.stop(0.2)
	prepare_to_grab = false

class_name IntoZiplineMove
extends PhysicsMove

# The original's TdMove_IntoZipLine, ported. [ME:CONFIRMED decompile script
# TdMove_IntoZipLine, TdZiplineVolume]
#
# The reach onto a cable. The cable's volume offers it every tick the body is
# inside (volume_pawn_update(), from Player); it flies the hands to a point
# 100 uu down the cable from the nearest one -- PLM_Fly when falling, PLM_Jump
# otherwise, at max(|V.xy|, 400 uu/s) -- turning the pawn to the cable on the
# way, and on arrival hands the body to ZipLine with the run-up's flat speed
# projected onto the cable (none past the fall limit). Hitting anything on the
# way is a fall.

## TdMove_IntoZipLine.ZipLine: the cable the volume offered.
var zip_line: InterestLine = null
var enter_zip_line_param: float = 0.0
var saved_initial_2d_velocity: Vector3 = Vector3.ZERO
## LastZipLineVolumeName: the cable last reached for.
var last_zip_line: InterestLine = null

var _points: PackedVector3Array = PackedVector3Array()

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_WALKING

func is_ported() -> bool:
	return true

## TdZiplineVolume.PawnUpdate. Returns whether the reach took the body.
func volume_pawn_update(line: InterestLine) -> bool:
	var state: StringName = player.move_manager.current_name
	if state == ZIPLINE or state == INTO_ZIPLINE:
		return false
	zip_line = line
	if can_do_move():
		player.move_manager.set_move(INTO_ZIPLINE)
		return true
	zip_line = null
	return false

## TdMove_IntoZipLine.CanDoMove.
func can_do_move() -> bool:
	if zip_line == null or not is_instance_valid(zip_line):
		return false
	var state: StringName = player.move_manager.current_name
	if state == ZIPLINE or state == INTO_ZIPLINE:
		return false
	if ZiplineMove.move_direction(zip_line).dot(player.facing()) <= 0.0:
		return false
	if state == WALKING or state == CROUCH or state == SLIDE:
		return false
	var points: PackedVector3Array = ZiplineMove.spline_points(zip_line)
	if points.is_empty():
		return false
	var to_end: Vector3 = player.global_position - points[points.size() - 1]
	if Vector2(to_end.x, to_end.z).length() < cfg.landing_strip:
		return false
	var ride: Move = player.move_manager.move_for(ZIPLINE)
	if ride != null and cfg.same_zipline_redo_move_time > player.world_time - ride.last_stop_move_time \
			and zip_line == last_zip_line:
		return false
	return td_can_do_move()

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
	_points = ZiplineMove.spline_points(zip_line)
	var destination: Vector3 = ZiplineMove.closest_on_spline(_points, player.global_position)[0]
	var ahead: Array = ZiplineMove.closest_on_spline(_points,
		destination + ZiplineMove.move_direction(zip_line) * cfg.reach_ahead)
	destination = ahead[0]
	enter_zip_line_param = ahead[1]
	destination.y -= cfg.hang_offset
	last_zip_line = zip_line
	var speed: float = maxf(Vector2(player.velocity.x, player.velocity.z).length(), cfg.min_reach_speed)
	var wanted: Vector3 = ZiplineMove.slope_at(_points, enter_zip_line_param)
	var time_to_destination: float = (destination - player.global_position).length() / speed
	set_precise_rotation(UE.dir_yaw(wanted), time_to_destination)
	saved_initial_2d_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if player.velocity.y < 0.0:
		set_precise_location(destination, speed, PLM_FLY)
	else:
		set_precise_location(destination, speed, PLM_JUMP)
	player.set_ignore_move_input(-1.0)

func exit() -> void:
	zip_line = null

## HitWall: whatever was hit, the reach is over.
func hit_wall(_normal: Vector3, _collider: Object) -> void:
	player.move_manager.set_move(FALLING)

func reached_precise_location() -> void:
	player.stop_ignore_move_input()
	var ride = player.move_manager.move_for(ZIPLINE)
	if ride == null or not ride.can_do_move():
		player.move_manager.set_move(FALLING)
		return
	ride.zip_line = zip_line
	var dir: Vector3 = ZiplineMove.slope_at(_points, enter_zip_line_param)
	player.rotation.y = atan2(-dir.x, -dir.z)
	if player.velocity.y < cfg.z_velocity_fall_limit:
		saved_initial_2d_velocity = Vector3.ZERO
	var saved_speed: float = saved_initial_2d_velocity.length()
	player.velocity = dir * (saved_speed * maxf(dir.dot(PawnPhysics.safe_normal(saved_initial_2d_velocity)), 0.0))
	player.move_manager.set_move(ZIPLINE)

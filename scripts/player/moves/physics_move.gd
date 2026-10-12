class_name PhysicsMove
extends Move

# The original's TdPhysicsMove: a move that names a physics mode and a
# controller state, and that the native layer asks about automatic
# transitions every tick. [ME:CONFIRMED decompile N4 §2]
#
# Every switch below is a field of the original's, and every value is its CDO
# default (TdPhysicsMove defaultproperties); a subclass declares in _init()
# only what its own CDO or DefaultPawnMovement.ini changes.

## TdPhysicsMove.bCheckForGrab / bCheckForVaultOver / bCheckForWallClimb are
## the MoveConfig's check_for_grab / check_for_vault_over /
## check_for_wall_climb (config, as in the original), read through
## Move.checks_grab() and its siblings.

## bCheckForEdgeInVelDir: adds the velocity's vertical direction to the hand
## plant search. Only WallClimb sets it.
var check_for_edge_in_vel_dir: bool = false
## bCheckExitToFalling: pre_physics() hands to Falling below
## exit_to_falling_z_speed.
var check_exit_to_falling: bool = false
## bCheckExitToUncontrolledFalling: pre_physics() hands to FallUncontrolled
## once EnterFallingHeight - Location.Z passes FallingUncontrolledHeight.
var check_exit_to_uncontrolled_falling: bool = false
## bCheckForSoftLanding: pre_physics() hands to SoftLanding when the arc two
## seconds ahead ends on a soft-landing surface.
var check_for_soft_landing: bool = false
## bDelayTimeCheckAutoMoves: the hand-plant search runs only once
## MoveActiveTime is past this. -1 means from the first tick. It gates the
## search alone, never the wall run in front of it.
var delay_time_check_auto_moves: float = -1.0
## [ME:CONFIRMED decompile] ExitToFallingZSpeed = -400 uu/s,
## SoftLandingZSpeedThreshold = -400 uu/s.
var exit_to_falling_z_speed: float = -4.0
var soft_landing_z_speed_threshold: float = -4.0

func _init() -> void:
	# [ME:CONFIRMED decompile] TdPhysicsMove's CDO: PawnPhysics = PHYS_Walking.
	pawn_physics = PHYS_WALKING

func edge_in_vel_dir() -> bool:
	return check_for_edge_in_vel_dir

func auto_move_delay() -> float:
	return delay_time_check_auto_moves

## Native slot 0x124, TdPhysicsMove::CheckAutoMoves. [ME:CONFIRMED decompile
## N4 §2.2] Move.auto_move_target() is the original's order. The level's
## interest points are not asked here: their volumes ask every tick
## (Player._update_movement_volume).
func check_auto_moves() -> void:
	var manager = player.move_manager
	var next: StringName = auto_move_target()
	if next == KEEP:
		return
	# A target not yet ported keeps its own cooldown, as it does when its own
	# physics_update() names the next move.
	var target: Move = manager.move_for(next)
	if target != null and not target.is_ported() and not manager.can_enter(next):
		return
	manager.set_move(next)

## Native slot 0x118, TdPhysicsMove::PrePhysics. [ME:CONFIRMED decompile N4
## §2.3] Precise location first, then the three falling exits in this order.
## The soft-landing branch returns whether or not SetMove took it.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	var manager = player.move_manager
	# Not while root rotation turns the pawn. The SetMove is made and the tick
	# ends here whether or not it changed anything: in SoftLanding itself it
	# changes nothing, and that is what keeps the exit below from running
	# while the pad is still ahead. [ME:CONFIRMED decompile N4 §2.3, N5 §5]
	if check_for_soft_landing and player.velocity.y < soft_landing_z_speed_threshold \
			and not player.using_root_rotation and _soft_landing_ahead():
		manager.set_move(SOFT_LANDING)
		return
	if check_exit_to_falling and player.velocity.y < exit_to_falling_z_speed:
		manager.set_move(FALLING)
		return
	if check_exit_to_uncontrolled_falling \
			and player.enter_falling_height - player.collision_center().y \
				> config.pawn.falling_uncontrolled_height:
		manager.set_move(FALL_UNCONTROLLED)

## SoftLandingProbe (0x011f9970) and the height test around it: a line from the
## feet to where they will be in two seconds -- p + v t + a t^2 / 2 at t = 2,
## with the SCRIPT gravity (half the felt one), as the original computes it --
## hitting an upward face (normal z > 0.9) of a soft-landing surface more than
## two collision heights below the body's centre.
func _soft_landing_ahead() -> bool:
	var feet: Vector3 = player.collision_center() - Vector3.UP * player.collision_half_height()
	var a := Vector3(player.acceleration.x, player.gravity_z(), player.acceleration.z)
	var to: Vector3 = feet + player.velocity * 2.0 + a * 2.0
	var hit: Dictionary = player.phys.line_trace(feet, to)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	if normal.y <= 0.9 or not Probes.is_soft(hit["collider"]):
		return false
	var position: Vector3 = hit["position"]
	return absf(position.y - player.collision_center().y) > 2.0 * player.collision_half_height()

# --- the heave-over tests (TdPhysicsMove script) -----------------------------------
#
# [ME:CONFIRMED decompile script TdPhysicsMove.uc] Asked by IntoGrab's folded
# hang and by GrabPullUp.

## CanHeaveOverLedgeFullyExtented: room for the standing body.
func can_heave_over_ledge_fully_extended(forward_check_depth: float, destination_floor: Vector3,
		highest_ledge_location: float) -> bool:
	return _can_heave_over_ledge(forward_check_depth, destination_floor, player.collision_half_height(),
		highest_ledge_location)

## CanHeaveOverLedgeCrouched: room for the crouched body, 61 uu half height.
func can_heave_over_ledge_crouched(forward_check_depth: float, destination_floor: Vector3,
		highest_ledge_location: float) -> bool:
	return _can_heave_over_ledge(forward_check_depth, destination_floor, 61.0 * UU, highest_ledge_location)

## CanHeaveOverLedge: the body's box raised from where it hangs to the ledge
## plus its height, then swept over the top, from the higher of the floor and
## the ledge -- compared as whole uu -- plus its height and 2 uu.
func _can_heave_over_ledge(forward_check_depth: float, destination_floor: Vector3, height: float,
		highest_ledge_location: float) -> bool:
	var start: Vector3 = player.global_position
	var end: Vector3 = start
	end.y = player.move_ledge_location.y + height
	var extent: Vector3 = player.collision_extent()
	extent.y = height
	if player.traces.movement_trace_for_blocking(end, start, extent):
		return false
	start = player.global_position
	var top_uu: int = maxi(int(destination_floor.y / UU), int(highest_ledge_location / UU))
	start.y = float(top_uu) * UU + height + 2.0 * UU
	end = start - player.move_normal * forward_check_depth
	extent = player.collision_extent()
	extent.y = height - 2.0 * UU
	return not player.traces.movement_trace_for_blocking(end, start, extent)

## FindFloorOverLedge: a flat box of the body's width less 5 uu dropped
## `forward_check_depth` past the wall, from 1.414 R (plus 4 uu) above the ledge
## to 1.414 R plus twice `collision_height` below it. Returns where it hit, or
## `floor_position` unchanged when it hit nothing.
func find_floor_over_ledge(forward_check_depth: float, floor_position: Vector3,
		collision_height: float) -> Vector3:
	var r_default: float = player.default_collision_radius()
	var ledge_y: float = player.move_ledge_location.y
	var start: Vector3 = player.global_position - player.move_normal * forward_check_depth
	start.y = ledge_y + r_default * 1.414 + 4.0 * UU
	var end: Vector3 = player.global_position - player.move_normal * forward_check_depth
	end.y = ledge_y - r_default * 1.414 - collision_height * 2.0
	var extent: Vector3 = player.collision_extent()
	extent.x -= 5.0 * UU
	extent.z -= 5.0 * UU
	extent.y = 0.0
	var hit: Dictionary = player.traces.movement_trace(end, start, extent)
	if hit["hit"]:
		return hit["location"]
	return floor_position

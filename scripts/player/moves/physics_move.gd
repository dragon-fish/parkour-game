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
## check_for_wall_climb (config, as in the original).

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
## bDelayTimeCheckAutoMoves: the ledge search runs only once MoveActiveTime is
## past this. -1 means from the first tick.
var delay_time_check_auto_moves: float = -1.0
## [ME:CONFIRMED decompile] ExitToFallingZSpeed = -400 uu/s,
## SoftLandingZSpeedThreshold = -400 uu/s.
var exit_to_falling_z_speed: float = -4.0
var soft_landing_z_speed_threshold: float = -4.0

func _init() -> void:
	# [ME:CONFIRMED decompile] TdPhysicsMove's CDO: PawnPhysics = PHYS_Walking.
	pawn_physics = PHYS_WALKING

## Native slot 0x124, TdPhysicsMove::CheckAutoMoves. [ME:CONFIRMED decompile
## N4 §2.2] The order is the original's -- nothing while the body is still;
## then the wall run, the hand-plant search, the wall climb, the vault and the
## grab -- but every test in it is still this project's own probe, because
## WallRun.CanDoMove, FindAutoMoveLedge and the IntoGrab / WallClimb native
## gates have not been ported. Move.legacy_probe_transition() asks them, in
## its own order, and the level's interest points (cables, bars, ladders,
## beams, ledges) with them.
func check_auto_moves() -> void:
	var v: Vector3 = player.velocity
	if absf(v.x) < 1e-6 and absf(v.y) < 1e-6 and absf(v.z) < 1e-6:
		return
	var c: MoveConfig = current_config()
	if c == null:
		return
	var probes_anything: bool = c.check_for_grab or c.check_for_vault_over or c.check_for_wall_climb \
		or c.check_for_ladder \
		or c.check_for_ledge_walk or c.check_for_balance
	if not probes_anything:
		return
	if move_active_time <= delay_time_check_auto_moves:
		return
	var next: StringName = legacy_probe_transition()
	if next != KEEP:
		player.move_manager.set_move(next)

## Native slot 0x118, TdPhysicsMove::PrePhysics. [ME:CONFIRMED decompile N4
## §2.3] Precise location first, then the three falling exits in this order.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	var manager = player.move_manager
	if check_for_soft_landing and player.velocity.y < soft_landing_z_speed_threshold \
			and _soft_landing_ahead():
		if manager.set_move(SOFT_LANDING):
			return
	if check_exit_to_falling and player.velocity.y < exit_to_falling_z_speed:
		manager.set_move(FALLING)
		return
	if check_exit_to_uncontrolled_falling \
			and player.enter_falling_height - player.global_position.y \
				> config.pawn.falling_uncontrolled_height:
		manager.set_move(FALL_UNCONTROLLED)

## SoftLandingProbe (0x011f9970) and the height test around it: a line from the
## feet to where they will be in two seconds -- p + v t + a t^2 / 2 at t = 2,
## with the SCRIPT gravity (half the felt one), as the original computes it --
## hitting an upward face (normal z > 0.9) of a soft-landing surface more than
## two collision heights below the body's centre.
func _soft_landing_ahead() -> bool:
	var feet: Vector3 = player.global_position - Vector3.UP * player.collision_half_height()
	var a := Vector3(player.acceleration.x, player.gravity_z(), player.acceleration.z)
	var to: Vector3 = feet + player.velocity * 2.0 + a * 2.0
	var hit: Dictionary = player.phys.line_trace(feet, to)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	if normal.y <= 0.9 or not Probes.is_soft(hit["collider"]):
		return false
	var position: Vector3 = hit["position"]
	return absf(position.y - player.global_position.y) > 2.0 * player.collision_half_height()

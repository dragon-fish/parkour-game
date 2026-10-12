class_name StepUpMove
extends PhysicsMove

# The original's TdMove_StepUp (MOVE_StepUp 37), ported. [ME:CONFIRMED
# decompile script TdMove_StepUp.uc]
#
# UNREACHABLE for the player: nothing in the script or the natives sets
# MOVE_StepUp (CheckAutoMoves asks AutoStepUp and VaultOver). Registered so the
# move exists as the original's does.
#
# The script picks its step type, then overwrites it with ESUT_Long whatever
# the height, so the low, medium and high root-motion steps can never play:
# every step up is VaultOnto's animation and a PLM_Jump arc to 80 uu past the
# ledge, ended by reaching it (Walking), leaving with the approach velocity.

enum Type { LOW, MEDIUM, HIGH, LONG }

var end_position: Vector3 = Vector3.ZERO
var step_up_type: int = Type.LONG
var start_distance: float = 0.0
var saved_velocity: Vector3 = Vector3.ZERO

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	disable_collision = true
	disable_face_rotation = true
	avoid_ledges = false
	disable_movement_time = -1.0

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func _step_cfg() -> StepUpConfig:
	return cfg as StepUpConfig

## TdMove_StepUp.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move() or not player.found_ledge:
		return false
	if player.found_ledge_excludes_foot_moves or MoveTraces.excludes_foot_moves(player.movement_actor):
		return false
	var ledge: Vector3 = player.move_ledge_location
	var here: Vector3 = player.global_position
	var distance: float = Vector2(ledge.x - here.x, ledge.z - here.z).length()
	var time_to_ledge: float = distance / maxf(150.0 * UU, SpeedVaultMove.uu_int(player.horizontal_speed()))
	if time_to_ledge > 0.45:
		return false
	if player.move_ledge_normal.y < 0.71:
		return false
	var handplant_height: float = ledge.y - here.y + player.collision_half_height()
	var c: StepUpConfig = _step_cfg()
	if handplant_height > c.step_up_high_max_height or handplant_height < c.step_up_low_min_height:
		return false
	start_distance = minf(120.0 * UU, distance)
	step_up_type = Type.LONG
	# (A heavy weapon refuses High and Long; this project has no weapons.)
	if step_up_type <= Type.MEDIUM and time_to_ledge > 0.3:
		return false
	saved_velocity = player.velocity
	end_position = ledge + player.facing() * 80.0 * UU
	end_position.y += player.collision_half_height() + 2.0 * UU
	var extent: Vector3 = player.collision_extent()
	extent.y = 62.0 * UU
	var trace_end: Vector3 = end_position
	trace_end.y = ledge.y + extent.y + 2.0 * UU
	var trace_start: Vector3 = here
	trace_start.y = trace_end.y
	if player.traces.movement_trace_for_blocking(trace_end, trace_start, extent):
		return false
	if player.traces.movement_trace_for_blocking(end_position, trace_end, extent):
		return false
	return true

## TdMove_StepUp.StartMove: only the Long branch is ever taken.
func enter(_previous: StringName) -> void:
	play_slot_anim(&"vaultonto", 1.0, 0.15, 0.25)
	set_precise_location(end_position,
		maxf(200.0 * UU, SpeedVaultMove.uu_int(Vector2(saved_velocity.x, saved_velocity.z).length())), PLM_JUMP)

func reached_precise_location() -> void:
	player.move_manager.set_move(WALKING)

## TdMove_StepUp.StopMove.
func exit() -> void:
	if step_up_type == Type.LONG:
		player.velocity = saved_velocity
		player.acceleration = PawnPhysics.safe_normal(saved_velocity)
	else:
		player.velocity = Vector3.ZERO
	player.face_rotation_time_left = 0.3
	player.set_acceleration_time(0.2)

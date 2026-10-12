class_name MeleeWallrunMove
extends PhysicsMove

# The original's TdMove_MeleeWallrun, ported for movement and animation
# (MOVE_MeleeWallrun, 62). [ME:CONFIRMED decompile 15.5] The kick off a wall
# run. With no target -- and this project has no melee targets -- the
# velocity is turned 6000 rotator units (about 33 degrees) away from the wall
# and scaled by 1.2, and the pawn is turned the same way in 0.1 s, the view
# with it. The kick ends when its animation does, by SETTING WALKING, in the
# air or not. A landing during it changes nothing: Landed only acts in
# MS_MeleePending, and StartMove has already left that state.
#
# No damage, no hit detection, no target lock-on: this project deals none.

## TdMove_MeleeBase.CanDoMoveTaserLimit.
const CAN_DO_MOVE_TASER_LIMIT := 0.8
## TdMove_MeleeBase.EMeleeState: MS_MeleePending 0, MS_MeleeAttackNormal 1.
const MS_MELEE_PENDING := 0
const MS_MELEE_ATTACK_NORMAL := 1

var melee_state: int = MS_MELEE_PENDING
## Whether the kick left a wall on the left (OldMovementState ==
## WallRunningLeft).
var left: bool = false
var wallrun_normal: Vector3 = Vector3.ZERO

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE
	pawn_physics = PHYS_FALLING

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

## TdMove_MeleeBase.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	return player.mobility_multiplier() >= CAN_DO_MOVE_TASER_LIMIT

## TdMove_MeleeWallrun.StartMove (with TdMove_MeleeBase's).
func enter(_previous: StringName) -> void:
	melee_state = MS_MELEE_ATTACK_NORMAL
	var wall_run: WallRunMove = player.move_manager.move_for(WALL_RUN)
	left = player.old_movement_state == WALL_RUN and wall_run.side == WallRunMove.SIDE_LEFT
	wallrun_normal = wall_run.wall_normal
	trigger_move()

## TdMove_MeleeWallrun.TriggerMove, without a target.
func trigger_move() -> void:
	var c: MeleeWallrunConfig = cfg as MeleeWallrunConfig
	var turn: int = int(round(c.turn_off_wall * UE.UNITS_PER_RADIAN))
	var pawn_units: int = UE.yaw_units(player.pawn_yaw)
	set_precise_rotation(UE.normalize_axis(pawn_units + (turn if left else -turn)), 0.1)
	# V << rot(0, -6000, 0) off a left wall turns it 6000 to the right; the
	# original's yaw grows to the right, Godot's to the left.
	var angle: float = turn / UE.UNITS_PER_RADIAN
	player.velocity = player.velocity.rotated(Vector3.UP, -angle if left else angle)
	player.velocity *= c.speed_scale
	reset_camera_look(0.1)
	# OnCustomAnimEnd: MeleeWallRunLeft / Right at rate 1.
	set_move_timer(c.left_kick_time if left else c.right_kick_time, false, _on_custom_anim_end)

func _on_custom_anim_end() -> void:
	player.move_manager.set_move(WALKING)

## TdMove_MeleeWallrun.Landed: Walking only while still pending.
func landed(_normal: Vector3) -> void:
	if melee_state == MS_MELEE_PENDING:
		player.move_manager.set_move(WALKING)

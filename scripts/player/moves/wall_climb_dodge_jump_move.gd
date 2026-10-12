class_name WallClimbDodgeJumpMove
extends PhysicsMove

# The original's TdMove_WallClimbDodgeJump, ported (MOVE_WallClimbDodgeJump,
# 49). [ME:CONFIRMED decompile 15.5] Jump on a wall climb with the stick
# pushed sideways past 0.8: sideways off the pawn's facing at JumpAddXY, the
# whole velocity kept, BaseJumpZ up, the view swung to the dodge's direction.
# For 0.5 s the grab, vault and wall-climb switches are off, then back.
#
# The original also has MOVE_WallClimbDodgeJumpLeft (51) and Right (52), more
# instances of this class that nothing ever sets. Not registered.

var _side: int = 1

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

## TdMove_WallClimbDodgeJump.CanDoMove: State == WallClimbing && (Hint == Right
## || Hint == Left), bracketed as the bytecode has it.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var hint: int = player.move_action_hint
	return player.move_manager.current_name == WALL_CLIMB and (hint == MAH_RIGHT or hint == MAH_LEFT)

## TdMove_WallClimbDodgeJump.StartMove. Its script adds a rising non-world
## base's Velocity.Z, but asks after super.StartMove has set PHYS_Falling,
## and setPhysics into Falling has already cleared the base. [ME:INFERRED]
## UE3's AActor::setPhysics, not decompiled here; the port's set_physics()
## does the same, so the addition is not carried.
func enter(_previous: StringName) -> void:
	var c: WallClimbDodgeJumpConfig = cfg as WallClimbDodgeJumpConfig
	_side = -1 if player.move_action_hint == MAH_LEFT else 1
	var dodge: Vector3 = UE.cross(Vector3.UP, player.facing()).normalized() * c.jump_add_xy * _side
	set_look_at_target_angle(UE.dir_pitch(dodge), UE.dir_yaw(dodge), 0.1, 1.0)
	player.last_jump_location = player.global_position
	player.velocity = dodge + c.dodge_jump_inertia_conservation * player.velocity
	player.velocity.y = c.base_jump_z
	auto_checks_cleared = true
	set_timer(c.auto_checks_off_time)

func on_timer() -> void:
	auto_checks_cleared = false

## Which way the dodge went, -1 left or +1 right, for the animation.
func dodge_side() -> int:
	return _side

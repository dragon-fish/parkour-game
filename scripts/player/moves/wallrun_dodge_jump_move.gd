class_name WallrunDodgeJumpMove
extends PhysicsMove

# The original's TdMove_WallrunDodgeJump, ported (MOVE_WallRunDodgeJump, 34).
# [ME:CONFIRMED decompile 15.5] Jump on a wall run with the stick pushed AWAY
# from the wall past 0.8 (PlayerWallWalking's hint): the action table asks
# this before WallRunJump. Sideways off the pawn's facing -- which on a wall
# is along the wall -- at JumpAddXY, plus 0.3 of the velocity, BaseJumpZ up.

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true

func is_ported() -> bool:
	return true

## TdMove_WallrunDodgeJump.CanDoMove: running the left wall with the hint
## Right, or the right wall with the hint Left.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var manager = player.move_manager
	if manager.current_name != WALL_RUN:
		return false
	var side: int = (manager.move_for(WALL_RUN) as WallRunMove).side
	var hint: int = player.move_action_hint
	return (side == WallRunMove.SIDE_LEFT and hint == MAH_RIGHT) \
		or (side == WallRunMove.SIDE_RIGHT and hint == MAH_LEFT)

## TdMove_WallrunDodgeJump.StartMove. A rising base would add its own vertical
## speed; this project's wall physics carries no base velocity.
func enter(_previous: StringName) -> void:
	var c: WallrunDodgeJumpConfig = cfg as WallrunDodgeJumpConfig
	player.last_jump_location = player.global_position
	var sign: float = -1.0 if player.move_action_hint == MAH_LEFT else 1.0
	_side = int(sign)
	var dodge: Vector3 = UE.cross(Vector3.UP, player.facing()).normalized() * c.jump_add_xy * sign
	player.velocity = dodge + c.dodge_jump_inertia_conservation * player.velocity
	player.velocity.y = c.base_jump_z

var _side: int = 1

## Which way the dodge went, -1 left or +1 right, for the animation.
func dodge_side() -> int:
	return _side

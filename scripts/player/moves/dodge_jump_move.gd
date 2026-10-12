class_name DodgeJumpMove
extends PhysicsMove

# The original's TdMove_DodgeJump, the side jump, ported. [ME:CONFIRMED
# decompile N5 §9]
#
# The action table asks it BEFORE SpringBoard and Jump on every ground jump,
# and it takes any jump made with the strafe hint held to its maximum -- a
# strafe key is always at its maximum, so a jump with A or D held is always a
# dodge jump. The launch is made once, in StartMove: JumpAddXY along the
# pawn's right (or left), plus 0.3 of the velocity it had, and BaseJumpZ
# straight up. Then PHYS_Falling under the PlayerGrabbing controller (no air
# control), and nothing it reaches for; below -190 uu/s of vertical speed it
# hands to Falling, or it lands first.
#
# The launch is a world vector and is never recomputed: turning the view
# mid-dodge turns the sideways speed into forward speed.

## Which way this dodge was thrown, -1 left and +1 right. For
## CharacterAnimator's pair of dodge clips.
var _side: int = 0

func side() -> int:
	return _side

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_GRABBING
	check_exit_to_falling = true
	# [ME:CONFIRMED decompile] ExitToFallingZSpeed = -190.
	exit_to_falling_z_speed = -1.9
	disable_movement_time = -1.0

func is_ported() -> bool:
	return true

## TdMove_DodgeJump.CanDoMove: the hint at its maximum, no uncontrolled slide,
## the hint left or right, then the base's RedoMoveTime.
func can_do_move() -> bool:
	if not player.move_action_max:
		return false
	if player.uncontrolled_slide:
		return false
	if player.move_action_hint != MAH_LEFT and player.move_action_hint != MAH_RIGHT:
		return false
	return td_can_do_move()

## TdMove_DodgeJump.StartMove.
func enter(_previous: StringName) -> void:
	_side = -1 if player.move_action_hint == MAH_LEFT else 1
	# Normal(Z x Vector(Rotation)): the pawn's right.
	var right: Vector3 = player.pawn_facing().cross(Vector3.UP).normalized()
	var dodge: Vector3 = right * (cfg.jump_add_xy * float(_side))
	player.last_jump_location = player.global_position
	var v: Vector3 = dodge + player.velocity * cfg.inertia_conservation
	v.y = cfg.base_jump_z
	if player.base_velocity.y > 0.0:
		v.y += player.base_velocity.y
	player.velocity = v
	player.acceleration = PawnPhysics.safe_normal(v)
	player.note_dodge_launch()
	if player.camera_rig != null:
		player.camera_rig.kick_takeoff(player.horizontal_speed())

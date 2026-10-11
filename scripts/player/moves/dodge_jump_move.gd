class_name DodgeJumpMove
extends AirborneMove

# The original's TdMove_DodgeJump: the sideways hop thrown off a strafe key,
# reached through the action table (Walking + jump, before SpringBoard and
# Jump). The launch happens on entry; what is left is the airborne stretch and
# the one thing that separates it from an ordinary Jump: it reaches for nothing.
#
# THE IMPULSE IS NEVER RECOMPUTED. It went into velocity as a world vector on
# the tick the move started and this state does not know which way it pointed.
# DO NOT add a per-tick push along the body's own right to "keep the dodge
# going": that turns a carried speed into a growing one, and it destroys the
# behaviour the move exists for -- [ME:CONFIRMED 04 §4.5] swinging the view 90
# degrees mid-dodge inherits the sideways speed as forward speed, which is how
# the side-jump boost bypasses the acceleration curve. That is a bug in the
# original, and copying it is the port.

## Which way this dodge was thrown, -1 for left and +1 for right.
##
## For CharacterAnimator, which has a Dodge_Left and a Dodge_Right and no way
## to tell them apart from velocity once air control has had a tick at it --
## the same job JumpMove.kick_side() does for the wall-kick clips.
var _side: int = 0

func side() -> int:
	return _side

func _init() -> void:
	# [ME:CONFIRMED decompile] TdMove_DodgeJump's PawnPhysics. This move still drives the
	# body itself; the mode is what the original's checks and the fall height
	# read while it runs.
	pawn_physics = PHYS_FALLING

## TdMove_DodgeJump.CanDoMove. [ME:CONFIRMED decompile] The strafe hint, held
## to its maximum (bMoveActionMax: past 0.96 on the raw axis, which a key
## always is), and no uncontrolled slide.
func can_do_move() -> bool:
	if not player.move_action_max or player.uncontrolled_slide:
		return false
	if player.move_action_hint != MAH_LEFT and player.move_action_hint != MAH_RIGHT:
		return false
	return super.can_do_move()

## The launch, square sideways along the hint. Player.dodge_launch() is this
## project's reading of it.
func enter(_previous: StringName) -> void:
	_side = 1 if player.move_action_hint == MAH_RIGHT else -1
	player.pending_dodge_side = 0
	var right: Vector3 = player.global_transform.basis.x
	right.y = 0.0
	player.dodge_launch(right.normalized() * float(_side))
	player.set_grounded(false)

func physics_update(delta: float, input: MoveInput) -> StringName:
	apply_air_physics(delta, player.wish_direction(input))

	# Runs the probe set the config declares, which for this move is none of
	# them (see DodgeJumpConfig). Called anyway rather than skipped, so the
	# capability set stays a property of the config the way every other
	# airborne state's is, instead of being half in data and half in an
	# omission here.
	var probed := probe_transition()
	if probed != KEEP:
		player.set_grounded(false)
		return probed

	if player.velocity.y <= config.pawn.enter_to_falling_z_speed:
		return advance_and_hand_off(FALLING)

	return settle_landing(delta)

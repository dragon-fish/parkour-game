class_name SoftLandingMove
extends PhysicsMove

# The original's TdMove_SoftLanding, ported. [ME:CONFIRMED decompile N5 §5]
#
# Entered only by the TdPhysicsMove PrePhysics of a move with
# bCheckForSoftLanding (Falling, 180TurnInAir, FallingUncontrolled, this one):
# falling faster than 400 uu/s with the arc two seconds ahead ending on a
# soft-landing surface more than two collision heights down. PHYS_Falling,
# PlayerWalking, no air control (move input ignored).
#
# While it runs its own soft-landing test runs first: as long as the pad is
# still ahead it sets SoftLanding again -- nothing, the same move -- and stops
# there, so the exit to Falling below -400 uu/s is only reached on a frame the
# probe fails: the pad closer than two heights, or out of the two-second
# window. It ends on Landed, through Landing, which reads bMovingBackwards.

## TdMove_SoftLanding.bMovingBackwards: entered out of a turn in the air.
var moving_backwards: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true
	check_for_soft_landing = true
	disable_movement_time = -1.0

func is_ported() -> bool:
	return true

func enter(_previous: StringName) -> void:
	moving_backwards = player.old_movement_state == TURN_180_IN_AIR

func is_moving_backwards() -> bool:
	return moving_backwards

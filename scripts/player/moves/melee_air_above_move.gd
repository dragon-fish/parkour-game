class_name MeleeAirAboveMove
extends MeleeBaseMove

# The original's TdMove_MeleeAirAbove, ported without combat. [ME:CONFIRMED
# decompile script TdMove_MeleeAirAbove]
#
# The stomp onto an enemy below. Only MeleeAir starts it, and only with a
# target; and its StartMove, finding no target, sets Falling BEFORE its own
# super.StartMove -- so none of its CDO (PHYS_Flying, input off) ever applies.
# That is the only branch here, and why this move declares nothing.

func _init() -> void:
	super._init()
	pawn_physics = PHYS_KEEP

func enter(_previous: StringName) -> void:
	player.move_manager.set_move(FALLING)

class_name CustomCollision
extends RefCounted

# TdMove.bUseCustomCollision, for the ported moves that set it.
# [ME:CONFIRMED decompile TdMove.StartMove / StopMove, N5 §0.2] StartMove
# shrinks the cylinder to a 61 uu half height with the feet kept where they
# are, unless the move it came from had already; StopMove gives the standing
# height back unless the move it is going to keeps it small.

## The moves whose CDO sets bUseCustomCollision.
const MOVES: Array[StringName] = [Move.SLIDE, Move.CROUCH, Move.COIL, Move.LAY_ON_GROUND,
	Move.TURN_180_IN_AIR, Move.AIR_BARGE, Move.MELEE_CROUCH, Move.MELEE_SLIDE]

## ShrinkCollision's CollisionSize: 122 uu, a 61 uu half height.
const HEIGHT := 1.22

## From StartMove.
static func shrink(player) -> void:
	if not MOVES.has(player.old_movement_state):
		player.set_capsule_height(HEIGHT)

## From StopMove: PendingMovementState is the move being switched to.
static func enlarge(player) -> void:
	if not MOVES.has(player.pending_movement_state):
		player.request_standing_capsule()

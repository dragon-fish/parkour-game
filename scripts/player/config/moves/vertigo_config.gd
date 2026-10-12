class_name VertigoConfig
extends MoveConfig

# The original's TdMove_Vertigo defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile N5 §10] DisableMovementTime and DisableLookTime 1.5
# are on the move.

## ZoomOutTime = 1.2 s: when the look-at is released.
@export var zoom_out_time: float = 1.2

func _init() -> void:
	# [ME:CONFIRMED ini] RedoMoveTime = 3.0 -- never asked: Vertigo's CanDoMove
	# does not call the base. Carried so the number is on file.
	redo_move_time = 3.0
	allows_turn = false

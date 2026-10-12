class_name MeleeAirConfig
extends MoveConfig

# The original's TdMove_MeleeAir: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_MeleeAir].

func _init() -> void:
	# [ME:CONFIRMED ini] RedoMoveTime = 0.3.
	redo_move_time = 0.3

## [ME:CONFIRMED decompile] LookAtAngle = (Pitch -6000): with no target, the
## view is pulled this far below the pawn's level over 0.2 s.
@export var look_at_pitch: float = -6000.0 * (TAU / 65536.0)

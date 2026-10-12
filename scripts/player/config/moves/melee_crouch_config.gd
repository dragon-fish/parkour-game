class_name MeleeCrouchConfig
extends MoveConfig

# The original's TdMove_MeleeCrouch: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_MeleeCrouch].

func _init() -> void:
	# [ME:CONFIRMED ini] SpeedModifier = 0.2.
	speed_modifier = 0.2

## [ME:CONFIRMED decompile] BargeTraceDistance = 120 uu: against a wall the
## crouch kick needs an interactable this close ahead.
@export var barge_trace_distance: float = 1.2

class_name StepUpConfig
extends MoveConfig

# The original's TdMove_StepUp, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_StepUp]. [ME:CONFIRMED decompile] Metric. Only the two height
# bounds are read: the type they would choose is overwritten with Long.

## StepUpLowMinHeight 33 uu .. StepUpHighMaxHeight 148 uu: the hand plant's
## height above the feet.
@export var step_up_low_min_height: float = 0.33
@export var step_up_high_max_height: float = 1.48

func _init() -> void:
	# bConstrainLook, relative to the pawn: pitch -3000 .. 6000, yaw +-8000.
	constrain_look = true
	min_look_constraint = Vector3(-3000.0, -8000.0, -32768.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(6000.0, 8000.0, 32768.0) / UE.UNITS_PER_RADIAN

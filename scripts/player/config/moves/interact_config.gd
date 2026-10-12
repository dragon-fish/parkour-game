class_name InteractConfig
extends MoveConfig

# The original's TdMove_Interact: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Interact].

func _init() -> void:
	# bDisableFaceRotation: the model holds the trigger's facing.
	freeze_visual_yaw = true

## [ME:CONFIRMED ini] DistanceToAButton = 48 uu: where the pawn stands, out
## from the button along the trigger's Y axis.
@export var distance_to_a_button: float = 0.48
## [ME:CONFIRMED ini] DistanceToAValve = 40 uu.
@export var distance_to_a_valve: float = 0.40

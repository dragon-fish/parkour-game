class_name CoilConfig
extends MoveConfig

# The original's TdMove_Coil defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile N5 §3]
#
# No grab, vault or wall-climb switch: the coil reaches for nothing, which is
# what makes it a risk -- and what lets it cross a gap the vault table would
# otherwise catch and slow. CoilTime (0.5 s) is in the ini and read by
# nothing.

## CoilMinTriggerSpeed = 100 uu/s along the pawn's facing.
@export var min_trigger_speed: float = 1.0
## TotalHeightBoost = 60 uu: the lift the coil adds to the arc.
@export var total_height_boost: float = 0.6
## HeightBoostDuration = 0.25 s: the lift is spread over this, at 240 uu/s.
@export var height_boost_duration: float = 0.25

## Seconds the fade into the tuck takes, and out of it. PROJECT-DEFINED
## presentation, read when the body's animation graph is built (see
## Player._exit_blend_time()).
@export var pose_enter_blend_time: float = 0.32
@export var pose_exit_blend_time: float = 0.18
## Seconds a coil's landing keeps the clip already on screen.
## PROJECT-DEFINED presentation, read by CharacterAnimator.
@export var landing_hold_time: float = 0.05

func _init() -> void:
	allows_turn = false
	# [ME:CONFIRMED decompile] Pitch -5000..30000 (-27.5 .. +164.8 degrees),
	# yaw free.
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(27.47), -PI, -PI)
	max_look_constraint = Vector3(deg_to_rad(164.79), PI, PI)

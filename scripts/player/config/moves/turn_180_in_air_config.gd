class_name Turn180InAirConfig
extends MoveConfig

# The original's TdMove_180TurnInAir defaults. [ME:CONFIRMED decompile N5 §8]
# No grab, vault or wall switch; the falling exits are on the move.

func _init() -> void:
	allows_turn = false
	# [ME:CONFIRMED decompile] bConstrainLook, Pitch 0..32768 and Yaw
	# -5000..5000 about the root-rotating pawn; bDisableFaceRotation.
	constrain_look = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(0.0, -deg_to_rad(27.47), -PI)
	max_look_constraint = Vector3(PI, deg_to_rad(27.47), PI)

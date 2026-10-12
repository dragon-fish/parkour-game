class_name SoftLandingConfig
extends MoveConfig

# The original's TdMove_SoftLanding defaults. [ME:CONFIRMED decompile N5 §5]
# No grab, vault or wall switch; its falling exits are on the move.

func _init() -> void:
	allows_turn = false
	# [ME:CONFIRMED decompile] bConstrainLook, Pitch -16384..16384, Yaw
	# -5000..5000 about the pawn; bDisableFaceRotation.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-deg_to_rad(90.0), -deg_to_rad(27.47), -PI)
	max_look_constraint = Vector3(deg_to_rad(90.0), deg_to_rad(27.47), PI)

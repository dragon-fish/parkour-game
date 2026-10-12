class_name MeleeVaultConfig
extends MoveConfig

# The original's TdMove_MeleeVault CDO.

func _init() -> void:
	# [ME:CONFIRMED decompile] bConstrainLook: pitch -3000 .. 6000, yaw
	# -8000 .. 8000 about the pawn, held still by bDisableFaceRotation.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-3000.0, -8000.0, -32768.0) * (TAU / 65536.0)
	max_look_constraint = Vector3(6000.0, 8000.0, 32768.0) * (TAU / 65536.0)

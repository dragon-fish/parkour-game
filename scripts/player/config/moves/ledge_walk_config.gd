class_name LedgeWalkConfig
extends MoveConfig

# The original's TdMove_LedgeWalk, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_LedgeWalk]. [ME:CONFIRMED decompile] What each value does is
# in LedgeWalkMove.

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	freeze_visual_yaw = true
	centre_shoulder = true
	# SpeedModifier 0.1: the walking physics caps the 80 uu/s the move asks
	# for at 72.
	speed_modifier = 0.1
	# bConstrainLook, relative to the pawn: pitch -14000 .. 16384 (the narrow
	# kind -6000 ..), yaw +-10000.
	constrain_look = true
	min_look_constraint = Vector3(-14000.0, -10000.0, -32768.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(16384.0, 10000.0, 32768.0) / UE.UNITS_PER_RADIAN

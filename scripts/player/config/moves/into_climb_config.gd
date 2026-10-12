class_name IntoClimbConfig
extends MoveConfig

# The original's TdMove_IntoClimb, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_IntoClimb]. [ME:CONFIRMED decompile]

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	freeze_visual_yaw = true
	redo_move_time = 0.5

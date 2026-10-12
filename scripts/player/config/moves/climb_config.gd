class_name ClimbConfig
extends MoveConfig

# The original's TdMove_Climb, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Climb]. [ME:CONFIRMED decompile] What each value does is in
# ClimbMove.

## StartTurningAngle, 16384 rotator units: the hands climb only while the view
## is within this of the ladder.
@export var start_turning_angle: int = 16384

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	freeze_visual_yaw = true
	redo_move_time = 0.5
	# bConstrainLook, relative to the pawn: pitch -5000 .. 10000, yaw +-32000.
	constrain_look = true
	min_look_constraint = Vector3(-5000.0, -32000.0, 0.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(10000.0, 32000.0, 0.0) / UE.UNITS_PER_RADIAN

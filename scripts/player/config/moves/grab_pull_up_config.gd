class_name GrabPullUpConfig
extends MoveConfig

# The original's TdMove_GrabPullUp, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_GrabPullUp]. [ME:CONFIRMED decompile] What each value does is
# in GrabPullUpMove.

## GrabAllowedPullUpAngle, 45 (degrees, an int in the original): the view
## must be within this of the wall.
@export var grab_allowed_pull_up_angle: int = 45

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	# This project's presentation, as on the hang: the hands are still on the
	# ledge for the climb, so a chest that twisted with the head would take the
	# arms off it (MoveConfig.allows_spine_twist).
	allows_spine_twist = false
	# bConstrainLook, relative to the pawn: pitch 0 .. 16384, yaw +-10000.
	constrain_look = true
	min_look_constraint = Vector3(0.0, -10000.0, 0.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(16384.0, 10000.0, 0.0) / UE.UNITS_PER_RADIAN

class_name GrabConfig
extends MoveConfig

# The original's TdMove_Grab, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Grab]. [ME:CONFIRMED decompile] Metric. What each value does
# is in GrabMove. The look constraints are the move's own instance state
# (UpdateViewConstraints), not these.

## GrabMaxAngle, 40 degrees: the pawn must face the wall this squarely for the
## catch to become a hang.
@export var grab_max_angle: float = deg_to_rad(40.0)
## GrabDesiredLedgeOffset (30, 0, 92.8) uu: the hang point is X out from the
## wall (plus the box's reach) and Z below the ledge.
@export var grab_desired_ledge_offset_x: float = 0.30
@export var grab_desired_ledge_offset_z: float = 0.928
## HangFreeZDistanceCheck, 128 uu: the leg probe runs this far below the top of
## the body.
@export var hang_free_z_distance_check: float = 1.28
## StartTurningAngle, 16384 rotator units: past this the view turning away
## from the wall plays the hang turn.
@export var start_turning_angle: int = 16384
## DisableShimmyTime, 0.6 s: no shimmy this soon after the catch.
@export var disable_shimmy_time: float = 0.6

# --- this project's probe -------------------------------------------------------
#
# Read by Probes (the debug overlays, the moves not yet ported) and the arena
# builder, never by the grab moves.

## How far ahead the probe looks for a ledge.
@export var ledge_find_distance: float = 3.5
## The highest ledge above the feet the probe reports.
@export var ledge_max_height: float = 2.8
## The lowest wall the probe calls a wall.
@export var min_wall_height: float = 1.8

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	# The drop off a hang counts from the hands.
	fall_counts_from_exit = true
	# The model holds its heading while the view turns; the spine does not twist.
	freeze_visual_yaw = true
	allows_spine_twist = false
	redo_move_time = 0.15
	constrain_look = true
	min_look_constraint = Vector3(-3200.0, -32768.0, 0.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(16000.0, 32768.0, 0.0) / UE.UNITS_PER_RADIAN

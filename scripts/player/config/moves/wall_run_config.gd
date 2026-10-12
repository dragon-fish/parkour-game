class_name WallRunConfig
extends MoveConfig

# The original's TdMove_WallRun, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_WallRun]. [ME:CONFIRMED decompile] Metric: 1 uu = 0.01 m.
# What each value does is in WallRunMove and PawnPhysics.phys_wall_running;
# several names say something else than the value does, and the notes below
# say what it is.

@export_group("Entry")
## WallRunningMinSpeed, 200 uu/s: the entry's horizontal speed floor. It gates
## entry only -- a run has no horizontal minimum once on the wall.
@export var wall_running_min_speed: float = 2.0
## WallRunningForwardCheckDistance, 50 uu: FindWallForward's reach at
## SpeedMaxBaseVelocity, stretched by ContextMoveDistanceMultiplier at speed.
@export var wall_running_forward_check_distance: float = 0.5
## WallRunningStrafeCheckDistance, 50 uu: FindWallSide's reach.
@export var wall_running_strafe_check_distance: float = 0.5
## WallRunningMinWallHeight, 192 uu above the feet: how tall a wall must be.
@export var wall_running_min_wall_height: float = 1.92
## WallRunningForwardMinStartAngle / MaxStartAngle: FindWallForward accepts a
## pawn facing between these angles TO THE WALL PLANE (0..57 degrees).
@export var wall_running_forward_min_start_angle: float = 0.0
@export var wall_running_forward_max_start_angle: float = deg_to_rad(57.0)
## WallRunningStrafeStartAngle, 60 degrees: FindWallSide's wall normal must be
## within this of the pawn's sideways direction.
@export var wall_running_strafe_start_angle: float = deg_to_rad(60.0)
## WallRunningVelocityStartLimit, 300 uu/s: the floor of WallRunningBeginSpeed
## when the run starts rising, and one of the two weights of FindWallSide's
## probe direction.
@export var wall_running_velocity_start_limit: float = 3.0
## WallRunningHorisontalAlignSpeed, 700 uu/s: NOT a speed anything moves at.
## The other weight of FindWallSide's probe direction.
@export var wall_running_horisontal_align_speed: float = 7.0
## WallRunningMoveToIntoPositionDegreeThreshold, 70 degrees: FindWallForward's
## lower bound (70 / 90) on how far its probe direction leans into the wall.
@export var wall_running_move_to_into_position_degree_threshold: float = deg_to_rad(70.0)

@export_group("On the wall")
## WallRunningHorisontalInitialZHeight, 170 uu: the run's apex above the jump's
## take-off point. Applied as an initial vertical speed sqrt(2 h a) against
## WallRunningHorisontalAcceleration, never as a position.
@export var wall_running_horisontal_initial_z_height: float = 1.7
## WallRunningHorisontalAcceleration / Deceleration, 820 / 500 uu/s^2: the
## VERTICAL gravity on the wall, the first while rising, the second while not,
## both times (1 + ConsequtiveWallruns). "Horisontal" is the original's
## misnomer.
@export var wall_running_horisontal_acceleration: float = 8.2
@export var wall_running_horisontal_deceleration: float = 5.0
## WallRunningHorisontalFriction, 0.05 /s: friction on the horizontal speed
## once the wall has been reached. None on the vertical.
@export var wall_running_horisontal_friction: float = 0.05
## WallRunningVelocityStopLimit, -500 uu/s: falling faster than this ends the
## run.
@export var wall_running_velocity_stop_limit: float = -5.0
## WallRunningDelayPawnRotationTime / RotatePawnAlongWallTime: the pawn starts
## turning to face along the wall after 0.01 s and gets there in 0.4 s.
@export var wall_running_delay_pawn_rotation_time: float = 0.01
@export var wall_running_rotate_pawn_along_wall_time: float = 0.4

func _init() -> void:
	redo_move_time = 0.15
	# A kick off the wall counts its fall from where it left the wall. See
	# MoveConfig.fall_counts_from_exit.
	fall_counts_from_exit = true
	# bConstrainLook with bUseAbsoluteYawConstraint: the yaw window is the
	# world one WallRunMove builds from the wall; the pitch is +-13000.
	# Original's sense (yaw positive turning right), radians.
	constrain_look = true
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-13000.0, -16384.0, -32768.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(13000.0, 16384.0, 32768.0) / UE.UNITS_PER_RADIAN
	# Q is the move's own (HandleMoveAction(MA_Turn)), never a turn move.
	allows_turn = false
	# A run along a wall into a pipe or a ladder catches it, as a level built
	# on exactly that requires. The level's interest point, not a switch of
	# the original's.
	check_for_ladder = true

@export_group("Presentation")

## How much of the model head's own offset the first-person eye follows
## during a wall run. 1.0 is the global follow; 0 pins the eye to its
## procedural position. Tuned by eye at 0.75: below it the neck comes into
## frame looking down, above it the lean rides the view.
@export_range(0.0, 1.0) var head_follow_scale: float = 0.75

## How far the first-person eye slides AWAY FROM the wall during a run,
## metres. The wall-run clip offset (scenes/player/tuning/*.json) holds the
## model out from the wall so the feet stay out of it, and the eye is moved by
## the matching amount so looking down shows the body where it is. Tuned by
## eye; DO NOT reach for head_follow_scale instead, which scales the head
## bone's own animated motion.
@export var eye_off_wall: float = 0.7

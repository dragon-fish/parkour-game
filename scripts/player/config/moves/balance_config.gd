class_name BalanceConfig
extends MoveConfig

# The original's TdMove_Balance, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Balance]. [ME:CONFIRMED decompile] What each value does is in
# BalanceMove.

## TimeToCounter, 0.8 s: how long the lean may stay at the stop.
@export var time_to_counter: float = 0.8
## GravityInfluence 0.3, ControlInfluence 1.5, SpeedInfluence 2.5,
## CameraInfluence 0.3: the balance factor's terms.
@export var gravity_influence: float = 0.3
@export var control_influence: float = 1.5
@export var speed_influence: float = 2.5
@export var camera_influence: float = 0.3

# --- presentation ---------------------------------------------------------------
#
# This project's: how the lean is shown. The balance factor, -1 .. 1, scales
# each.

## The camera's roll at a full lean, degrees, tipping toward the fall.
@export var max_camera_roll_deg: float = 40.0
## The largest torso lean the skeleton shows, degrees, and the share of it the
## hips take (small: the feet hang off them, and there is no leg IK).
@export var max_body_lean_deg: float = 18.0
@export var hips_lean_share_deg: float = 4.0
## How far the FOV closes in at a full lean, degrees.
@export var fov_squeeze_deg: float = 10.0

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	freeze_visual_yaw = true
	speed_modifier = 0.34
	redo_move_time = 0.5
	# bConstrainLook, relative to the pawn: pitch -13000 .. 25000, yaw +-6000.
	constrain_look = true
	min_look_constraint = Vector3(-13000.0, -6000.0, -32768.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(25000.0, 6000.0, 32768.0) / UE.UNITS_PER_RADIAN

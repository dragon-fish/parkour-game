class_name MeleeWallrunConfig
extends MoveConfig

# The original's TdMove_MeleeWallrun (and TdMove_MeleeBase), CDO.
# [ME:CONFIRMED decompile] Movement and animation only: this project deals no
# melee damage.

## The kick's turn off the wall with no target: the velocity rotated by 6000
## rotator units (about 33 degrees) away from the wall, then scaled.
@export var turn_off_wall: float = 6000.0 / UE.UNITS_PER_RADIAN
@export var speed_scale: float = 1.2
## How long the kick lasts: MeleeWallRunLeft / MeleeWallRunRight in the
## first-person set, 0.833 s and 0.767 s at rate 1. OnCustomAnimEnd ends it.
@export var left_kick_time: float = 0.833
@export var right_kick_time: float = 0.767

func _init() -> void:
	# bConstrainLook, relative to the pawn: pitch -3000 .. 16000, yaw +-8000.
	# Original's sense (yaw positive turning right), radians.
	constrain_look = true
	min_look_constraint = Vector3(-3000.0, -8000.0, 0.0) / UE.UNITS_PER_RADIAN
	max_look_constraint = Vector3(16000.0, 8000.0, 0.0) / UE.UNITS_PER_RADIAN

class_name ZiplineConfig
extends MoveConfig

# The original's TdMove_ZipLine: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_ZipLine]. Lengths in metres, speeds in m/s.

func _init() -> void:
	# MG_TwoHandsBusy: both hands on the cable.
	allows_turn = false
	hit_knocks_off = true
	holds_world_path = true
	# [ME:CONFIRMED decompile] bConstrainLook: pitch -3200 .. 32768, yaw
	# -7000 .. 7000 about the pawn, which bDisableFaceRotation holds at the
	# cable's heading -- so the fan is pinned to the cable, and the model does
	# not turn with the view.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-3200.0, -7000.0, -32768.0) * (TAU / 65536.0)
	max_look_constraint = Vector3(32768.0, 7000.0, 32768.0) * (TAU / 65536.0)

## [ME:CONFIRMED decompile] HangOffset = (0, 0, -90): the hands are 90 uu
## above the pawn's centre.
@export var hang_offset: float = 0.9
## [ME:CONFIRMED ini] MinZipVelocity = 300 uu/s: the floor of the step taken
## along the cable each frame, and of the velocity written.
@export var min_zip_velocity: float = 3.0
## [ME:CONFIRMED ini] MinZipAcceleration = 400 uu/s^2: the floor of the
## acceleration along the cable, against max(it, |GravityZ * slope|).
@export var min_zip_acceleration: float = 4.0

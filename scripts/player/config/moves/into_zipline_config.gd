class_name IntoZiplineConfig
extends MoveConfig

# The original's TdMove_IntoZipLine: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_IntoZipLine], plus TdZiplineVolume's LandingStrip.

func _init() -> void:
	# [ME:CONFIRMED ini] RedoMoveTime = 0.5.
	redo_move_time = 0.5
	allows_turn = false
	# [ME:CONFIRMED decompile] bConstrainLook: pitch -2500 .. 32768, yaw
	# -7000 .. 7000 about the pawn, which the reach turns to the cable.
	constrain_look = true
	min_look_constraint = Vector3(-2500.0, -7000.0, -32768.0) * (TAU / 65536.0)
	max_look_constraint = Vector3(32768.0, 7000.0, 32768.0) * (TAU / 65536.0)

## [ME:CONFIRMED decompile] HangOffset = (0, 0, -90).
@export var hang_offset: float = 0.9
## [ME:CONFIRMED ini] ZVelocityFallLimit = -600 uu/s: arriving faster than
## this downward, the run-up's speed is not carried onto the cable.
@export var z_velocity_fall_limit: float = -6.0
## [ME:CONFIRMED decompile] SameZipLineRedoMoveTime = 3.0 s: the cable just
## left, counted from the ride's own stop, refuses the reach.
@export var same_zipline_redo_move_time: float = 3.0
## [ME:CONFIRMED decompile] TdZiplineVolume.LandingStrip = 500 uu: no reach
## within this of the cable's last point, flat distance. A per-volume value in
## the original; no InterestLine carries one, so every cable has the default.
@export var landing_strip: float = 5.0
## [ME:CONFIRMED decompile] IntoClimbSpeed's floor, 400 uu/s.
@export var min_reach_speed: float = 4.0
## [ME:CONFIRMED decompile] The reach aims 100 uu down the cable from the
## nearest point.
@export var reach_ahead: float = 1.0

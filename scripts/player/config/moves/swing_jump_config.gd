class_name SwingJumpConfig
extends MoveConfig

# The original's TdMove_SwingJump: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_SwingJump].

func _init() -> void:
	# [ME:CONFIRMED ini] bCheckForWallClimb, bCheckForGrab, bCheckForVaultOver.
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# [ME:CONFIRMED decompile] bConstrainLook: pitch -11000 .. 16384, yaw and
	# roll a full turn.
	constrain_look = true
	min_look_constraint = Vector3(-11000.0, -32768.0, -32768.0) * (TAU / 65536.0)
	max_look_constraint = Vector3(16384.0, 32768.0, 32768.0) * (TAU / 65536.0)

## [ME:CONFIRMED ini] GravityModifier 0.73 for GravityModifierTimer 0.75 s,
## on the flight to a target bar only.
@export var gravity_modifier: float = 0.73
@export var gravity_modifier_timer: float = 0.75
## [ME:CONFIRMED ini] TargetVolumeOffset = (-120, 0, -20) uu: the flight lands
## 1.2 m short of the target bar's centre along the line to it, 0.2 m down.
@export var target_offset_along: float = -1.2
@export var target_offset_up: float = -0.2

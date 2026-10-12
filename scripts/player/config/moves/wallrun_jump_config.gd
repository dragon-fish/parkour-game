class_name WallrunJumpConfig
extends MoveConfig

# The original's TdMove_WallrunJump, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_WallrunJump]. [ME:CONFIRMED decompile] Metric.
#
# p = the wall's normal . the camera's flat direction (1 after a Q turn) is the
# whole of the jump's "skill": every term below is weighted by it, and it is
# NOT clamped to [0, 1] -- the original's FMax(0, p) throws its result away.

## WallRunningPushAwaySpeedNoob + p x ProAdd: the push along the wall normal,
## 120 + 400 p uu/s.
@export var wall_running_push_away_speed_noob: float = 1.2
@export var wall_running_push_away_speed_pro_add: float = 4.0
## WallRunningPushForwardSpeedMin, 0.1: the share of the along-wall speed kept,
## 0.1 + 0.9 (1 - p).
@export var wall_running_push_forward_speed_min: float = 0.1
## WallRunningJumpOffZHeightForward + p x MaxAddTurned: the jump's height,
## 100 + 60 p uu, divided by (1 + ConsequtiveWallruns) as a speed.
@export var wall_running_jump_off_z_height_forward: float = 1.0
@export var wall_running_jump_off_z_height_max_add_turned: float = 0.6

func _init() -> void:
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# bUseAbsoluteYawConstraint with a window StartMove builds; bConstrainLook
	# is NOT set, so the window is never applied. Kept as the original has it.
	absolute_yaw_constraint = true

class_name WallClimb180TurnJumpConfig
extends MoveConfig

# The original's TdMove_WallClimb180TurnJump, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_WallClimb180TurnJump]. [ME:CONFIRMED decompile] Metric.

## JumpOffZHeight, 250 uu: the jump's height, as a speed under the script's
## gravity: 2 g sqrt(h / g).
@export var jump_off_z_height: float = 2.5
## JumpPushAwaySpeed, 400 uu/s: straight off the wall.
@export var jump_push_away_speed: float = 4.0
## JumpTimeWindow, 0.6 s: how long a jump press is taken, and when the turn
## hands over to the jump's own facing.
@export var jump_time_window: float = 0.6

func _init() -> void:
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	redo_move_time = 1.0
	# The level's interest points, as Jump has them.
	check_for_zipline = true
	check_for_swing = true
	check_for_ladder = true
	check_for_ledge_walk = true
	check_for_balance = true

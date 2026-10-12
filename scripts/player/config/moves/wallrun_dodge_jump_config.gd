class_name WallrunDodgeJumpConfig
extends MoveConfig

# The original's TdMove_WallrunDodgeJump, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_WallrunDodgeJump]. [ME:CONFIRMED decompile] Metric.

## BaseJumpZ, 300 uu/s: the vertical speed, replaced outright.
@export var base_jump_z: float = 3.0
## JumpAddXY, 600 uu/s: the push sideways off the pawn's facing, away from the
## wall.
@export var jump_add_xy: float = 6.0
## DodgeJumpInertiaConservation, 0.3: the share of the velocity kept.
@export var dodge_jump_inertia_conservation: float = 0.3

func _init() -> void:
	# bCheckForGrab and bCheckForVaultOver cleared by the ini; no wall climb.
	# The level's interest points, as Jump has them.
	check_for_ladder = true
	check_for_ledge_walk = true
	check_for_balance = true

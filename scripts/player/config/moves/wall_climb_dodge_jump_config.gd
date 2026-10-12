class_name WallClimbDodgeJumpConfig
extends MoveConfig

# The original's TdMove_WallClimbDodgeJump, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_WallClimbDodgeJump]. [ME:CONFIRMED decompile] Metric.

## BaseJumpZ, 700 uu/s: the vertical speed, replaced outright.
@export var base_jump_z: float = 7.0
## JumpAddXY, 150 uu/s: the push sideways off the pawn's facing.
@export var jump_add_xy: float = 1.5
## DodgeJumpInertiaConservation, 1.0: the velocity is kept whole.
@export var dodge_jump_inertia_conservation: float = 1.0
## How long StartMove clears the grab, vault and wall-climb switches.
@export var auto_checks_off_time: float = 0.5

func _init() -> void:
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# The level's interest points, as Jump has them.
	check_for_ladder = true
	check_for_ledge_walk = true
	check_for_balance = true

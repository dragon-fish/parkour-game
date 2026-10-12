class_name DodgeJumpConfig
extends MoveConfig

# The original's TdMove_DodgeJump defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile N5 §9] No grab, vault or wall switch: a dodge
# reaches for nothing. StrafeThreshold (0.99) is in the ini and read by
# nothing; the gate is the hint's bMoveActionMax (raw strafe past 0.96).

## BaseJumpZ = 300 uu/s, the launch's vertical speed.
@export var base_jump_z: float = 3.0
## JumpAddXY = 600 uu/s along the pawn's right or left.
@export var jump_add_xy: float = 6.0
## DodgeJumpInertiaConservation = 0.3: the share of the velocity kept under
## the launch.
@export var inertia_conservation: float = 0.3

func _init() -> void:
	# [ME:CONFIRMED ini] RedoMoveTime = 0.3.
	redo_move_time = 0.3
	allows_turn = false

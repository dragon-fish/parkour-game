class_name SpringBoardConfig
extends MoveConfig

# The original's TdMove_SpringBoard defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile] The terrain decides where a spring board is: the
# ledge the jump press found in front of the body is the first foot plant, and
# a second ledge IntermediateFootPlantDistance further on, between
# SpringBoardMinHeight and SpringBoardMaxHeight above the feet, is the second.

## SpringBoardJumpZ = 950 uu/s, the launch's vertical speed.
@export var jump_z: float = 9.5
## SpringBoardJumpXYAdd = -100 uu/s on the speed the body arrived with.
@export var xy_add: float = -1.0
## SpringBoardJumpXYMin = 400 uu/s, the least horizontal launch speed.
@export var xy_min: float = 4.0
## IntermediateFootPlantHeight = 64 uu above the feet, +-20 uu.
@export var plant_1_height: float = 0.64
## IntermediateFootPlantDistance = 112 uu from the first plant to the second,
## +-20 uu along the second's face normal.
@export var plant_spacing: float = 1.12
## SpringBoardMinHeight / SpringBoardMaxHeight: the second plant's band above
## the feet.
@export var plant_2_min_height: float = 0.8
@export var plant_2_max_height: float = 1.48
## CheckDistanceTime = 1.0 s: the first plant must be reached within this at
## the body's average speed over the last quarter second.
@export var check_distance_time: float = 1.0
## StepTime1 / StepTime2 = 0.2 s each: the two flights onto the plants.
@export var step_time_1: float = 0.2
@export var step_time_2: float = 0.2

func _init() -> void:
	# [ME:CONFIRMED ini] bCheckForGrab, bCheckForVaultOver, bCheckForWallClimb,
	# all held off for the first 0.7 s (bDelayTimeCheckAutoMoves, on the move).
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# The level's interest points, asked with the switches above.
	check_for_ladder = true
	check_for_ledge_walk = true
	check_for_balance = true
	# [ME:CONFIRMED decompile] PlayerWalking and no bConstrainLook: the view is
	# free throughout, and the throw goes the way the pawn faces at launch.
	allows_turn = false

class_name Turn180Config
extends MoveConfig

# The original's TdMove_180Turn defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile] DisableMovementTime (0.3) is on the move. TurnTime
# (0.25) is in the ini and read by nothing: the turn's length is the
# animation's.

func _init() -> void:
	# [ME:CONFIRMED ini] FrictionModifier 0.3, RedoMoveTime 0.5.
	friction_modifier = 0.3
	redo_move_time = 0.5
	allows_turn = false
	# [ME:CONFIRMED decompile] Pitch -10000..10000, Yaw -16384..16384 about the
	# pawn. Absolute, so the fan carries the root rotation round (HalfTurn).
	constrain_look = true
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-deg_to_rad(54.93), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(54.93), deg_to_rad(90.0), PI)

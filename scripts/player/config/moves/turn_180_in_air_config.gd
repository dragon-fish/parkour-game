class_name Turn180InAirConfig
extends MoveConfig

# The original's TdMove_180TurnInAir: Q in mid-air, off no wall.
#
# [ME:CONFIRMED 11 §11.2] its whole capability list is ExitToUncontrolledFalling
# and ForSoftLanding. Nothing reaches for a ledge, a vault or a wall, so the
# three probe flags stay at MoveConfig's neutral false.

func _init() -> void:
	# Already turning, and in the air: Q again is nothing.
	allows_turn = false
	# The same fan as the ground turn, and needed for the same reason: HalfTurn
	# carries the body round by moving an ABSOLUTE yaw fan's reference. Without
	# a fan there is nothing to move and the body does not turn.
	constrain_look = true
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-deg_to_rad(55.0), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(55.0), deg_to_rad(90.0), PI)

## How long the body takes to come round, seconds.
## [ME:UNKNOWN] not measured in the air; borrowed from the ground turn's
## confirmed 0.3 (Turn180Config.turn_time).
@export var turn_time: float = 0.3

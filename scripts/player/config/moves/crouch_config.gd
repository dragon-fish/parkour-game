class_name CrouchConfig
extends MoveConfig

# The original's TdMove_Crouch defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile N5 §2] The crouched collision itself is the pawn's
# (PawnConfig.custom_collision_height), shared by every move that uses it.

## The collision height the moves not yet ported fold the body to (the hang's
## pull-up into a duct, the vault, the reach). Not read by Crouch.
@export var crouch_capsule_height: float = 0.9

func _init() -> void:
	# [ME:CONFIRMED ini] SpeedModifier = 0.2: the walking physics caps a
	# crouch at GroundSpeed x 0.2, 1.44 m/s.
	speed_modifier = 0.2
	# [ME:CONFIRMED decompile] Pitch -14000..14000 (+-76.9 degrees), yaw free.
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(76.9), -PI, -PI)
	max_look_constraint = Vector3(deg_to_rad(76.9), PI, PI)

class_name SkillRollConfig
extends MoveConfig

# The original's TdMove_SkillRoll defaults. [ME:CONFIRMED decompile] The CDO
# carries no duration, distance or speed: the roll is fallinglandroll's root
# motion (RootMotionClip.skill_roll()).

## The view's tumble over the roll, radians, and how far the eye dips through
## it (a crouch amount). PROJECT-DEFINED presentation.
@export var camera_spin: float = TAU
@export var camera_crouch: float = 1.0

func _init() -> void:
	allows_turn = false
	# [ME:CONFIRMED decompile] bConstrainLook, Pitch -2000..32768, Yaw
	# -5000..5000 about the pawn; bDisableFaceRotation.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-deg_to_rad(10.99), -deg_to_rad(27.47), -PI)
	max_look_constraint = Vector3(PI, deg_to_rad(27.47), PI)
	third_person_frees_look = true

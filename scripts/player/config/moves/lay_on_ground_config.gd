class_name LayOnGroundConfig
extends MoveConfig

# The original's TdMove_LayOnGround defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile] Reached by Landing's backwards landing and by this
# project's KNOCKDOWN status (the original's SeqAct_TdFallOnBack).

## How long the tint a blow or a hard landing left fades over while the body
## lies there, seconds. PROJECT-DEFINED presentation.
@export var tint_fade_time: float = 0.6
## The pitch CEILING in third person, degrees; the first-person floor does not
## apply there. The camera hangs behind the rig, so looking up swings it down
## into the floor the body is lying on. PROJECT-DEFINED presentation (see
## LayOnGroundMove.third_person_pitch_limits()).
@export var third_person_pitch_max_deg: float = -10.0

func _init() -> void:
	# [ME:CONFIRMED ini] FrictionModifier = 0.15.
	friction_modifier = 0.15
	allows_turn = false
	freeze_visual_yaw = true
	constrain_look = true
	absolute_yaw_constraint = true
	# [ME:CONFIRMED decompile] Yaw -5000..5000 (27.5 degrees) about the pawn.
	#
	# The pitch floor is 30 degrees below level, lower than the CDO's -2000
	# (11 degrees): the body scene props itself on its hands (LyingPose) and
	# the eye is lifted over it (lay_on_ground_eye_lift), so looking down looks
	# along the body. First person only -- see third_person_pitch_max_deg.
	min_look_constraint = Vector3(deg_to_rad(-30.0), -0.479, -PI)
	max_look_constraint = Vector3(PI, 0.479, PI)

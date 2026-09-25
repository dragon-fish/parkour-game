class_name LayOnGroundConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_LayOnGround: the body is on
# its back, and gets up when the player says so. Reached three ways -- a
# forward jump turned round in the air and landed on (Turn180Move), a level's
# script (Status.Effect.KNOCKDOWN; the original's SeqAct_TdFallOnBack), and an
# enemy's shove, which this project has nobody to give.
#
# NOT THE HARD LANDING. LandingMove is a lockout that ends on its own and
# refuses everything; this one slides, waits for the player, and ends with a
# get-up. The original keeps them apart too (TdMove_Landing), and folding a
# scripted knock-down into the hard landing left it with the wrong clip, the
# wrong camera and no way up but the clock.

## How hard the floor brakes the body while it lies there, in m/s^2.
##
## [ME:CONFIRMED A1 TdMove_LayOnGround] FrictionModifier = 0.15: the body
## SLIDES on, a back landing carries its jump across the floor. The modifier
## is confirmed, this figure is PROJECT-DEFINED -- this project's ground
## friction is not the original's, so the ratio does not carry over as a
## number.
@export var slide_deceleration: float = 6.0
## How long the body is down before a key is heard. PROJECT-DEFINED: the clip
## of going down has to have mostly played, or the get-up starts from a body
## still in the air.
@export var min_down_time: float = 0.6
## How long getting up takes. PROJECT-DEFINED; UAL2's KipUp is 1.17 s long.
@export var get_up_time: float = 1.1
## The pitch CEILING in third person, degrees; the first-person floor does not
## apply there. The camera hangs behind the rig, so looking up swings it down
## into the floor the body is lying on -- the view is held this far below level
## at most, and eased down to it when it arrives higher. See
## LayOnGroundMove.third_person_pitch_limits().
@export var third_person_pitch_max_deg: float = -10.0
## Capsule height while down. The slide's own, so that anywhere a slide ends
## under a low ceiling this fits as well.
@export var capsule_height: float = 0.9

func _init() -> void:
	# On its back: nothing to spin on.
	allows_turn = false
	freeze_visual_yaw = true
	constrain_look = true
	# ABSOLUTE, for LandingConfig's reason: measured against the body's own
	# facing a relative clamp is a rate limit and no clamp at all.
	absolute_yaw_constraint = true
	# [ME:CONFIRMED A1 TdMove_LayOnGround] Min/MaxLookConstraint yaw is
	# +-5000 of 65536, 27.5 degrees.
	#
	# The pitch floor is 10 degrees below level, a degree short of the CDO's
	# -2000. The body props itself up on its hands (the body scene's LyingPose),
	# so a little below level looks along it; lying flat it would look into
	# it, and a body posed flat wants this back above level. A view that
	# arrives lower is eased up to the floor by CameraRig.apply_look(), not
	# snapped. First person only -- see third_person_pitch_max_deg.
	min_look_constraint = Vector3(deg_to_rad(-10.0), -0.479, -PI)
	max_look_constraint = Vector3(PI, 0.479, PI)

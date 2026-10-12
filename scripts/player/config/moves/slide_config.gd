class_name SlideConfig
extends MoveConfig

# The original's TdMove_Slide defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile N5 §1]

## SlideAbortSpeed = 250 uu/s: under this (3D) the slide aborts to Crouch.
@export var slide_abort_speed: float = 2.5
## MaxFloorInclineZ = 0.5: an UPHILL entry limit, sin(slope) x the velocity's
## alignment with the uphill direction. Downhill is unlimited.
@export var max_floor_incline_z: float = 0.5
## SlideAbortTime = 2.0 is in the CDO and the ini and is read by nothing,
## script or native: a slide has no time limit. Not carried.

## The stand-up after a slide, seconds: the eye rising
## (Player.begin_slide_recovery()). PROJECT-DEFINED presentation; the
## original's is the CrouchSlideToCrouch animation. DO NOT hold the slide's
## look clamp over it: TdMove.StopMove ends the clamp with the move.
@export var recovery_time: float = 1.0

func _init() -> void:
	# [ME:CONFIRMED ini] FrictionModifier = 0.1. With the slide friction scales
	# this is the whole of what slows a slide.
	friction_modifier = 0.1
	# [ME:CONFIRMED decompile] bConstrainLook, Pitch and Yaw -10000..10000
	# about the pawn: +-54.9 degrees. bDisableFaceRotation keeps the pawn's own
	# facing apart from the view's, which is the absolute fan here.
	constrain_look = true
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-deg_to_rad(54.93), -deg_to_rad(54.93), -PI)
	max_look_constraint = Vector3(deg_to_rad(54.93), deg_to_rad(54.93), PI)
	# The model's legs do not swing round under the view. See
	# MoveConfig.freeze_visual_yaw.
	freeze_visual_yaw = true
	# No steps are taken on the floor: see MoveConfig.footfall_bob.
	footfall_bob = false
	# The original's Q is MA_Turn, which a slide's row in the action table
	# does not have.
	allows_turn = false

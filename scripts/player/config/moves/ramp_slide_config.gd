class_name RampSlideConfig
extends MoveConfig

# The original's TdMove_RumpSlide defaults (CDO and DefaultPawnMovement.ini).
# [ME:CONFIRMED decompile N5 §4] Only a surface whose material carries the
# uncontrolled-slide mark starts it; the level builder turns that mark into
# Probes.UNCONTROLLED_SLIDE_GROUP.

## MaxSlideSpeed = 1000 uu/s: PrePhysics caps the speed here.
@export var max_slide_speed: float = 10.0
## SideControl = 350 uu/s^2, times sin(slope): what a strafe hint pushes
## across the fall line.
@export var side_control: float = 3.5
## GravityModifier = 0.5, for the slide's length.
@export var gravity_modifier: float = 0.5
## InitialSpeedLoss = 0.75: the arriving speed is MULTIPLIED by this (and by
## sin(slope), the fall line's length) on entry.
@export var initial_speed_loss: float = 0.75
## MinSlideFloorZ = 0.9: the pawn's walkable floor normal for the slide's
## length, and the flattest chute the slide starts on.
@export var min_slide_floor_z: float = 0.9

func _init() -> void:
	# [ME:CONFIRMED ini] RedoMoveTime = 1.0.
	redo_move_time = 1.0
	# [ME:CONFIRMED decompile] bConstrainLook, Pitch and Yaw -5000..5000
	# (+-27.5 degrees) about the pawn; bDisableFaceRotation.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	footfall_bob = false
	allows_turn = false
	min_look_constraint = Vector3(-deg_to_rad(27.47), -deg_to_rad(27.47), -PI)
	max_look_constraint = Vector3(deg_to_rad(27.47), deg_to_rad(27.47), PI)

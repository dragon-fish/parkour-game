class_name RampSlideConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_RumpSlide: the seated,
# uncontrolled slide down a chute the level marked for it. Not a terrain rule:
# an ordinary slope too steep to stand on is either crept down or fallen off.
# Only a surface whose material carries bEnableUncontrolledSlide (its
# PhysMaterial's TdPhysicalMaterialProperty) starts this, which the level
# builder turns into Probes.UNCONTROLLED_SLIDE_GROUP on that surface's body.

## [ME:CONFIRMED A1] MaxSlideSpeed = 1000 uu/s. The slide never goes faster
## than this along the surface, however long the chute.
@export var max_slide_speed: float = 10.0
## [ME:CONFIRMED A1] SideControl = 350 uu/s^2: the acceleration across the
## slide that A and D buy. A nudge, not a steer.
@export var side_control: float = 3.5
## [ME:CONFIRMED A1] GravityModifier = 0.5: the slide pulls down the chute at
## half gravity, which is what keeps a 30 m chute from ending at terminal
## velocity.
@export var gravity_modifier: float = 0.5
## [ME:CONFIRMED A1] InitialSpeedLoss = 0.75. [ME:INFERRED] read as the share
## of the arriving speed that is LOST on sitting down, so a quarter is kept.
@export var initial_speed_loss: float = 0.75
## [ME:CONFIRMED A1] MinSlideFloorZ = 0.9. [ME:INFERRED] read as the floor
## normal at which the slide ends: a surface flatter than this (under 26
## degrees) is a floor to stand up on, whatever its material says.
@export var min_slide_floor_z: float = 0.9
## PROJECT-DEFINED. How long the body may lose contact with the chute before
## the slide is a fall: seams between chute meshes part the capsule from the
## surface for a tick or two. At the chute's end the contact stays lost and
## the body flies.
@export var contact_grace: float = 0.12
## PROJECT-DEFINED. [ME:CONFIRMED A1] RootOffset z = 20 uu lowers the model;
## the seated body is as tall as the crouch, so the same capsule height.
@export var capsule_height: float = 0.9


func _init() -> void:
	# [ME:CONFIRMED A1] bDisableFaceRotation: the body faces down the chute.
	allows_turn = false  # seated, carried: which way you face is the chute's business.
	# [ME:CONFIRMED A1] RedoMoveTime = 1.0: off the chute, a second before the
	# same surface can take the body again.
	redo_move_time = 1.0
	# [ME:CONFIRMED A1] bConstrainLook with MinLookConstraint (-5000, -5000, 0):
	# UE3 integer angles at 65536 = 360 degrees -> +-27.5 degrees on pitch and
	# yaw, about the slide's own facing (see SlideConfig for why absolute).
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-deg_to_rad(27.5), -deg_to_rad(27.5), -PI)
	max_look_constraint = Vector3(deg_to_rad(27.5), deg_to_rad(27.5), PI)

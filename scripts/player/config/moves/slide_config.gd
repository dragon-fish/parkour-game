class_name SlideConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Slide.

## Source: 05 §5.1 `SlideAbortSpeed = 250` uu/s. ✅ Below this a slide ends.
## Also serves as the ENTRY gate: entering under it would abort on the very
## next tick anyway, so the original needs no separate minimum and neither do
## we (the old `slide_entry_speed = 4.0` was this project's own invention).
@export var slide_abort_speed: float = 2.5
## Source: 05 §5.1 `SlideAbortTime = 2.0` s. ✅
@export var slide_abort_time: float = 2.0
## Source: 05 §5.1 `MaxFloorInclineZ = 0.5`. ✅ Steeper than ~60 degrees and
## the surface cannot be slid on at all.
@export var max_floor_incline_z: float = 0.5
## Project-specific, no counterpart in the original: the capsule size and how
## fast the line can be steered.
@export var slide_capsule_height: float = 0.9
@export var slide_steer_rate: float = 1.2
## Project-specific SAFETY VALVE, not a feel knob. A slide that stops under a
## ceiling too low to stand up in has no exit at all -- every route back is
## gated on headroom and nothing in this move generates speed. The original
## has other outlets (LayOnGround and friends) that this project does not.
@export var slide_crawl_speed: float = 2.5

func _init() -> void:
	# Source: 05 §5.1 `FrictionModifier = 0.1`. ✅ The whole of what a slide
	# does to speed: it PRESERVES it by cutting friction to a tenth. There is
	# no acceleration term anywhere in TdMove_Slide, which is why the
	# community calls it the slowest move in the game.
	friction_modifier = 0.1
	# Source: 05 §5.1 `MinLookConstraint = (-10000, -10000, 0)`, UE3 integer
	# angles at 65536 = 360 degrees -> +-54.9 degrees on pitch and yaw. ✅
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(54.9), -deg_to_rad(54.9), -PI)
	max_look_constraint = Vector3(deg_to_rad(54.9), deg_to_rad(54.9), PI)

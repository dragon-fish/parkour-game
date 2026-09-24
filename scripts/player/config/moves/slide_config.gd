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
## The shortest slide a press buys, seconds: let go of the key sooner and the
## slide runs on to here. Speed still ends it early -- slide_abort_speed is not
## held off by this.
## [ME:INFERRED] from play in the original.
@export var min_duration: float = 0.5
## Source: 05 §5.1 `MaxFloorInclineZ = 0.5`. ✅ as a value. RECORDED BUT NOT
## ENFORCED -- nothing reads this yet, the same pattern as
## PawnConfig.speed_max_base_velocity. In the original this would reject a
## slide on a surface steeper than ~60 degrees; here it is on file for
## whichever later task wires floor-incline gating into SlideMove, not a live
## gate today. Do not read behaviour into this field's mere presence.
@export var max_floor_incline_z: float = 0.5
## Project-specific, no counterpart in the original: the capsule size and how
## fast the line can be steered.
@export var slide_capsule_height: float = 0.9

## Radians per second the slide's line may be turned by the input. ZERO, so a
## slide holds the direction it launched on and cannot be aimed once it has
## started -- the same absolute-vector rule the dodge follows.
##
## THE LOOK CLAMP DOES NOT COVER THIS, which is why it read as a bug rather
## than as a dial. The clamp bounds how far the view may turn; the steering
## reads wish_direction(), which is RELATIVE to the view -- so any yaw the
## clamp still allows was a slice of steering the slide would accept. The two
## limit different things and only this one aims the body.
##
## Turn it back up for a slide that can be nudged; there is nothing in the
## original arguing either way, because the original has no such control.
@export var slide_steer_rate: float = 0.0
## Project-specific SAFETY VALVE, not a feel knob. A slide that stops under a
## ceiling too low to stand up in has no exit at all -- every route back is
## gated on headroom and nothing in this move generates speed. The original
## has other outlets (LayOnGround and friends) that this project does not.
@export var slide_crawl_speed: float = 2.5

## ⚠️ PROJECT-DEFINED, borrowed from `TdMove_RumpSlide.RedoMoveTime = 1.0`.
## The stand-up after a slide, seconds: the eye rising, the speed budget not
## banking, the slide's look clamp still holding (Player.begin_slide_recovery()).
## NOT the re-entry cooldown -- that is redo_move_time, set below.
@export var recovery_time: float = 1.0

func _init() -> void:
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # legs busy: on the floor, mid-slide.
	# [ME:INFERRED] from play: a crouch pressed within this of a slide ending
	# CROUCHES rather than sliding again -- see WalkingMove's crouch branch --
	# so a stray second press on the way out of one costs the pace a crouch
	# costs. Shorter than the stand-up on purpose; recovery_time is not a
	# cooldown.
	redo_move_time = 0.5
	# Source: 05 §5.1 `FrictionModifier = 0.1`. ✅ The whole of what a slide
	# does to speed: it PRESERVES it by cutting friction to a tenth. There is
	# no acceleration term anywhere in TdMove_Slide, which is why the
	# community calls it the slowest move in the game.
	friction_modifier = 0.1
	# Source: 05 §5.1 `MinLookConstraint = (-10000, -10000, 0)`, UE3 integer
	# angles at 65536 = 360 degrees -> +-54.9 degrees on pitch and yaw. ✅
	constrain_look = true
	# ✅ The owner: during a slide the legs must not swing round under the view.
	# See MoveConfig.freeze_visual_yaw.
	freeze_visual_yaw = true
	# No steps are taken on the floor: see MoveConfig.footfall_bob.
	footfall_bob = false
	# ✅ THE YAW WAS NEVER ACTUALLY LIMITED, and the owner found it in play: "I
	# forgot the slide's yaw clamp -- it can still turn freely." Both halves of
	# the measured pair were here, and the yaw half did nothing, because a
	# RELATIVE constraint is a per-tick rate limit by construction (see
	# CameraRig.apply_look). +-54.9 degrees PER FRAME is no limit at all.
	#
	# Absolute makes the measured number mean what it was measured to mean: a
	# fan of that size around the facing the slide began at. Grab, Landing,
	# SkillRoll, Turn180 and WallRun all declare it; this one was simply missed.
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-deg_to_rad(54.9), -deg_to_rad(54.9), -PI)
	max_look_constraint = Vector3(deg_to_rad(54.9), deg_to_rad(54.9), PI)

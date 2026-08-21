class_name SkillRollConfig
extends MoveConfig

# The original's TdMove_SkillRoll: the roll that turns a landing which would
# otherwise have cost everything into one that costs almost nothing.
#
# Its CDO is short, and worth quoting in full because it is the whole of what
# is confirmed about this move:
#
#     ControllerState        PlayerGrabbing
#     bConstrainLook         True
#     bDisableFaceRotation   True
#     bAvoidLedges           False
#     MovementGroup          MG_TwoHandsBusy
#     AimMode                MAM_Right
#     MinLookConstraint      (-2000, -5000, -32768)
#     MaxLookConstraint      (32768, 5000, 32768)
#
# There is NO duration, NO distance, and NO speed in it. Everything below that
# is not a look constraint is this project's own, and marked as such.

func _init() -> void:
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # legs busy: mid-roll.
	# ✅ MinLookConstraint / MaxLookConstraint, at 65536 units = 360 degrees:
	# pitch -11.0 .. +180, yaw +-27.5, roll unconstrained. The lopsided pitch
	# is the roll itself -- the view is allowed to sweep all the way up and
	# over, but barely below level.
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(11.0), -deg_to_rad(27.5), -PI)
	max_look_constraint = Vector3(PI, deg_to_rad(27.5), PI)
	# ⚠️ The CDO says bDisableFaceRotation, which this project does not
	# implement yet (docs/feel-backlog.md 12). Absolute yaw is the closest
	# available stand-in: with the body's facing pinned, the original's
	# relative clamp behaves exactly like an absolute one, so asking for
	# absolute here reproduces the effect without the mechanism.
	absolute_yaw_constraint = true

## ✅ MEASURED by the owner with a stopwatch in the original: about a second.
## Nothing in the CDO says so -- the roll is carried on an animation there.
##
## Was 0.6 while it was a guess, on the reasoning that it had to read as a
## manoeuvre rather than a stumble without feeling like a punishment for landing
## correctly. Nearly half again as long turns out to be right, which changes
## what the move IS: at 0.6 it is a flourish, at 1.0 it is a commitment.
@export var duration: float = 1.0

## ⚠️ PROJECT-DEFINED. How much of the banked speed budget survives the roll.
##
## Not all of it: the roll is a recovery, and a fall the player had to roll out
## of should still cost something. Not little, either, or nobody would use it.
@export var energy_keep: float = 0.75

## ⚠️ PROJECT-DEFINED. The speed the roll carries the body forward at, as a
## fraction of the horizontal speed it landed with.
##
## Above 1.0 on purpose: a roll converts a fall into forward travel, and coming
## out of one slightly faster than you went in is what makes it worth aiming
## for. The direction is fixed at touchdown and cannot be steered -- the CDO's
## ControllerState is PlayerGrabbing, the hands are busy, and the original
## gives the player no say in where a roll goes.
@export var speed_scale: float = 1.05

## ✅ MEASURED: a roll carries the body about 3 m forward, and it is FORCED --
## the owner's word. It happens whatever speed you arrived with, which is why
## the owner also reports that rolling toward a cliff edge in the original rolls
## you off it.
##
## A FLOOR, not a replacement for the carried speed. That reading is what makes
## both halves true at once: a fast landing still converts its momentum into
## forward travel through speed_scale above, and a straight drop -- which
## arrives with no horizontal speed at all, and which the old code left rolling
## on the spot -- still travels the measured 3 m.
##
## Consumed as a SPEED (distance over duration) rather than as a distance the
## move integrates toward, so it composes with speed_scale by a plain maxf()
## instead of needing its own arrival logic.
@export var forced_distance: float = 3.0

## How far the view rotates about the pitch axis over the roll. A full turn:
## the body goes over, and in first person the view goes with it.
##
## ⚠️ The AMOUNT is project-defined, but that a roll takes the view past
## vertical is not: TdMove_SkillRoll's own MaxLookConstraint is +180 degrees,
## where every other move in the library clamps well short of it. A sink-and-
## return, which is what this was at first, is indistinguishable from the hard
## landing the roll exists to avoid.
@export var camera_spin: float = TAU

## ⚠️ PROJECT-DEFINED. How low the eye drops at the midpoint of the roll, as a
## fraction of the crouch offset -- 1.0 is fully crouched.
@export var camera_crouch: float = 1.0

## Whether the forced travel follows the VIEW (the 2008 original) or the
## MOMENTUM (Catalyst).
##
## ✅ 2008 aims it with the camera, which the owner found by spinning 180 degrees
## in mid-air and rolling off in the direction they were looking rather than the
## one they were travelling. A deliberate break with physics, and the reasoning
## reads clearly: a roll is a second of lost control, and letting the view aim it
## hands that second back.
##
## ⚠️ CATALYST DIFFERS, and the owner flagged it: the sequel has four roll
## variants -- forward, back, left, right -- and its rolls DO follow momentum.
## So this is a CHOICE between two shipped games rather than a fact about one.
##
## Set to the 2008 behaviour because that is this project's target and every
## measurement behind the move came from it. Recorded as a switch rather than
## hard-coded so changing that decision is a line rather than an excavation.
@export var aim_with_view: bool = true

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
	# A roll spends the fall it landed. See MoveConfig.fall_counts_from_exit.
	fall_counts_from_exit = true
	# ✅ MinLookConstraint / MaxLookConstraint, at 65536 units = 360 degrees:
	# pitch -11.0 .. +180, yaw +-27.5, roll unconstrained. The lopsided pitch
	# is the roll itself -- the view is allowed to sweep all the way up and
	# over, but barely below level.
	constrain_look = true
	min_look_constraint = Vector3(-deg_to_rad(11.0), -deg_to_rad(27.5), -PI)
	max_look_constraint = Vector3(PI, deg_to_rad(27.5), PI)
	third_person_frees_look = true
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

## ⚠️ NO CONSUMER. Left recorded rather than deleted, and honestly labelled.
##
## This was the fraction of the landing speed the roll carried forward, on a
## reading of the measured 3 m as a minimum. The owner tested the original
## directly -- a standstill roll and an 80 km/h roll both travel 3 m -- so
## distance does not scale with arrival speed at all, and nothing reads this.
##
## What speed actually buys is energy_keep below: the share of the budget that
## survives, so a fast approach gets back up to pace sooner. Same intent, a
## different channel, and the original's channel.
@export var speed_scale: float = 1.05

## ✅ MEASURED, AND FIXED. The owner tested a roll from a standstill and one at
## 80 km/h in the original: both travel 3 m. Speed does not buy distance -- what
## it buys is the share of the energy budget that survives, see energy_keep.
##
## BACK TO 3.0 after a detour worth recording. This was briefly a FLOOR that
## momentum could exceed, which was my reading rather than a measurement, and it
## is what the owner then measured here as an over-long 3.2 m roll. They asked
## for 2.5 to compensate; with the invented momentum term gone the number can go
## back to the one the original actually uses. If 3 m still reads as far in this
## project's own camera and speeds, 2.5 is one line -- but it should be a choice
## made against faithful behaviour, not against a bug.
##
## ✅ A roll carries the body 3 m forward, and it is
## FORCED --
## the owner's word. It happens whatever speed you arrived with, which is why
## the owner also reports that rolling toward a cliff edge in the original rolls
## you off it.
##
## Consumed as a SPEED (distance over duration) rather than as a distance the
## move integrates toward: the roll has a fixed length in TIME as well, so the
## two together are simply a constant velocity.
@export var forced_distance: float = 3.0

## THE FULL-TURN PART of the roll's rotation about the pitch axis. The body goes
## over, and in first person the view goes with it.
##
## NOT the whole rotation: SkillRollMove adds the pitch the view started at, so
## the roll always finishes LEVEL. ✅ The owner, from the original -- the pitch
## is not forced to zero on entry, so looking up travels more than a full turn
## and looking down travels less. Both end at zero.
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

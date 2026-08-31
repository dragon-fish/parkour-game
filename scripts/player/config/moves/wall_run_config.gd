class_name WallRunConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_WallRun.

@export_group("Entry")
## Minimum horizontal speed required to attach to a wall, AND to stay
## attached once there (see WallRunMove's exit check) -- wall running is a
## way to CARRY speed, never a way to create it from nothing.
## Source: 04 §4.1 `WallRunningMinSpeed = 200` uu/s. ✅
@export var wall_running_min_speed: float = 2.0
## ✅ `WallRunningVelocityStartLimit = 300` uu/s. ❓ NO CONSUMER, again.
##
## Briefly had one: it was read as a ceiling on the vertical speed carried into
## an attach, which fixed a peak that came out too high. The owner then reported
## it still being too high, with a detail that settled the matter -- in the
## original the WAIST ends level with the plank's top, while here the FEET could
## clear it at speed -- and their HUD gave the real rule: the peak is measured
## from the GROUND, not from the contact point. See
## wall_running_horisontal_initial_z_height.
##
## That target subsumes this clamp entirely: the vertical speed at the attach is
## now assigned outright, so there is nothing left for a ceiling on it to do.
## Recorded here rather than deleted, and honestly labelled unused, because a
## value measured out of the original is worth keeping even when the behaviour
## it seemed to explain turned out to belong to another field.
@export var wall_running_velocity_start_limit: float = 3.0
## Minimum wall height to run along. Recorded; nothing reads this yet --
## Probes.wall_query() has no wall-height measurement of its own (its side
## rays only ever report whether SOMETHING is there, not how tall it is).
## Source: 04 §4.1 `WallRunningMinWallHeight = 192` uu (1.92 m). ✅
@export var wall_running_min_wall_height: float = 1.92
## Incidence angle (see Probes.wall_query()'s own "incidence" doc comment)
## AT OR BELOW which an approach qualifies for the FORWARD entry branch.
## Source: 04 §4.1 `WallRunningForwardMaxStartAngle = 57`°. ✅
@export var wall_running_forward_max_start_angle: float = deg_to_rad(57.0)
## Incidence angle AT OR ABOVE which an approach qualifies for the STRAFE
## entry branch. The 3-degree gap between this and the forward threshold
## above is a deliberate hysteresis band (04 §4.1): an approach landing
## inside it qualifies for NEITHER branch, which is what stops a borderline
## angle from flickering in and out of a wall run tick to tick.
## Source: 04 §4.1 `WallRunningStrafeStartAngle = 60`°. ✅
@export var wall_running_strafe_start_angle: float = deg_to_rad(60.0)
## How far sideways a wall may be and still be grabbed by
## Probes.wall_query()'s side rays -- REPLACES this project's own former
## `wall_reach` (0.75). This project has no separate forward-facing probe to
## give wall_running_strafe_check_distance below a distinct role, so the one
## side-ray reach this project has reads from the FORWARD field.
## Source: 04 §4.1 `WallRunningForwardCheckDistance = 50` uu. ✅
@export var wall_running_forward_check_distance: float = 0.5
## Recorded from the original as a value. ✅ ❓ No consumer wired -- see
## wall_running_forward_check_distance's own note on why this project's
## single side-ray probe reads that field instead of this one.
## Source: 04 §4.1 `WallRunningStrafeCheckDistance = 50` uu.
@export var wall_running_strafe_check_distance: float = 0.5

@export_group("Maintain")
## Friction while attached -- only 5%, which is most of why speed barely
## decays on its own. Recorded as a value; this project expresses the actual
## per-tick decay through wall_running_horisontal_deceleration below rather
## than through Player.ground_accelerate()'s friction path (WallRunMove
## drives velocity directly and is never grounded). Mirrored into
## MoveConfig's own friction_modifier in _init() below for architectural
## consistency with every other move, even though nothing consumes it here
## yet -- same status as min_look_constraint until CameraRig.apply_look()
## catches up.
## Source: 04 §4.1 `WallRunningHorisontalFriction = 0.05`. ✅
@export var wall_running_horisontal_friction: float = 0.05
## Acceleration pushing the player's speed along the wall's tangent UP
## TOWARD the energy-curve ceiling (Player.speed_cap()) -- see
## WallRunMove.physics_update()'s own maintenance step. Replaces this
## project's former wall_accel, which pushed toward a wall-specific
## wall_max_speed instead.
## Source: 04 §4.1 `WallRunningHorisontalAcceleration = 820` uu/s². ✅
@export var wall_running_horisontal_acceleration: float = 8.2
## Deceleration subtracted from TOTAL horizontal speed every tick this move
## is active, unconditionally -- THIS is the force that actually ends a wall
## run now that there is no duration cap: a faster entry simply takes longer
## to decay past wall_running_min_speed. Replaces this project's former
## wall_max_speed clamp, which capped speed instead of ever pulling it down.
## Source: 04 §4.1 `WallRunningHorisontalDeceleration = 500` uu/s². ✅
@export var wall_running_horisontal_deceleration: float = 5.0
## HOW HIGH A RUN PEAKS ABOVE THE GROUND IT TOOK OFF FROM.
##
## ✅ The value, from 04 §4.1 `WallRunningHorisontalInitialZHeight = 170` uu.
## ✅ The frame of reference, from the owner's own HUD in the original: standing
## at Z 43.17, and at the top of the run ZT 44.82 with SZD 1.56. A wall run
## peaks about 1.65 m above the roof it left, and does not care where on the
## wall contact happened.
##
## THAT FRAME IS THE WHOLE CORRECTION. Read as an increment added to the contact
## point -- which is what "initial Z height" sounds like, and what this project
## did -- the peak comes out that contact height too high. And contact height
## rises with approach speed, which is why the owner saw it as "at speed you can
## end up with your FEET above the plank top, where the original has your waist
## level with it".
##
## Applied at the point of use (WallRunMove.enter()) as the vertical speed that
## reaches whatever is LEFT of this height, converted against the wall's own
## rising gravity rather than plain gravity -- see there for why.
@export var wall_running_horisontal_initial_z_height: float = 1.7
## Recorded from the original as a value. ✅ ❓ No consumer wired -- this
## project has no separate "align velocity to the wall surface" pass distinct
## from WallRunMove._derive_along()'s own tangent projection.
## Source: 04 §4.1 `WallRunningHorisontalAlignSpeed = 700`.
@export var wall_running_horisontal_align_speed: float = 7.0
## ⚠️ INFERRED as a vertical SINK speed, not a horizontal one: the value is
## negative and the field name says velocity, and a horizontal speed (as
## wall_running_min_speed measures it) can never be negative. A wall run
## exits once vertical velocity falls past this.
## Source: 04 §4.1 `WallRunningVelocityStopLimit = -500` uu/s.
@export var wall_running_velocity_stop_limit: float = -5.0
## Recorded from the original as a value. ✅ ❓ No consumer wired -- this
## project has no body-rotation tween to drive.
## Source: 04 §4.1 `WallRunningRotatePawnAlongWallTime = 0.4` s.
@export var rotate_pawn_along_wall_time: float = 0.4
## Recorded from the original as a value. ✅ ❓ No consumer wired, same
## caveat as rotate_pawn_along_wall_time above.
## Source: 04 §4.1 `TimeToDo90Turn = 0.25` s.
@export var time_to_do_90_turn: float = 0.25

## ✅ MEASURED (04 §4.1). Vertical gravity is cut while attached, and the cut
## is ASYMMETRIC: the rise is braked harder than the fall accelerates, which is
## what produces the original's "stick to the wall and float" feel -- quick to
## the top, slow coming down.
##
## Fitted to two complete wall-run arcs (rms 0.011-0.022 m):
##
##   rising   ~790 uu/s^2  = 49% of world gravity
##   falling  ~505 uu/s^2  = 32%
##
## The falling figure closes a loop with wall_running_velocity_stop_limit:
## accelerating from rest at ~505 uu/s^2 reaches -500 uu/s in almost exactly
## 1.0 s, which is the wall run's measured duration. Duration is therefore an
## emergent consequence of these two numbers, not a separate timer -- do not
## add one.
##
## This replaced a single project-specific scale of 0.35 documented as having
## "no original counterpart". It has one; it just could not be seen without
## frame-level capture.
@export var wall_gravity_scale_rising: float = 0.49
@export var wall_gravity_scale_falling: float = 0.32

@export_group("Project-specific")
## ⚠️ MODEL DIFFERS FROM SOURCE, same reasoning as wall_gravity_scale above:
## a gentle pull toward the wall surface, in m/s per tick, so the body stays
## glued through small surface irregularities instead of drifting off. No
## original counterpart.
@export var wall_stick_force: float = 0.5

func _init() -> void:
	# Source: 04 §4.1 `RedoMoveTime = 0.15`. ✅ Far shorter than the 0.5 s
	# same-wall cooldown this project invented, because the original does not
	# need a cooldown to stop an endless climb -- a wall run does not lift you
	# at all, it only slows your descent, and every wall jump's own rise is
	# bounded by JumpOffZHeight.
	redo_move_time = 0.15
	friction_modifier = 0.05
	# Source: 04 §4.1 `MinLookConstraint = (-13000, -16384, -32768)` /
	# `MaxLookConstraint` mirrored, at 65536 = 360 degrees -> pitch +-71.4,
	# yaw +-90. ✅ With bUseAbsoluteYawConstraint = True. This is where "the
	# view swings to face along the wall" comes from -- an input constraint,
	# not an animation.
	#
	# THE YAW FAN IS ONE-SIDED, THOUGH, and the CDO's symmetric +-90 is not what
	# reaches the player. The owner: "running the left wall, you can only look
	# to the right-front." Which is the reading that makes sense of the
	# original having a WallRunLeft and a WallRunRight at all -- two moves whose
	# only difference is a mirrored fan, collapsed here into one move plus
	# `mirror_yaw_by_wall_side` below.
	#
	# So the 90 degrees is the full span, running from straight-ahead to a
	# quarter turn AWAY. Declared here for a wall on the LEFT; MoveManager
	# mirrors it for a wall on the right.
	#
	# MIND THE SIGN. Yaw increases COUNTER-CLOCKWISE seen from above, which is
	# leftward, so a wall on the left -- which the view must turn away from, to
	# the right -- gets the NEGATIVE half. Getting this backwards clamps the
	# view into the wall instead of away from it, which is precisely what it
	# did on its first outing.
	constrain_look = true
	absolute_yaw_constraint = true
	mirror_yaw_by_wall_side = true
	min_look_constraint = Vector3(-deg_to_rad(71.4), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(71.4), 0.0, PI)
	# Q DOES NOT START A TURN HERE. It moves the VIEW, not the body -- see
	# WallRunMove's own handling. The owner: "Q during a wall run only changes
	# the view; it does not pin the character in place", and "turning 90 degrees
	# right by hand and pressing space should feel the same as Q and space",
	# which is only true if Q is a shortcut for the mouse movement rather than a
	# move of its own.
	allows_turn = false

@export_group("Same-wall lockout")

## How long after leaving a wall its geometry keeps refusing certain moves.
##
## ⚠️ PROJECT-DEFINED, from the owner's own estimate of the original ("within a
## second of leaving the wall"). Replaces nothing: `redo_move_time` above is the
## confirmed 0.15 s and stays, as the short guard against a run flickering off
## and back on the same tick. This is the longer, GEOMETRIC rule on top.
@export var same_wall_lockout: float = 1.0

## How different two walls' facings must be before the second counts as a
## genuinely new wall rather than more of the one just left.
##
## ⚠️ PROJECT-DEFINED. See Player.recent_wall_refuses_run() for the physics this
## expresses and why only the same SIDE is constrained.
@export var same_wall_angle: float = deg_to_rad(20.0)

@export_group("Curved walls")

## How fast the look fan's centre follows the wall's own line, exponentially.
##
## The fan is measured against the wall, so on a curve it has to turn with it or
## it ends up policing a direction the wall stopped pointing in metres ago.
##
## ⚠️ PROJECT-DEFINED, and eased rather than tracked exactly for a reason a flat
## test wall would never show: a blockout curve is a row of straight segments,
## so the normal arrives in steps of several degrees at each seam. Followed
## rigidly, every seam is a visible tick in the view.
@export var fan_track_speed: float = 6.0

## How much of the wall's turn the VIEW is carried through, 0 to 1. See
## CameraRig.shift_yaw_reference().
##
## ⚠️ PROJECT-DEFINED. The owner asked for an ASSIST rather than a lock -- the
## run guiding the eyes, not steering them -- so this is deliberately short of
## 1. The clamp itself always travels the full turn; only the view is partial.
@export var view_assist: float = 0.6

## ⚠️ PROJECT-DEFINED, by eye. How much of the model head's own offset the
## first-person eye follows DURING a wall run. 1.0 restores the global follow;
## 0 pins the eye to the procedural position.
##
## ⚠️ THE "0.7 m OFF THE AXIS" THIS ONCE CITED IS NOT WHAT IT SCALES. That
## figure is the clip offset in scenes/player/tuning/*.json, and
## Player._camera_head_offset() subtracts it before the rig ever sees it -- so
## halving this never touched it. Holding the model off the wall is
## eye_off_wall's job now.
##
## What it really scales is the head bone's OWN motion, and raising it is why
## looking down stopped showing the neck: the camera pitches about its own
## centre rather than about the neck joint, so at a steep pitch it sits well
## above where the eyes belong -- and a fuller follow of a head bone that
## itself swings forward and down happens to approximate the arc the camera
## should be travelling. ✅ the owner tuned 0.75 by eye.
##
## 📌 That makes this number a COMPENSATION for a wrong pivot, not a fact about
## wall running. If the eye is ever hung off the neck joint properly, every
## value calibrated against the old pivot -- this one first -- has to be
## revisited rather than carried over.
@export_range(0.0, 1.0) var head_follow_scale: float = 0.75

## How far the FIRST-PERSON eye slides AWAY FROM the wall during a run, metres.
##
## THE MODEL IS DELIBERATELY OFF THE AXIS HERE. The wall-run clip offset in
## scenes/player/tuning/*.json holds the body out from the wall so the feet do
## not go through it, and Player._camera_head_offset() subtracts that back out
## so the view is not swung by it. Both halves are right. What the pair leaves
## is an eye on the capsule while the body is most of a metre to the side, so
## looking down shows it somewhere it visibly is not.
##
## Same answer CameraConfig.eye_forward already gives for the same shape of
## problem, quoted there: keep the model where it meets the world and push the
## EYE by the matching amount. This is that, sideways, and it moves nothing but
## the eye -- the feet stay out of the wall.
##
## NOT CLAMPED to the clip offset. Tuned by eye it went past it -- 0.7 against
## beriul's 0.6 -- and that is allowed: what the number has to satisfy is the
## view, not an equality with the model's own displacement.
##
## DO NOT REACH FOR head_follow_scale INSTEAD. That scales the head bone's own
## animated motion, centimetres of it, and the offset in question never reaches
## the rig at all.
## AWAY, because that is where the model is. The clip offset pushes the body
## OUT from the wall (WallRun_R is -0.6, and wall_side is +1 for a wall on the
## right), so an eye moved toward the wall goes straight into it -- which is
## exactly what happened when this was first written with the sign the name
## suggested rather than the sign the offset has.
@export var eye_off_wall: float = 0.7

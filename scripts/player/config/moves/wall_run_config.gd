class_name WallRunConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_WallRun.

@export_group("Entry")
## Minimum horizontal speed required to attach to a wall, AND to stay
## attached once there (see WallRunMove's exit check) -- wall running is a
## way to CARRY speed, never a way to create it from nothing.
## Source: 04 §4.1 `WallRunningMinSpeed = 200` uu/s. ✅
@export var wall_running_min_speed: float = 2.0
## Recorded from the original as a value. ✅ ❓ No consumer wired: nothing in
## the research ties this to behaviour distinct from wall_running_min_speed's
## own gate above, and the field name ("start limit") reads as a duplicate of
## it rather than a separate question.
## Source: 04 §4.1 `WallRunningVelocityStartLimit = 300` uu/s.
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
## ⚠️ INFERRED as a one-off vertical lift applied on attaching, expressed at
## the point of use (WallRunMove.enter()) as the vertical speed that reaches
## this height under plain gravity -- matching how this project reads every
## other `*ZHeight` field (see spec §2.5).
## Source: 04 §4.1 `WallRunningHorisontalInitialZHeight = 170` uu (1.7 m).
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
	# quarter turn AWAY. Declared here for a wall on the LEFT (look rightward,
	# positive yaw); MoveManager mirrors it for a wall on the right.
	constrain_look = true
	absolute_yaw_constraint = true
	mirror_yaw_by_wall_side = true
	min_look_constraint = Vector3(-deg_to_rad(71.4), 0.0, -PI)
	max_look_constraint = Vector3(deg_to_rad(71.4), deg_to_rad(90.0), PI)
	# Q DOES NOT START A TURN HERE. It moves the VIEW, not the body -- see
	# WallRunMove's own handling. The owner: "Q during a wall run only changes
	# the view; it does not pin the character in place", and "turning 90 degrees
	# right by hand and pressing space should feel the same as Q and space",
	# which is only true if Q is a shortcut for the mouse movement rather than a
	# move of its own.
	allows_turn = false

class_name Turn180Config
extends MoveConfig

# The original's TdMove_180Turn: pressing Q part-way up a wall kick to spin
# round and face back the way you came, with a brief window in which the body
# hangs there and can be kicked off the wall.
#
# The owner described this before any of the data was read: "there is a very
# short compensation window, during which you are not subject to gravity; press
# space in it and you kick off the wall, otherwise your speed drops to zero and
# you fall." Every clause of that has a field.

func _init() -> void:
	# LEGS BUSY: no spare limbs to spin on. See MoveConfig.allows_turn.
	allows_turn = false  # already turning. Q again mid-turn is nothing.
	# ✅ RedoMoveTime = 0.5.
	redo_move_time = 0.5
	# ✅ FrictionModifier = 0.3.
	friction_modifier = 0.3
	# ✅ bConstrainLook = True, with
	# MinLookConstraint = (-10000, -16384, 0) and its positive mirror.
	# -16384 of 65536 is a quarter turn; 10000 is 55 degrees.
	constrain_look = true
	absolute_yaw_constraint = true
	min_look_constraint = Vector3(-deg_to_rad(55.0), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(55.0), deg_to_rad(90.0), PI)

## ✅ `DisableMovementTime = 0.3`. THE OWNER'S "compensation window".
##
## The field is common across the original's move library (TdMove_Slide sets it
## to -1.0, i.e. disabled) and this project had not implemented the mechanism at
## all. It is implemented here only for this move rather than hoisted onto
## MoveConfig: one consumer is not a mechanism, and the moves that would use it
## are not written yet.
##
## For the window's duration the body holds still -- no gravity, no input --
## which is what makes the turn feel like a decision point rather than a
## flourish performed on the way down.
##
## THIS IS THE FREEZE, NOT THE OPPORTUNITY. They were one number to begin with,
## and the owner reported the result: "the grace period is too short -- Q has to
## be followed by space immediately or you slide off." Enlarging this would have
## been the easy fix and the wrong one, since 0.3 is confirmed. What was wrong
## was reading a field named DisableMovementTime as the whole move's length: it
## says how long INPUT IS DISABLED, and says nothing about when the chance to
## kick expires. See kick_window.
@export var disable_movement_time: float = 0.3

## How long space still kicks off the wall, counted from the start of the turn.
##
## ⚠️ PROJECT-DEFINED. Past disable_movement_time the body is falling again, so
## the tail of this window is a genuine grace period: you are already dropping,
## and a late press still catches. Long enough that Q and space are two
## deliberate presses rather than a chord.
@export var kick_window: float = 0.75

## Gravity during the tail, after the freeze and before the window closes.
##
## ⚠️ PROJECT-DEFINED, and deliberately gentle: this is still a body braced
## against a wall, not one in free fall. Full gravity here would drop the player
## far enough in the remaining window that the extra time bought nothing.
@export var falling_gravity_scale: float = 0.35

## How long the body takes to come round.
##
## ✅ MEASURED by the owner in the original: a 180 out of a wall climb takes
## about half a second. Not in the CDO -- the turn is carried on an animation
## there, so a stopwatch was the only way to get it.
##
## A DURATION, not a rate, so every turn takes the same time whatever angle it
## covers. That is what an animation does, and it is why this is longer than the
## freeze above rather than shorter: the body is still coming round when gravity
## returns, which is the half-second the manoeuvre is worth.
##
## The turn is SCRIPTED, so the camera trails it and eases in rather than being
## cut through it (docs/camera-authority.md).
@export var turn_time: float = 0.5

@export_group("Wall kick")

## ✅ `TdMove_WallKick`: `WallKickVelocity2D = 300` uu/s away from the wall and
## `WallKickVelocityZ = 580` uu/s upward.
##
## Folded into this move's exit rather than given its own state. From outside it
## is one impulse and then an ordinary jump, and a state that exists only to
## apply an impulse on the tick it is entered is a state whose entire content is
## a function call. The original's own `RedoMoveTime = 1.0` on the kick is the
## one thing lost by folding, and it has no consumer yet -- this move's own 0.5
## already prevents the obvious abuse, which is spinning repeatedly on one wall.
@export var wall_kick_speed_out: float = 3.0
@export var wall_kick_speed_up: float = 5.8

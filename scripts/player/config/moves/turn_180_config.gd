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
@export var disable_movement_time: float = 0.3

## How long the body takes to come round. ⚠️ PROJECT-DEFINED: the original
## carries the turn on an animation, and there is no duration in the CDO.
##
## The turn is SCRIPTED, so the camera trails it and eases in rather than being
## cut through it (docs/camera-authority.md). Set shorter than the window above,
## so the turn is visibly finished while there is still time to decide.
@export var turn_time: float = 0.2

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

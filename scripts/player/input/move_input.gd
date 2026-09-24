class_name MoveInput
extends RefCounted

# One physics tick worth of input. Pure data — no logic, no engine access.

## x = strafe (+ is right), y = forward (+ is forward). NORMALISED: a
## diagonal is (0.707, 0.707), never (1, 1), so that running diagonally is
## not faster than running straight.
var move := Vector2.ZERO
## How far the strafe AXIS ITSELF is pushed, BEFORE the normalisation above,
## in -1..1. Not derivable from `move.x`: normalising throws away the
## difference between a key (which is always full-scale) and a stick held
## halfway, and those are the two cases DodgeJumpConfig.strafe_threshold has
## to tell apart.
##
## [ME:CONFIRMED 04 §4.5] the original fires a dodge from W+A, whose strafe
## axis reads 1.0 on a keyboard where a stick would read 0.707. Every OTHER consumer of
## `move` asks it for a DIRECTION and must keep reading the normalised
## vector; this field answers "how hard is the axis pushed", which is a
## different question and the reason it is a field rather than a rescale.
var strafe_axis := 0.0
## Mouse motion accumulated since the previous poll, in pixels.
var look := Vector2.ZERO
## True only on the tick the jump key transitioned from up to down.
var jump_pressed := false
var jump_held := false
## True while the walk modifier is held: the keyboard's stand-in for a stick
## pushed gently, read through Player.stick_amount(). There is no sprint key.
var walk_held := false
var crouch_held := false
## True only on the tick the crouch key transitioned from up to down.
var crouch_pressed := false
## True only on the tick the turn key transitioned from up to down. Q in the
## keyboard binding. Consumed by Turn180Move's entry, and by nothing else.
var turn_pressed := false

func copy() -> MoveInput:
	var out := MoveInput.new()
	out.move = move
	out.strafe_axis = strafe_axis
	out.look = look
	out.jump_pressed = jump_pressed
	out.jump_held = jump_held
	out.walk_held = walk_held
	out.crouch_held = crouch_held
	out.crouch_pressed = crouch_pressed
	out.turn_pressed = turn_pressed
	return out

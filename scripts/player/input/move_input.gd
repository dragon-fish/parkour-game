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
## halfway. The original's dodge gate is the hint's bMoveActionMax, which is
## taken from the raw axes (Player.set_input_hint()).
##
## [ME:CONFIRMED 04 §4.5] the original fires a dodge from W+A, whose strafe
## axis reads 1.0 on a keyboard where a stick would read 0.707. Every OTHER consumer of
## `move` asks it for a DIRECTION and must keep reading the normalised
## vector; this field answers "how hard is the axis pushed", which is a
## different question and the reason it is a field rather than a rescale.
var strafe_axis := 0.0
## The two axes as the keys or the stick hold them, BEFORE the normalisation
## above: x strafe, y forward. The original reads these raw -- its input hint
## and InputSize come before any normalising (TdPlayerInput.PlayerInput).
var raw_move := Vector2.ZERO
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
## True only on the tick the attack key went down: TdPlayerController.AttackPress.
var melee_pressed := false

func copy() -> MoveInput:
	var out := MoveInput.new()
	out.move = move
	out.strafe_axis = strafe_axis
	out.raw_move = raw_move
	out.look = look
	out.jump_pressed = jump_pressed
	out.jump_held = jump_held
	out.walk_held = walk_held
	out.crouch_held = crouch_held
	out.crouch_pressed = crouch_pressed
	out.turn_pressed = turn_pressed
	out.melee_pressed = melee_pressed
	return out

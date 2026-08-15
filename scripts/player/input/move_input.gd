class_name MoveInput
extends RefCounted

# One physics tick worth of input. Pure data — no logic, no engine access.

## x = strafe (+ is right), y = forward (+ is forward).
var move := Vector2.ZERO
## Mouse motion accumulated since the previous poll, in pixels.
var look := Vector2.ZERO
## True only on the tick the jump key transitioned from up to down.
var jump_pressed := false
var jump_held := false
var sprint_held := false
var crouch_held := false
## True only on the tick the crouch key transitioned from up to down.
var crouch_pressed := false

func copy() -> MoveInput:
	var out := MoveInput.new()
	out.move = move
	out.look = look
	out.jump_pressed = jump_pressed
	out.jump_held = jump_held
	out.sprint_held = sprint_held
	out.crouch_held = crouch_held
	out.crouch_pressed = crouch_pressed
	return out

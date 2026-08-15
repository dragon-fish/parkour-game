class_name KeyboardInputSource
extends InputSource

# Reads physical key positions so the bindings do not shift with keyboard
# layout. No InputMap actions are registered: rebinding is out of scope for
# the prototype.

var _jump_was_held := false
var _look_accumulator := Vector2.ZERO

## Called from the player's _input() with the raw mouse relative motion.
func accumulate_look(delta: Vector2) -> void:
	_look_accumulator += delta

func poll() -> MoveInput:
	var out := MoveInput.new()

	var forward := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		forward += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		forward -= 1.0

	var strafe := 0.0
	if Input.is_physical_key_pressed(KEY_D):
		strafe += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		strafe -= 1.0

	out.move = Vector2(strafe, forward)
	if out.move.length_squared() > 1.0:
		out.move = out.move.normalized()

	out.look = _look_accumulator
	_look_accumulator = Vector2.ZERO

	var jump_held := Input.is_physical_key_pressed(KEY_SPACE)
	out.jump_pressed = jump_held and not _jump_was_held
	out.jump_held = jump_held
	_jump_was_held = jump_held

	out.sprint_held = Input.is_physical_key_pressed(KEY_SHIFT)
	out.crouch_held = Input.is_physical_key_pressed(KEY_CTRL)
	return out

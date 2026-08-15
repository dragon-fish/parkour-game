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
	# While the mouse is released (F1 panel open, or right after Esc) the
	# physical keys are being used to interact with UI — typing a preset
	# name, clicking a slider — not to move the character. Stop polling them
	# so e.g. the 'a' in a typed preset name cannot strafe the player.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_look_accumulator = Vector2.ZERO
		# Resync to the physical key state rather than leaving it stale, so a
		# jump held across the capture/release boundary does not read as a
		# fresh press the moment the mouse is recaptured.
		_jump_was_held = Input.is_physical_key_pressed(KEY_SPACE)
		return MoveInput.new()

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

class_name KeyboardInputSource
extends InputSource

# Reads the keyboard and mouse through InputBindings.current(), so what each
# action listens to is the player's choice. Keys are read by PHYSICAL position,
# so a layout change never moves a binding. No InputMap actions are
# registered.
#
# Anything that names a key on screen must ask InputNames, which reads the
# same table -- a rebind changes the game and every prompt at once.
#
# The left mouse button's default, attack, matches the original. While the
# cursor is free that button clicks back into the game instead (Player), and
# this source reads nothing at all then.
#
# TWO READS PER INPUT: the live state, polled once a tick, and the press
# EVENTS since the previous poll, latched by accumulate_press(). [ME:CONFIRMED
# TdPlayerInput.uc] the original acts on the event -- IE_Pressed runs the exec
# (Jump sets bPressedJump, LookBehind turns) whenever it arrives -- so a press
# is never lost. Polling alone loses a tap that goes down and up between two
# ticks; the latch keeps it.

## The actions whose press is an EDGE, tracked across polls.
const _EDGE_ACTIONS: Array[String] = [
	InputBindings.JUMP, InputBindings.CROUCH, InputBindings.TURN, InputBindings.MELEE,
]

## One action's reading for one poll.
class Reading:
	var held := false
	var pressed := false

## action -> whether its keys and buttons were down at the previous poll.
var _was_held: Dictionary = {}
## Inputs that went down since the previous poll, by _latch_key().
var _latched: Dictionary = {}
var _look_accumulator := Vector2.ZERO

## Called from the player's _input() with the raw mouse relative motion.
func accumulate_look(delta: Vector2) -> void:
	_look_accumulator += delta

## Called by the player with every key event (_input) and every mouse button
## event (_unhandled_input). Keeps the presses for the next poll; releases and
## key repeats are not presses and the live state answers for them.
##
## A WHEEL NOTCH IS ONLY EVER THIS. [ME:INFERRED] UE3's viewport delivers
## MouseScrollUp/Down as IE_Pressed then IE_Released in the same frame
## (native, not read here). [ME:CONFIRMED TdPlayerInput.uc,
## TdPlayerController.uc] GBA_Jump is "Jump | OnRelease StopJump"; Jump sets
## bPressedJump, StopJump sets bReleasedJump, and PlayerWalking.PlayerMove
## runs CheckJumpPressed then CheckJumpReleased and clears both, every tick.
## Ported as: the notch reads as a press on the next poll and as held for
## exactly that poll, released on the one after -- so a notch every tick is a
## press every tick, and several notches inside one tick are one press, as
## they are there. The one difference: MA_StopJump lands a tick later here
## than there, and no move reads it. A key tapped inside one tick reads the
## same way.
##
## A press while the mouse is NOT captured is never the game's -- the click
## that captures it above all, which arrives before the capture does. It is
## not latched, and is marked as already held, so the first poll after the
## capture does not read that same click, still down, as a fresh press.
func accumulate_press(event: InputEvent) -> void:
	if not _is_fresh_press(event):
		return
	var binding := InputBindings.from_event(event)
	if binding.is_empty():
		return
	if not _is_captured():
		var bindings := InputBindings.current()
		for action in _EDGE_ACTIONS:
			for slot in bindings.get(action, []):
				if InputBindings.same(slot, binding):
					_was_held[action] = true
		return
	_latched[_latch_key(binding)] = true

func poll() -> MoveInput:
	var bindings := InputBindings.current()
	# While the mouse is released (F1 panel open, or right after Esc) the
	# physical keys are being used to interact with UI -- typing a preset
	# name, clicking a slider -- not to move the character. Stop polling them
	# so e.g. the 'a' in a typed preset name cannot strafe the player.
	if not _is_captured():
		_look_accumulator = Vector2.ZERO
		_latched.clear()
		# Resync to the physical state rather than leaving it stale, so a
		# jump or crouch held across the capture/release boundary does not
		# read as a fresh press the moment the mouse is recaptured.
		for action in _EDGE_ACTIONS:
			_was_held[action] = _down(bindings, action)
		return MoveInput.new()

	var out := MoveInput.new()

	var forward := 0.0
	if _active(bindings, InputBindings.MOVE_FORWARD):
		forward += 1.0
	if _active(bindings, InputBindings.MOVE_BACK):
		forward -= 1.0

	var strafe := 0.0
	if _active(bindings, InputBindings.MOVE_RIGHT):
		strafe += 1.0
	if _active(bindings, InputBindings.MOVE_LEFT):
		strafe -= 1.0

	out.move = Vector2(strafe, forward)
	if out.move.length_squared() > 1.0:
		out.move = out.move.normalized()
	# BEFORE the normalisation, deliberately: a key is a full-scale axis and
	# holding W as well does not make A any less pressed. See
	# MoveInput.strafe_axis.
	out.strafe_axis = strafe
	out.raw_move = Vector2(strafe, forward)

	out.look = _look_accumulator
	_look_accumulator = Vector2.ZERO

	var jump := _read(bindings, InputBindings.JUMP)
	out.jump_pressed = jump.pressed
	out.jump_held = jump.held

	out.walk_held = _active(bindings, InputBindings.WALK)

	var crouch := _read(bindings, InputBindings.CROUCH)
	out.crouch_held = crouch.held
	out.crouch_pressed = crouch.pressed

	out.turn_pressed = _read(bindings, InputBindings.TURN).pressed
	out.melee_pressed = _read(bindings, InputBindings.MELEE).pressed

	_latched.clear()
	return out

## An edge action: pressed on going down between polls or on a press event
## since the last one; held while down, or for the one poll a latched press
## lasts. Only the live state feeds the edge memory, so a latched tap never
## hides the next real press.
func _read(bindings: Dictionary, action: String) -> Reading:
	var reading := Reading.new()
	var down := _down(bindings, action)
	var latched := _latched_any(bindings, action)
	reading.pressed = (down and not bool(_was_held.get(action, false))) or latched
	reading.held = down or latched
	_was_held[action] = down
	return reading

## A level action (an axis, the walk modifier): down now, or pressed since the
## last poll.
func _active(bindings: Dictionary, action: String) -> bool:
	return _down(bindings, action) or _latched_any(bindings, action)

## Whether any key or button bound to `action` is down right now. The wheel is
## never down: it only ever arrives as a latched press.
func _down(bindings: Dictionary, action: String) -> bool:
	for binding in bindings.get(action, []):
		if not InputBindings.is_valid(binding) or InputBindings.is_wheel(binding):
			continue
		if binding.kind == InputBindings.KIND_KEY:
			if _key_down(int(binding.code)):
				return true
		elif _button_down(int(binding.button)):
			return true
	return false

func _latched_any(bindings: Dictionary, action: String) -> bool:
	for binding in bindings.get(action, []):
		if InputBindings.is_valid(binding) and _latched.has(_latch_key(binding)):
			return true
	return false

static func _latch_key(binding: Dictionary) -> String:
	if binding.kind == InputBindings.KIND_KEY:
		return "key:%d" % int(binding.code)
	return "mouse:%d" % int(binding.button)

static func _is_fresh_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	return event is InputEventMouseButton and (event as InputEventMouseButton).pressed

# The engine reads, one place each, so a test can stand in for the hardware:
# a headless run can neither hold a key nor capture the mouse.

func _is_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _key_down(code: int) -> bool:
	return Input.is_physical_key_pressed(code)

func _button_down(button: int) -> bool:
	return Input.is_mouse_button_pressed(button)

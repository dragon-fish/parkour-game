class_name ScriptedInputSource
extends InputSource

# Test double. Tests write into `state` directly; poll() reproduces the
# keyboard source's edge semantics so that jump_pressed lasts exactly one
# tick no matter which source the player is fed.

var state := MoveInput.new()

func press_jump() -> void:
	state.jump_pressed = true
	state.jump_held = true

func release_jump() -> void:
	state.jump_pressed = false
	state.jump_held = false

func press_crouch() -> void:
	state.crouch_pressed = true
	state.crouch_held = true

func release_crouch() -> void:
	state.crouch_pressed = false
	state.crouch_held = false

func press_turn() -> void:
	state.turn_pressed = true

func poll() -> MoveInput:
	var snapshot := state.copy()
	state.jump_pressed = false
	state.crouch_pressed = false
	# No held counterpart, unlike jump and crouch: Q is a one-shot. There is
	# nothing a held Q could mean -- the turn either started or it did not.
	state.turn_pressed = false
	return snapshot

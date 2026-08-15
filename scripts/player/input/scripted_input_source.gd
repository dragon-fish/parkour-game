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

func poll() -> MoveInput:
	var snapshot := state.copy()
	state.jump_pressed = false
	return snapshot

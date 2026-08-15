class_name StateMachine
extends Node

signal state_changed(from: StringName, to: StringName)

var current_name: StringName = &""

var _current: PlayerState = null
var _states: Dictionary = {}

func register(state_name: StringName, state: PlayerState) -> void:
	_states[state_name] = state

func start(state_name: StringName) -> void:
	assert(_states.has(state_name), "unknown state: %s" % state_name)
	_current = _states[state_name]
	current_name = state_name
	_current.enter(&"")
	state_changed.emit(&"", state_name)

func physics_update(delta: float, input: MoveInput) -> void:
	if _current == null:
		return
	var next: StringName = _current.physics_update(delta, input)
	if next == PlayerState.KEEP or next == current_name:
		return
	assert(_states.has(next), "transition to unknown state: %s" % next)
	var from := current_name
	_current.exit()
	_current = _states[next]
	current_name = next
	_current.enter(from)
	state_changed.emit(from, next)

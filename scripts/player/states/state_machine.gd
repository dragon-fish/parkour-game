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
	if not _states.has(state_name):
		push_error("StateMachine.start: unknown state: %s" % state_name)
		return
	# A live machine can already be mid-state when start() is called again
	# (e.g. Arena.reset_player() restarting into Ground while the machine is
	# still in Air). Exit the outgoing state first so states with exit side
	# effects (P1's SlideState restoring the standing collision shape) do not
	# get skipped and leave the player stuck in a partial state.
	if _current != null:
		_current.exit()
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
	if not _states.has(next):
		push_error("StateMachine.physics_update: transition to unknown state: %s" % next)
		return
	var from := current_name
	_current.exit()
	_current = _states[next]
	current_name = next
	_current.enter(from)
	state_changed.emit(from, next)

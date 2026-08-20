extends ParkourTest

# A local stub state so the state machine can be tested without a player.
# NOTE: the recorder is named `events`, not `log` — `log` is GDScript's
# built-in natural logarithm and shadowing it causes confusing errors.
class StubState:
	extends PlayerState
	var events: Array[String] = []
	var next_state: StringName = PlayerState.KEEP

	func enter(previous: StringName) -> void:
		events.append("enter:%s" % previous)

	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		events.append("update")
		var n := next_state
		next_state = PlayerState.KEEP
		return n

	func exit() -> void:
		events.append("exit")


func _build() -> Array:
	var sm := StateMachine.new()
	var a := StubState.new()
	var b := StubState.new()
	sm.add_child(a)
	sm.add_child(b)
	sm.register(&"A", a)
	sm.register(&"B", b)
	return [sm, a, b]


func test_start_enters_the_initial_state() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	sm.start(&"A")
	assert_true(sm.current_name == &"A", "current_name not set by start()")
	assert_true(a.events == ["enter:"], "initial enter() not called exactly once")
	sm.free()

func test_transition_calls_exit_then_enter_in_order() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	var b: StubState = parts[2]
	sm.start(&"A")
	a.events.clear()
	a.next_state = &"B"
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	assert_true(a.events == ["update", "exit"], "outgoing state did not update then exit")
	assert_true(b.events == ["enter:A"], "incoming state did not receive the previous name")
	assert_true(sm.current_name == &"B", "current_name not updated")
	sm.free()

func test_keep_does_not_retrigger_enter() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	sm.start(&"A")
	a.events.clear()
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	assert_true(a.events == ["update", "update"], "KEEP must not cause exit/enter")
	sm.free()

func test_state_changed_signal_reports_both_names() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	var seen: Array[String] = []
	sm.state_changed.connect(func(from: StringName, to: StringName) -> void:
		seen.append("%s->%s" % [from, to]))
	sm.start(&"A")
	a.next_state = &"B"
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	assert_true(seen == ["->A", "A->B"], "state_changed payload wrong: %s" % str(seen))
	sm.free()

func test_returning_own_name_is_a_noop() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	sm.start(&"A")
	a.events.clear()
	a.next_state = &"A"
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	assert_true(a.events == ["update"], "returning the current state name must not trigger exit()/enter()")
	assert_true(sm.current_name == &"A", "current_name must stay unchanged when a state returns its own name")
	sm.free()

# The reviewer flagged that assert() is stripped in release exports, so an
# unregistered transition target must also degrade safely without it: push
# an error but leave the machine on its current state instead of advancing
# current_name to a name with no matching state (which would otherwise null
# out _current and freeze physics_update() permanently, silently, forever).
func test_restarting_a_running_machine_exits_the_outgoing_state() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	var b: StubState = parts[2]
	sm.start(&"A")
	a.events.clear()
	sm.start(&"B")
	assert_true(a.events == ["exit"], "start() on a live machine did not exit the outgoing state")
	assert_true(b.events == ["enter:"], "start() must still enter the new state with an empty previous name")
	assert_true(sm.current_name == &"B", "current_name not updated by a restart")
	sm.free()

func test_unknown_transition_leaves_the_machine_running() -> void:
	await step(1)
	var parts := _build()
	var sm: StateMachine = parts[0]
	var a: StubState = parts[1]
	sm.start(&"A")
	a.events.clear()
	a.next_state = &"Nonexistent"
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	assert_true(sm.current_name == &"A", "an unknown transition target must not change current_name")
	a.events.clear()
	sm.physics_update(1.0 / 60.0, MoveInput.new())
	assert_true(a.events == ["update"], "state machine must keep responding after an unknown transition")
	sm.free()

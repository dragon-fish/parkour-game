class_name StateMachine
extends Node

signal state_changed(from: StringName, to: StringName)

var current_name: StringName = &""

var _current: PlayerState = null
var _states: Dictionary = {}

# --- grounded-declaration invariant ------------------------------------------
#
# Player.grounded is DECLARED by the active state, never inferred (scripted-move
# states drive the body directly and never call move_and_slide(), so
# is_on_floor() would report whatever the previous state left behind). P0's
# refactor made that a rule; nothing enforced it. A state that simply never
# calls set_grounded() silently inherits the OUTGOING state's value — and the
# dangerous direction is inheriting `true` from Ground, because Player's
# _tick_timers() then refills coyote time every tick, which is infinite jumps.
# P3's WallRun is exactly the shape of state that would forget.
#
# Enforced here rather than left to a review checklist, and enforced this way
# rather than by defaulting `grounded` to false before delegating, because
# GroundState legitimately READS its own previously-declared value: its Slide
# and Vault entry gates are `if player.grounded`, meaning "a move_and_slide()
# has verified this, on this tick or an earlier one". Defaulting the flag every
# tick would pin that gate shut forever; defaulting it only on entry would
# still discard AirState's landing declaration on the very tick it was made,
# deferring every landing-into-slide by a tick and quietly changing feel. An
# invariant check changes no behaviour at all: correct states are untouched,
# and an incorrect one is reported the first time it runs, in any test or in
# play. tools/run_tests.ps1 fails the run on any engine error line, so a state
# that forgets cannot reach a green suite.
#
# The rule checked is "the ACTIVE state has declared at least once since it was
# entered", evaluated only on ticks where the state stays active:
#   * enter() counts — VaultState and LedgeHangState declare there and never
#     again, which is correct for them (their value cannot change mid-move);
#   * a state that transitions AWAY on a given tick is exempt for that tick,
#     because the incoming state's enter()/first update is what owns the flag
#     from then on. GroundState's Vault branch returns without declaring and is
#     legitimately covered by VaultState.enter().
var _entry_declarations: int = -1
var _reported_missing_declaration: bool = false

func register(state_name: StringName, state: PlayerState) -> void:
	_states[state_name] = state

## The registered instance for a state name, or null. Exposed for tests that
## need to observe a state's own internals — SlideState.is_crawling(), which
## nothing outside the state can otherwise distinguish from ordinary sliding.
## Normal operation never hands a state out.
func state_for(state_name: StringName) -> PlayerState:
	return _states.get(state_name)

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
	# Snapshot BEFORE enter(), so a declaration made in enter() counts.
	_arm_declaration_check()
	_current.enter(&"")
	_clear_stale_grounded_after_start()
	state_changed.emit(&"", state_name)

func physics_update(delta: float, input: MoveInput) -> void:
	if _current == null:
		return
	var next: StringName = _current.physics_update(delta, input)
	if next == PlayerState.KEEP or next == current_name:
		_check_declared_grounded()
		return
	assert(_states.has(next), "transition to unknown state: %s" % next)
	if not _states.has(next):
		push_error("StateMachine.physics_update: transition to unknown state: %s" % next)
		# The machine stays on the current state, so it is still the one whose
		# declaration matters this tick.
		_check_declared_grounded()
		return
	var from := current_name
	_current.exit()
	_current = _states[next]
	current_name = next
	_arm_declaration_check()
	_current.enter(from)
	state_changed.emit(from, next)

## Fail-safe half only, no reporting: start() can be the FIRST tick of a
## state's life, so its own first physics_update() has not run yet -- a state
## whose enter() legitimately defers declaring (GroundState is exactly this
## shape) has not yet violated the invariant, and _check_declared_grounded()'s
## "did not declare" report would be a false positive here.
##
## But Player._physics_process() calls _tick_timers() BEFORE
## state_machine.physics_update() every frame, and _tick_timers() reads
## `grounded` to refill coyote time. Without this, a restart whose new state
## does not declare in enter() would leave whatever `grounded` held a moment
## earlier -- the OUTGOING state's value, or older still -- readable by
## _tick_timers() for one whole tick before the new state's first
## physics_update() ever gets a chance to correct it. Real play was covered
## only by a coincidence of caller order (Arena.reset_player() clears
## `grounded` via reset_state() before calling start()); this closes the gap
## in start() itself so the guarantee no longer depends on that order.
##
## Mirrors the fail-safe half of _check_declared_grounded() exactly -- a state
## that DID declare in enter() (VaultState, LedgeHangState) is untouched,
## since the count comparison below then differs.
func _clear_stale_grounded_after_start() -> void:
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return
	_current.player.clear_grounded_undeclared()

## Player's declaration counter, or -1 when there is no player to read it from
## (tests/test_state_machine.gd drives this class with bare stub states that
## have none). -1 disables the invariant for that machine entirely.
func _declaration_count() -> int:
	if _current == null or _current.player == null:
		return -1
	return _current.player.grounded_declarations

func _arm_declaration_check() -> void:
	_entry_declarations = _declaration_count()
	_reported_missing_declaration = false

## See the invariant note at the top of this file.
func _check_declared_grounded() -> void:
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return

	# Fail-safe first, and every tick it keeps not declaring: whatever the
	# previous state left in `grounded` must not be believed. false is the safe
	# value — it withholds coyote time rather than granting it.
	_current.player.clear_grounded_undeclared()

	# Reported once per entry, not once per tick: a state that never declares
	# never will, and 60 identical lines a second buries the one that matters.
	if _reported_missing_declaration:
		return
	_reported_missing_declaration = true
	var message := "state %s did not declare grounded-ness: every state must call player.set_grounded() in enter() or in its physics_update()" % current_name
	assert(false, message)
	push_error("StateMachine: " + message)

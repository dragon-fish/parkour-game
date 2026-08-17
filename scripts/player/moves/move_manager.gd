class_name MoveManager
extends Node

signal move_changed(from: StringName, to: StringName)

var current_name: StringName = &""

var _current: Move = null
var _moves: Dictionary = {}

## Seconds of cooldown still owed per move name. An entry only exists while a
## move is actually cooling down.
var _redo_cooldowns: Dictionary = {}

func register(move_name: StringName, move: Move) -> void:
	_moves[move_name] = move

## The registered instance for a move name, or null. Read every physics tick
## by CharacterAnimator (to reach GrabMove.is_mantling()), and by tests that
## need to observe a move's own internals — SlideMove.is_crawling(), which
## nothing outside the move can otherwise distinguish from ordinary sliding.
func move_for(move_name: StringName) -> Move:
	return _moves.get(move_name)

## False while `move_name`'s own redo_move_time is still running. The original
## declares this per move (TdMove.RedoMoveTime) rather than scattering it
## across the callers, which is what lets Player stop carrying three separate
## hand-rolled cooldowns of its own (the ledge regrab timer, the recent-wall
## list, and the wall reattach window).
func can_enter(move_name: StringName) -> bool:
	return not _redo_cooldowns.has(move_name)

## The active move's own friction multiplier, or 1.0 when there is no move or
## no config. Read by Player.ground_accelerate() so braking respects whatever
## move is in force without Player having to know which one that is.
func current_move_friction_modifier() -> float:
	if _current == null:
		return 1.0
	var active: MoveConfig = _current.current_config()
	return active.friction_modifier if active != null else 1.0

func _tick_cooldowns(delta: float) -> void:
	for key in _redo_cooldowns.keys():
		var remaining: float = _redo_cooldowns[key] - delta
		if remaining <= 0.0:
			_redo_cooldowns.erase(key)
		else:
			_redo_cooldowns[key] = remaining

func _arm_cooldown(move_name: StringName, move: Move) -> void:
	var seconds: float = move.cfg.redo_move_time if move.cfg != null else 0.0
	if seconds > 0.0:
		_redo_cooldowns[move_name] = seconds

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

func start(move_name: StringName) -> void:
	assert(_moves.has(move_name), "unknown state: %s" % move_name)
	if not _moves.has(move_name):
		push_error("MoveManager.start: unknown state: %s" % move_name)
		return
	# A live manager can already be mid-move when start() is called again
	# (e.g. Arena.reset_player() restarting into Walking while the manager is
	# still in Falling). Exit the outgoing move first so moves with exit side
	# effects (SlideMove restoring the standing collision shape) do not get
	# skipped and leave the player stuck in a partial move.
	#
	# Deliberately NOT paired with _arm_cooldown(), unlike the exit() call in
	# physics_update() below: a restart is not the move choosing to leave, it
	# is being interrupted from outside, so it must not be penalised with a
	# cooldown on top of that. Whatever the interrupted move was, its next
	# life should be free to re-enter it immediately.
	if _current != null:
		_current.exit()
	# Same reasoning Player.reset_state() already states for its own
	# hand-rolled cooldowns (the ledge regrab timer, the recent-wall list):
	# a cooldown left over from the previous life must not withhold the new
	# life's first attempt at a move. Without this, a WallRun or Grab
	# cooldown still ticking down at the moment of death or reset would
	# silently refuse the very first entry into that move on the fresh life.
	_redo_cooldowns.clear()
	_current = _moves[move_name]
	current_name = move_name
	# Snapshot BEFORE enter(), so a declaration made in enter() counts.
	_arm_declaration_check()
	_current.enter(&"")
	_clear_stale_grounded_after_start()
	move_changed.emit(&"", move_name)
	_push_look_constraint()

func physics_update(delta: float, input: MoveInput) -> void:
	if _current == null:
		return
	_tick_cooldowns(delta)
	var next: StringName = _current.physics_update(delta, input)
	if next == Move.KEEP or next == current_name:
		_check_declared_grounded()
		_push_look_constraint()
		return
	# A move that asks for a target still cooling down simply stays put. Done
	# here rather than in each caller so no move can forget, and so the
	# refusal never silently drops the tick's own transition INTENT into some
	# third state.
	if not can_enter(next):
		_check_declared_grounded()
		_push_look_constraint()
		return
	assert(_moves.has(next), "transition to unknown state: %s" % next)
	if not _moves.has(next):
		push_error("MoveManager.physics_update: transition to unknown state: %s" % next)
		# The manager stays on the current move, so it is still the one whose
		# declaration matters this tick.
		_check_declared_grounded()
		_push_look_constraint()
		return
	var from := current_name
	_current.exit()
	_arm_cooldown(from, _current)
	_current = _moves[next]
	current_name = next
	_arm_declaration_check()
	_current.enter(from)
	move_changed.emit(from, next)
	_push_look_constraint()

## Fail-safe half only, no reporting: start() can be the FIRST tick of a
## move's life, so its own first physics_update() has not run yet -- a move
## whose enter() legitimately defers declaring (WalkingMove is exactly this
## shape) has not yet violated the invariant, and _check_declared_grounded()'s
## "did not declare" report would be a false positive here.
##
## But Player._physics_process() calls _tick_timers() BEFORE
## move_manager.physics_update() every frame, and _tick_timers() reads
## `grounded` to refill coyote time. Without this, a restart whose new move
## does not declare in enter() would leave whatever `grounded` held a moment
## earlier -- the OUTGOING move's value, or older still -- readable by
## _tick_timers() for one whole tick before the new move's first
## physics_update() ever gets a chance to correct it. Real play was covered
## only by a coincidence of caller order (Arena.reset_player() clears
## `grounded` via reset_state() before calling start()); this closes the gap
## in start() itself so the guarantee no longer depends on that order.
##
## Mirrors the fail-safe half of _check_declared_grounded() exactly -- a move
## that DID declare in enter() (SpeedVaultMove, GrabMove) is untouched,
## since the count comparison below then differs.
func _clear_stale_grounded_after_start() -> void:
	if _entry_declarations < 0:
		return
	if _declaration_count() > _entry_declarations:
		return
	_current.player.clear_grounded_undeclared()

## Player's declaration counter, or -1 when there is no player to read it from
## (tests/test_move_manager.gd drives this manager with bare stub moves that
## have none). -1 disables the invariant for that manager entirely.
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
	# previous move left in `grounded` must not be believed. false is the safe
	# value — it withholds coyote time rather than granting it.
	_current.player.clear_grounded_undeclared()

	# Reported once per entry, not once per tick: a move that never declares
	# never will, and 60 identical lines a second buries the one that matters.
	if _reported_missing_declaration:
		return
	_reported_missing_declaration = true
	var message := "state %s did not declare grounded-ness: every state must call player.set_grounded() in enter() or in its physics_update()" % current_name
	assert(false, message)
	push_error("MoveManager: " + message)

## Pushes the ACTIVE move's look clamp to the camera every tick. The original
## makes this per-move data (MinLookConstraint / MaxLookConstraint /
## bConstrainLook, see 06 §6.2 and 04 §4.1), and it is an INPUT constraint,
## not an animation effect -- "the view swings to face along the wall" is this
## and nothing else. Pushed every tick rather than only on transition because
## FallingMove's own constraint changes mid-move (see Move.current_config()).
func _push_look_constraint() -> void:
	if _current == null or _current.player == null:
		return
	var rig = _current.player.camera_rig
	if rig == null:
		return
	var active: MoveConfig = _current.current_config()
	if active == null or not active.constrain_look:
		rig.clear_look_constraint()
		return
	rig.set_look_constraint(active.min_look_constraint, active.max_look_constraint, \
		active.absolute_yaw_constraint)

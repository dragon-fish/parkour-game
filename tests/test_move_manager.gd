extends ParkourTest

# Drives MoveManager with bare stub moves -- no player, no physics -- so the
# manager's own contract is tested in isolation from any real movement: the
# original's SetMove order and re-entrancy, the action table's "current move
# first, then candidates in order", and, for the moves not yet ported, the
# physics_update() hand-off and its per-move cooldown.

class StubMove extends Move:
	var next: StringName = Move.KEEP
	var entered: int = 0
	func enter(_previous: StringName) -> void:
		entered += 1
	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		return next

## One tick of a move that is not ported: the timers, then its own update.
func _tick(manager: MoveManager) -> void:
	manager.tick_timers(0.016)
	manager.perform_physics(0.016, MoveInput.new())

func _manager(names: Array) -> MoveManager:
	var manager := MoveManager.new()
	get_tree().root.add_child(manager)
	for n in names:
		var move := StubMove.new()
		move.cfg = MoveConfig.new()
		manager.add_child(move)
		manager.register(n, move)
	return manager

func test_a_transition_enters_the_target_move() -> void:
	var manager := _manager([Move.WALKING, Move.FALLING])
	manager.start(Move.WALKING)
	(manager.move_for(Move.WALKING) as StubMove).next = Move.FALLING
	_tick(manager)
	assert_true(manager.current_name == Move.FALLING, "did not transition")
	assert_true((manager.move_for(Move.FALLING) as StubMove).entered == 1, "target enter() not called")
	manager.queue_free()
	await step(1)

func test_redo_move_time_blocks_re_entering_the_same_move() -> void:
	# [ME:CONFIRMED] The original gives each move its own cooldown
	# (TdMove.RedoMoveTime, e.g. WallRun 0.15, WallKick 1.0). Centralising it
	# here is what lets Player stop carrying three separate hand-rolled
	# cooldowns of its own (the ledge regrab timer, the recent-wall list, and
	# the wall reattach window).
	var manager := _manager([Move.WALKING, Move.WALL_RUN])
	manager.move_for(Move.WALL_RUN).cfg.redo_move_time = 0.5
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var wall := manager.move_for(Move.WALL_RUN) as StubMove

	walking.next = Move.WALL_RUN
	_tick(manager)
	assert_true(manager.current_name == Move.WALL_RUN, "first entry was blocked")

	wall.next = Move.WALKING
	_tick(manager)
	assert_true(manager.current_name == Move.WALKING, "did not leave the wall")

	# Still cooling down: the request is refused and the manager simply stays.
	_tick(manager)
	assert_true(manager.current_name == Move.WALKING, "redo_move_time did not block re-entry")

	# Park the wall move before running the clock out, or the two stubs bounce
	# off each other for the rest of the loop and the final state says nothing.
	wall.next = Move.KEEP
	for i in 40:
		_tick(manager)
	assert_true(manager.current_name == Move.WALL_RUN, "cooldown never expired")
	manager.queue_free()
	await step(1)

func test_start_clears_a_live_cooldown() -> void:
	# Mirrors Player.reset_state() clearing its own per-life timers (coyote,
	# jump buffer, roll buffer) on a fresh life: a redo_move_time still
	# counting down at the moment start() restarts the manager -- e.g.
	# Arena.reset_player() after a death or an R-key reset -- must not carry
	# over and silently refuse the new life's first attempt at that move.
	var manager := _manager([Move.WALKING, Move.WALL_RUN])
	manager.move_for(Move.WALL_RUN).cfg.redo_move_time = 0.5
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var wall := manager.move_for(Move.WALL_RUN) as StubMove

	walking.next = Move.WALL_RUN
	_tick(manager)
	wall.next = Move.WALKING
	_tick(manager)
	assert_true(not manager.can_enter(Move.WALL_RUN), "cooldown was not armed for the fixture")

	# A reset restarts the manager mid-cooldown -- start() must clear it.
	manager.start(Move.WALKING)
	assert_true(manager.can_enter(Move.WALL_RUN), "start() did not clear a live cooldown")
	manager.queue_free()
	await step(1)

func test_a_move_with_no_cooldown_can_be_re_entered_immediately() -> void:
	var manager := _manager([Move.WALKING, Move.SLIDE])
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var slide := manager.move_for(Move.SLIDE) as StubMove
	walking.next = Move.SLIDE
	slide.next = Move.WALKING
	for i in 4:
		_tick(manager)
	assert_true((manager.move_for(Move.SLIDE) as StubMove).entered == 2, "a zero cooldown blocked re-entry")
	manager.queue_free()
	await step(1)

func test_current_config_defaults_to_the_moves_own_cfg() -> void:
	var move := StubMove.new()
	var cfg := MoveConfig.new()
	move.cfg = cfg
	assert_true(move.current_config() == cfg, "current_config() did not fall through to cfg")
	# Never added to the tree, so queue_free() has nothing to defer to -- a
	# bare Node (unlike RefCounted) does not free itself when it goes out of
	# scope, and leaving this out trips Godot's own "objects still in use at
	# exit" leak report even though every assert_true() above already passed.
	move.free()

func test_current_move_friction_modifier_reads_the_active_moves_cfg() -> void:
	var manager := _manager([Move.WALKING])
	manager.start(Move.WALKING)
	(manager.move_for(Move.WALKING) as StubMove).cfg.friction_modifier = 0.1
	assert_almost_eq(manager.current_move_friction_modifier(), 0.1, 0.0001, \
		"did not read the active move's own friction_modifier")
	manager.queue_free()
	await step(1)

func test_current_move_friction_modifier_defaults_to_one_with_no_current_move() -> void:
	var manager := MoveManager.new()
	get_tree().root.add_child(manager)
	assert_almost_eq(manager.current_move_friction_modifier(), 1.0, 0.0001, \
		"did not default to 1.0 with no current move at all")
	manager.queue_free()
	await step(1)

func test_current_move_friction_modifier_defaults_to_one_with_no_cfg() -> void:
	var manager := MoveManager.new()
	get_tree().root.add_child(manager)
	var move := StubMove.new()
	move.cfg = null
	manager.add_child(move)
	manager.register(Move.WALKING, move)
	manager.start(Move.WALKING)
	assert_almost_eq(manager.current_move_friction_modifier(), 1.0, 0.0001, \
		"did not default to 1.0 when the active move has no cfg")
	manager.queue_free()
	await step(1)

# --- the original's SetMove -------------------------------------------------------

## Records every lifecycle call on a shared log, and can set another move from
## inside its own enter() -- the way Landing sets Walking.
class LogMove extends Move:
	var log: Array
	var chain_to: StringName = Move.KEEP
	var allowed: bool = true
	func can_do_move() -> bool:
		return allowed
	func enter(previous: StringName) -> void:
		log.append("enter %s from %s" % [move_name, previous])
		if chain_to != Move.KEEP:
			player_manager.set_move(chain_to)
	func exit() -> void:
		log.append("exit %s" % move_name)
	func post_exit() -> void:
		log.append("post_exit %s" % move_name)
	var player_manager: MoveManager

func _log_manager(names: Array, log: Array) -> MoveManager:
	var manager := MoveManager.new()
	get_tree().root.add_child(manager)
	for n in names:
		var move := LogMove.new()
		move.cfg = MoveConfig.new()
		move.log = log
		move.player_manager = manager
		manager.add_child(move)
		manager.register(n, move)
	return manager

## [ME:CONFIRMED decompile N4 §1.2] Old move's StopMove, then PostStopMove once
## the state has moved on, then the new move's StartMove.
func test_set_move_stops_then_posts_then_starts() -> void:
	var log: Array = []
	var manager := _log_manager([Move.FALLING, Move.LANDING], log)
	manager.start(Move.FALLING)
	log.clear()
	assert_true(manager.set_move(Move.LANDING), "set_move refused a plain change")
	assert_eq(log, ["exit Falling", "post_exit Falling", "enter Landing from Falling"])
	manager.queue_free()
	await step(1)

func test_set_move_refuses_the_current_move_and_a_locked_manager() -> void:
	var log: Array = []
	var manager := _log_manager([Move.WALKING, Move.FALLING], log)
	manager.start(Move.WALKING)
	assert_false(manager.set_move(Move.WALKING), "set the move it was already in")
	manager.allow_move_change = false
	assert_false(manager.set_move(Move.FALLING), "changed move while move changes were off")
	assert_eq(manager.current_name, Move.WALKING)
	manager.queue_free()
	await step(1)

func test_set_move_with_check_honours_can_do_move() -> void:
	var log: Array = []
	var manager := _log_manager([Move.WALKING, Move.FALLING], log)
	manager.start(Move.WALKING)
	(manager.move_for(Move.FALLING) as LogMove).allowed = false
	assert_false(manager.set_move(Move.FALLING, true), "bCheckCanDo let a refused move in")
	assert_eq(manager.current_name, Move.WALKING)
	assert_true(manager.set_move(Move.FALLING), "without the check the move is set regardless")
	manager.queue_free()
	await step(1)

## [ME:CONFIRMED decompile 15.4] A StartMove may set another move: Landing
## sets Walking on the spot. The chain is reported once every enter() has run,
## in the order the switches happened.
func test_a_start_move_may_set_the_next_move_and_both_changes_are_reported_in_order() -> void:
	var log: Array = []
	var manager := _log_manager([Move.FALLING, Move.LANDING, Move.WALKING], log)
	manager.start(Move.FALLING)
	(manager.move_for(Move.LANDING) as LogMove).chain_to = Move.WALKING
	var changes: Array = []
	manager.move_changed.connect(func(from: StringName, to: StringName) -> void:
		changes.append([from, to, manager.current_name]))
	log.clear()
	manager.set_move(Move.LANDING)
	assert_eq(manager.current_name, Move.WALKING)
	assert_eq(log, ["exit Falling", "post_exit Falling", "enter Landing from Falling",
		"exit Landing", "post_exit Landing", "enter Walking from Landing"])
	assert_eq(changes, [[Move.FALLING, Move.LANDING, Move.WALKING],
		[Move.LANDING, Move.WALKING, Move.WALKING]])
	manager.queue_free()
	await step(1)

# --- the action table ---------------------------------------------------------------

## Changes the move from its own handle_move_action, the way a move that
## handles an action itself does.
class ActingMove extends LogMove:
	var takes_action_to: StringName = Move.KEEP
	func handle_move_action(_action: int) -> void:
		if takes_action_to != Move.KEEP:
			player_manager.set_move(takes_action_to)

func test_the_table_asks_its_candidates_in_order() -> void:
	var log: Array = []
	var manager := _log_manager([Move.WALKING, Move.SLIDE, Move.CROUCH], log)
	manager.start(Move.WALKING)
	(manager.move_for(Move.SLIDE) as LogMove).allowed = false
	assert_true(manager.handle_move_action(Move.MA_CROUCH), "no candidate taken")
	assert_eq(manager.current_name, Move.CROUCH, "Walking + crouch is Slide, then Crouch")
	manager.queue_free()
	await step(1)

func test_the_first_candidate_that_can_wins() -> void:
	var log: Array = []
	var manager := _log_manager([Move.WALKING, Move.SLIDE, Move.CROUCH], log)
	manager.start(Move.WALKING)
	manager.handle_move_action(Move.MA_CROUCH)
	assert_eq(manager.current_name, Move.SLIDE)
	manager.queue_free()
	await step(1)

## A candidate this project does not have is simply skipped, as a CanDoMove
## that says no.
func test_a_move_the_project_lacks_falls_through() -> void:
	var log: Array = []
	var manager := _log_manager([Move.FALLING, Move.TURN_180_IN_AIR], log)
	manager.start(Move.FALLING)
	assert_false(manager.handle_move_action(Move.MA_MELEE), "AirBarge / MeleeAir do not exist")
	assert_true(manager.handle_move_action(Move.MA_TURN), "Falling + turn is 180TurnInAir")
	assert_eq(manager.current_name, Move.TURN_180_IN_AIR)
	manager.queue_free()
	await step(1)

## [ME:CONFIRMED decompile 15.3] The current move sees the action first; if
## it changed the move, the table is not consulted.
func test_the_current_move_sees_the_action_first() -> void:
	var manager := MoveManager.new()
	get_tree().root.add_child(manager)
	var log: Array = []
	for n in [Move.WALKING, Move.SLIDE, Move.CROUCH]:
		var move := ActingMove.new() if n == Move.WALKING else LogMove.new()
		move.cfg = MoveConfig.new()
		move.log = log
		move.player_manager = manager
		manager.add_child(move)
		manager.register(n, move)
	manager.start(Move.WALKING)
	(manager.move_for(Move.WALKING) as ActingMove).takes_action_to = Move.CROUCH
	manager.handle_move_action(Move.MA_CROUCH)
	assert_eq(manager.current_name, Move.CROUCH, "the table overrode the move's own handling")
	manager.queue_free()
	await step(1)

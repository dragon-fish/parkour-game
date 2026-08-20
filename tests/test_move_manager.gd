extends ParkourTest

# Drives MoveManager with bare stub moves -- no player, no physics -- so the
# manager's own contract (registration, transitions, redo_move_time, the
# look-constraint hand-off) is tested in isolation from any real movement.

class StubMove extends Move:
	var next: StringName = Move.KEEP
	var entered: int = 0
	func enter(_previous: StringName) -> void:
		entered += 1
	func physics_update(_delta: float, _input: MoveInput) -> StringName:
		return next

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
	manager.physics_update(0.016, MoveInput.new())
	assert_true(manager.current_name == Move.FALLING, "did not transition")
	assert_true((manager.move_for(Move.FALLING) as StubMove).entered == 1, "target enter() not called")
	manager.queue_free()
	await step(1)

func test_redo_move_time_blocks_re_entering_the_same_move() -> void:
	# The original gives each move its own cooldown (TdMove.RedoMoveTime,
	# e.g. WallRun 0.15, WallKick 1.0). Centralising it here is what lets the
	# three ad-hoc cooldowns Player used to carry go away.
	var manager := _manager([Move.WALKING, Move.WALL_RUN])
	manager.move_for(Move.WALL_RUN).cfg.redo_move_time = 0.5
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var wall := manager.move_for(Move.WALL_RUN) as StubMove

	walking.next = Move.WALL_RUN
	manager.physics_update(0.016, MoveInput.new())
	assert_true(manager.current_name == Move.WALL_RUN, "first entry was blocked")

	wall.next = Move.WALKING
	manager.physics_update(0.016, MoveInput.new())
	assert_true(manager.current_name == Move.WALKING, "did not leave the wall")

	# Still cooling down: the request is refused and the manager simply stays.
	manager.physics_update(0.016, MoveInput.new())
	assert_true(manager.current_name == Move.WALKING, "redo_move_time did not block re-entry")

	# Park the wall move before running the clock out, or the two stubs bounce
	# off each other for the rest of the loop and the final state says nothing.
	wall.next = Move.KEEP
	for i in 40:
		manager.physics_update(0.016, MoveInput.new())
	assert_true(manager.current_name == Move.WALL_RUN, "cooldown never expired")
	manager.queue_free()
	await step(1)

func test_start_clears_a_live_cooldown() -> void:
	# Mirrors Player.reset_state() clearing its own hand-rolled cooldowns
	# (the ledge regrab timer, the recent-wall list) on a fresh life: a
	# redo_move_time still counting down at the moment start() restarts the
	# manager -- e.g. Arena.reset_player() after a death or an R-key reset --
	# must not carry over and silently refuse the new life's first attempt
	# at that move.
	var manager := _manager([Move.WALKING, Move.WALL_RUN])
	manager.move_for(Move.WALL_RUN).cfg.redo_move_time = 0.5
	manager.start(Move.WALKING)
	var walking := manager.move_for(Move.WALKING) as StubMove
	var wall := manager.move_for(Move.WALL_RUN) as StubMove

	walking.next = Move.WALL_RUN
	manager.physics_update(0.016, MoveInput.new())
	wall.next = Move.WALKING
	manager.physics_update(0.016, MoveInput.new())
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
		manager.physics_update(0.016, MoveInput.new())
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
	# scope, and leaving this out trips run_tests.ps1's own "resources still
	# in use at exit" scan even though every assert_true() above already passed.
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

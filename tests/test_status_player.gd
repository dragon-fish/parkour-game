extends ParkourTest

# The wiring between StatusList and the single read points each effect lands
# on. Values (0.5, 2 s) are NOT asserted -- they are tuning dials. What is
# asserted is that the reading changes at all, and that it changes in the one
# place every caller already goes through.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _cap_spec(scale: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = INF
	return s

func test_a_speed_cap_scales_what_every_move_asks_for() -> void:
	var p := _player()
	await step(1)
	var free_cap: float = p.speed_cap()
	p.statuses.apply(_cap_spec(0.5), p, 0)
	assert_almost_eq(p.speed_cap(), free_cap * 0.5, 0.0001, \
		"speed_cap() ignored the status")

func test_removing_the_cap_restores_the_ceiling_immediately() -> void:
	# The energy budget is deliberately NOT cleared while capped, so the
	# ceiling comes straight back rather than having to be re-earned.
	var p := _player()
	await step(1)
	var free_cap: float = p.speed_cap()
	p.statuses.apply(_cap_spec(0.5), p, 0)
	p.statuses.remove(Status.Effect.SPEED_CAP)
	assert_almost_eq(p.speed_cap(), free_cap, 0.0001, "the ceiling did not come back")

func test_the_player_ages_its_own_statuses() -> void:
	var p := _player()
	await step(1)
	var s := _cap_spec(0.5)
	s.seconds = 1.0 / 30.0
	p.statuses.apply(s, p, 0)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the status never landed")
	await step(4)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"nothing ticked the list down")

func _block_spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = INF
	return s

func test_a_blocked_jump_never_applies_its_launch_velocity() -> void:
	# THE POINT OF THIS TEST. walking_move.gd sets velocity.y BEFORE it returns
	# JUMP, so refusing the transition in MoveManager.can_enter() would leave
	# the body launched but still Walking. The block has to land on the buffer.
	var p := _player()
	await step(1)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_JUMP), p, 0)
	assert_false(p.consume_jump(), "a blocked jump was still spendable")
	assert_false(p.consume_buffered_jump(), "a blocked buffered jump was spendable")

func test_a_blocked_jump_does_not_eat_the_buffered_press() -> void:
	# Refusing must not spend the press: the player let go of nothing, and the
	# press has to still be there the moment the block lifts.
	var p := _player()
	await step(1)
	p.statuses.apply(_block_spec(Status.Effect.BLOCK_JUMP), p, 0)
	p.arm_jump_buffer_for_test()
	assert_false(p.consume_jump(), "the block did not hold")
	p.statuses.remove(Status.Effect.BLOCK_JUMP)
	assert_true(p.consume_jump(), "the block swallowed the press")

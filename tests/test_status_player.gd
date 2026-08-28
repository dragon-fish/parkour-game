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

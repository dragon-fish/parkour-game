extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that. Settled on the floor before
# returning, not just spawned there -- TestWorld.build() leaves the capsule
# interpenetrating the floor slab, and how far the solver's depenetration
# pushes it over the following frames varies with system load. A volume
# boxed around that still-moving body can end up left behind before a test
# means it to be; TestWorld.place() plus a settle removes the variable.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _cap(scale: float, seconds: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.SPEED_CAP
	s.amount = scale
	s.seconds = seconds
	return s

func _shaped_volume() -> ModifierVolume:
	var v := ModifierVolume.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 4.0)
	shape.shape = box
	v.add_child(shape)
	add_child_autofree(v)
	return v

func _volume(at: Vector3) -> ModifierVolume:
	var v := _shaped_volume()
	v.global_position = at
	return v

func test_walking_in_applies_and_walking_out_lets_it_lapse() -> void:
	var p := await _player()
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, 0.2)]
	v.refresh_interval = 0.1
	await step(20)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the volume never applied")
	p.global_position += Vector3(50.0, 0.0, 0.0)
	await step(30)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"the status outlived the volume it came from")

func test_an_infinite_status_survives_leaving_the_volume() -> void:
	var p := await _player()
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, INF)]
	await step(5)
	p.global_position += Vector3(50.0, 0.0, 0.0)
	await step(20)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), \
		"an INF status was cleared by leaving")

func test_a_volume_may_both_apply_and_remove() -> void:
	# One volume, several changes -- the author must not have to place a
	# second box just to lift something.
	var p := await _player()
	var lock := StatusSpec.new()
	lock.effect = Status.Effect.BLOCK_JUMP
	lock.seconds = INF
	p.statuses.apply(lock, p, 0)
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, INF)]
	v.remove = [lock]
	await step(5)
	assert_false(p.statuses.has(Status.Effect.BLOCK_JUMP), "the volume did not remove")
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), "the volume did not apply")

func test_a_capped_volume_stops_after_its_last_entry() -> void:
	var p := await _player()
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, INF)]
	v.max_trigger_count = 1
	await step(5)
	p.statuses.remove(Status.Effect.SPEED_CAP)
	p.global_position += Vector3(50.0, 0.0, 0.0)
	await step(5)
	p.global_position = v.global_position
	await step(10)
	assert_false(p.statuses.has(Status.Effect.SPEED_CAP), \
		"a volume capped at one entry fired on the second")

func test_refreshing_does_not_spend_the_entry_count() -> void:
	# The count is about ENTRIES. A polling volume refreshes many times per
	# visit, and counting those would use the whole budget on the first tick.
	var p := await _player()
	var v := _volume(p.global_position)
	v.apply = [_cap(0.5, 0.2)]
	v.refresh_interval = 0.05
	v.max_trigger_count = 1
	await step(40)
	assert_true(p.statuses.has(Status.Effect.SPEED_CAP), \
		"the refreshes ate the entry budget")

# _get_configuration_warnings() is all that stands between a level author and a
# volume that looks placed and never fires. Structural, not cosmetic: every
# case below is silent at run time.
#
# Counted, never matched: the strings are prose and will be reworded. Each test
# leaves the volume otherwise valid so the count names one condition.

func _warned(volume: ModifierVolume) -> int:
	return volume._get_configuration_warnings().size()

func test_a_correctly_configured_volume_warns_about_nothing() -> void:
	# The negative case, and the one that keeps the rest honest -- without it
	# they would all pass on a function that warns about everything.
	var v := _shaped_volume()
	v.apply = [_cap(0.5, INF)]
	assert_eq(_warned(v), 0, "a volume with nothing wrong with it was flagged")

func test_a_volume_with_no_shape_is_flagged() -> void:
	var v := ModifierVolume.new()
	add_child_autofree(v)
	v.apply = [_cap(0.5, INF)]
	assert_eq(_warned(v), 1, "a volume that can never be entered was not flagged")

func test_a_volume_that_neither_applies_nor_removes_is_flagged() -> void:
	var v := _shaped_volume()
	assert_eq(_warned(v), 1, "a volume that does nothing was not flagged")

func test_an_empty_row_in_apply_is_flagged() -> void:
	var v := _shaped_volume()
	var rows: Array[StatusSpec] = [null]
	v.apply = rows
	assert_eq(_warned(v), 1, "a null entry was not flagged")

func test_a_speed_cap_of_zero_is_flagged() -> void:
	# It pins the player in place, which reads as the level having hung.
	var v := _shaped_volume()
	v.apply = [_cap(0.0, INF)]
	assert_eq(_warned(v), 1, "a cap that stops the player dead was not flagged")

func test_a_line_block_with_no_subject_is_flagged() -> void:
	var v := _shaped_volume()
	var spec := StatusSpec.new()
	spec.effect = Status.Effect.BLOCK_INTEREST_LINE
	spec.seconds = INF
	v.apply = [spec]
	assert_eq(_warned(v), 1, "a line block naming no line was not flagged")

func test_a_refreshing_volume_holding_an_endless_status_is_flagged() -> void:
	# The pairing that never lapses: refreshing is how a status is meant to
	# expire on the way out, and INF is what stops it ever doing so.
	var v := _shaped_volume()
	v.apply = [_cap(0.5, INF)]
	v.refresh_interval = 0.1
	assert_eq(_warned(v), 1, "a status that can never lapse was not flagged")

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

func _block_jump(seconds: float) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.BLOCK_JUMP
	s.seconds = seconds
	return s

func test_a_no_jump_region_never_lifts_between_refreshes() -> void:
	# THE TIGHTEST PAIRING THERE IS: seconds exactly equal to refresh_interval,
	# so the status expires on the very tick it is renewed. Two things have to
	# hold for the block never to lift, and this is the only test that needs
	# both. The volume's cycle must not be longer than the life it renews -- a
	# refresh clock that discards its overshoot rounds every cycle up to a
	# whole frame and lapses one frame early, forever -- and the volume must
	# run before the Player ages the list.
	#
	# BLOCK_JUMP rather than SPEED_CAP because a one-frame hole in a cap is
	# invisible while a one-frame hole in a jump block is a jump.
	#
	# The signal is counted as well as has() read: a lift and a re-apply inside
	# one frame is invisible to a test that only looks between frames, and it
	# is still a frame the moves ran with no block in force.
	var p := await _player()
	var v := _volume(p.global_position)
	v.apply = [_block_jump(0.1)]
	v.refresh_interval = 0.1
	# Pinned directly, because no fixture can pin it by behaviour: which of the
	# two runs first without it is scene-tree order, and a test's own nodes
	# happen to sit ahead of the world fixture's either way.
	assert_lt(v.process_physics_priority, p.process_physics_priority, \
		"the volume no longer refreshes before the player ages the list")
	var lifts := [0]
	p.statuses.status_removed.connect(func(effect: int, _subject: StringName) -> void:
		if effect == Status.Effect.BLOCK_JUMP:
			lifts[0] += 1)
	await step(2)
	assert_true(p.statuses.has(Status.Effect.BLOCK_JUMP), "the volume never applied")
	# Well past several refresh cycles at 60 fixed fps: 0.1 s is six ticks.
	for i in 60:
		await step(1)
		assert_true(p.statuses.has(Status.Effect.BLOCK_JUMP), \
			"the block was gone at the end of tick %d" % i)
	assert_eq(lifts[0], 0, \
		"the block was lifted and re-applied inside a frame -- a jump fits through that")

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

func test_a_status_no_longer_than_the_refresh_interval_is_flagged() -> void:
	# The pairing above, caught in the editor instead of at run time.
	var v := _shaped_volume()
	v.apply = [_cap(0.5, 0.1)]
	v.refresh_interval = 0.1
	assert_eq(_warned(v), 1, "a status that expires on its own refresh tick was not flagged")

func test_a_refresh_interval_below_one_physics_tick_is_flagged() -> void:
	# Behaviourally harmless -- the accumulator goes negative and it refreshes
	# every tick, which is already the maximum cadence -- and that is exactly
	# why it needs flagging: it looks like it works, while the number the
	# author typed means nothing at all.
	var v := _shaped_volume()
	v.apply = [_cap(0.5, 1.0)]
	v.refresh_interval = 0.5 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	assert_eq(_warned(v), 1, "a sub-tick refresh interval was not flagged")

func test_a_status_lasting_twice_the_interval_is_not_flagged() -> void:
	# The documented pairing, and the negative that keeps the check honest.
	var v := _shaped_volume()
	v.apply = [_cap(0.5, 0.2)]
	v.refresh_interval = 0.1
	assert_eq(_warned(v), 0, "the recommended pairing was flagged")

## Records how it was told, rather than what it was told. Duck-typed the same
## way a Player is, and deliberately not one: what `fresh_contact` MEANS is
## the receiver's business, and this test is only about the volume saying it.
class ContactLog extends CharacterBody3D:
	var fresh: Array[bool] = []
	func apply_status(_spec: StatusSpec, _source: Object, _priority: int,
			fresh_contact: bool = false) -> void:
		fresh.append(fresh_contact)
	func remove_status(_effect: int, _subject: StringName) -> void:
		pass

func test_a_volume_says_whether_it_was_entered_or_is_renewing() -> void:
	# The receiver cannot work this out for itself: nothing tracks membership,
	# so a body that left and came back is indistinguishable from one that
	# never moved. The volume is the only thing that knows, and for a hazard
	# the difference is whether stepping back on costs anything.
	var volume := _volume(Vector3.ZERO)
	volume.apply = [_cap(0.5, 10.0)]
	volume.refresh_interval = 0.05
	var log := ContactLog.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	log.add_child(shape)
	add_child_autofree(log)
	log.global_position = Vector3.ZERO
	await step(12)
	assert_gt(log.fresh.size(), 1, "test setup: the volume never applied anything")
	assert_true(log.fresh[0], "walking in was reported as a renewal")
	assert_false(log.fresh[log.fresh.size() - 1], "a refresh was reported as walking in")

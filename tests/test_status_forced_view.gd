extends ParkourTest

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

func _force(view: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.FORCE_VIEW
	s.view = view
	s.seconds = INF
	return s

func test_a_forced_view_overrides_the_preference() -> void:
	var p := _player()
	await step(1)
	p.camera_rig.third_person = true
	p.statuses.apply(_force(Status.View.FIRST), p, 0)
	await step(1)
	assert_false(p.camera_rig.in_third_person(), "the force did not take")

func test_the_saved_preference_is_not_touched() -> void:
	# The whole reason forced_view is its own field: toggle_third_person()
	# saves to disk on every change, so sharing the field would rewrite the
	# player's preference the first time they walk indoors.
	var p := _player()
	await step(1)
	p.camera_rig.third_person = true
	p.statuses.apply(_force(Status.View.FIRST), p, 0)
	await step(1)
	assert_true(p.camera_rig.third_person, "the force overwrote the preference")
	p.statuses.remove(Status.Effect.FORCE_VIEW)
	await step(1)
	assert_true(p.camera_rig.in_third_person(), "the preference did not come back")

func test_the_view_key_does_nothing_while_forced() -> void:
	var p := _player()
	await step(1)
	p.camera_rig.third_person = false
	p.statuses.apply(_force(Status.View.FIRST), p, 0)
	await step(1)
	p.camera_rig.toggle_third_person()
	assert_false(p.camera_rig.third_person, "the key changed the preference under a force")

func test_the_view_eases_in_whichever_way_it_is_going() -> void:
	# THE BUG THIS PINS. Easing an absolute 0..1 blend is ease-in one way and
	# ease-out the other: pow(t, 5) climbing from 0 starts slow, but the same
	# expression on a t falling from 1 drops fastest immediately. Measured as a
	# fraction of the distance covered in the first quarter of the blend, which
	# a slow start keeps well under a quarter in BOTH directions.
	var p := _player()
	# Seeded first: an unseeded rig snaps to whatever view it first sees, and
	# a single tick is not enough to seed it.
	await step(6)
	assert_eq(p.camera_rig._eased_view_blend(), 0.0, "test setup: not seeded at the eye")
	var quarter: int = maxi(int(p.config.camera.view_blend_time * 60.0 / 4.0), 1)
	
	# first -> third
	p.camera_rig.third_person = true
	await step(quarter)
	var out_early: float = p.camera_rig._eased_view_blend()
	await step(120)
	assert_almost_eq(p.camera_rig._eased_view_blend(), 1.0, 0.001, "test setup: never arrived")
	
	# third -> first, measured as distance travelled from where it started
	p.camera_rig.third_person = false
	await step(quarter)
	var back_early: float = 1.0 - p.camera_rig._eased_view_blend()
	
	assert_lt(out_early, 0.25, "leaving the eye did not start slowly")
	assert_lt(back_early, 0.25, \
		"returning to the eye started fast: the curve is riding position, not progress")

func test_a_forced_view_is_a_journey_the_public_reading_can_follow() -> void:
	# THE BUG THIS PINS. A death forces third person by writing forced_view, and
	# in_third_person() answers `true` from that instant -- a whole blend before
	# the camera arrives. DeathSequence used to choose its framing from that
	# boolean, so the rig pitched into its third-person death pose while the eye
	# was still in the socket and the position caught up in a rush afterwards:
	# two halves of one change on two different clocks, which reads as a cut no
	# matter how well either half is eased.
	#
	# view_blend() is what it follows instead, so what is asserted here is that
	# the public reading is genuinely mid-journey while in_third_person() has
	# already committed -- not merely that it ends up in the right place.
	var p := _player()
	# Seeded, not merely built: _view_blend starts at -1 meaning "no view yet",
	# and view_blend() answers that with the destination. Reading the private
	# value is how the test tells a seeded eye from an unseeded one -- the public
	# reading cannot, which is the whole point of it.
	await step(6)
	assert_eq(p.camera_rig._eased_view_blend(), 0.0, "test setup: not seeded at the eye")
	
	# Through a status, the way a room forces one -- Player rewrites
	# camera_rig.forced_view from statuses every tick, so a field set by hand
	# lasts until the next one and proves nothing.
	p.statuses.apply(_force(Status.View.THIRD), p, 0)
	await step(1)
	assert_true(p.camera_rig.in_third_person(), 		"test setup: the force did not take immediately")
	var mid: float = p.camera_rig.view_blend()
	assert_lt(mid, 1.0, 		"the view arrived the moment it was forced: nothing can ride the journey")
	
	await step(int(ceil(p.config.camera.view_blend_time * 60.0)) + 2)
	assert_almost_eq(p.camera_rig.view_blend(), 1.0, 0.001, "the journey never ended")

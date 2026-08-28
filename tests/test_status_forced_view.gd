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

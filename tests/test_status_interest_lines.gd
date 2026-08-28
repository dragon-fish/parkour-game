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

func _line(tag: StringName, at: Vector3) -> InterestLine:
	var l := InterestLine.new()
	l.kind = InterestLine.Kind.LADDER
	l.tag = tag
	l.curve = Curve3D.new()
	l.curve.add_point(Vector3.ZERO)
	l.curve.add_point(Vector3(0.0, 3.0, 0.0))
	add_child_autofree(l)
	l.global_position = at
	return l

func _block(tag: StringName) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = Status.Effect.BLOCK_INTEREST_LINE
	s.subject = tag
	s.seconds = INF
	return s

func test_a_blocked_line_is_skipped_and_its_sibling_is_not() -> void:
	# The point of the whole effect: the grain is the OBJECT, not the class.
	# Blocking one pipe must leave the other one climbable.
	var p := _player()
	await step(1)
	var near := _line(&"pipe1", p.global_position + Vector3(1.0, 0.0, 0.0))
	var far := _line(&"pipe2", p.global_position + Vector3(3.0, 0.0, 0.0))
	p.enter_interest_line(near)
	p.enter_interest_line(far)
	assert_eq(p.nearest_interest_line(InterestLine.Kind.LADDER), near, \
		"the fixture did not pick the nearer line")
	p.statuses.apply(_block(&"pipe1"), p, 0)
	assert_eq(p.nearest_interest_line(InterestLine.Kind.LADDER), far, \
		"a blocked line was still offered, or its sibling was blocked too")

func test_an_untagged_line_cannot_be_blocked() -> void:
	var p := _player()
	await step(1)
	var anon := _line(&"", p.global_position + Vector3(1.0, 0.0, 0.0))
	p.enter_interest_line(anon)
	p.statuses.apply(_block(&""), p, 0)
	assert_eq(p.nearest_interest_line(InterestLine.Kind.LADDER), anon, \
		"an untagged line was blocked by an empty subject")

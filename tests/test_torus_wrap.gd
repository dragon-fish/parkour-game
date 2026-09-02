extends ParkourTest

# The plain is a torus: all four edges join. What is asserted here is the
# contract -- where the body lands, and the one state that forbids the move.
# The period itself is a tuning value and is not asserted.

const TestWorld = preload("res://tests/world_fixture.gd")

## A made-up hanging ledge, reused from test_grab_jump.gd's fixture: GrabMove
## never aborts on this query, unlike an ungrounded start() call with no
## pending_ledge handed over, so it is what lets the scripted-move test below
## hold the state it means to forbid a wrap during.
const LEDGE_TOP := 2.0
const LEDGE_FACE_Z := -1.5
const EDGE := Vector3(0.0, LEDGE_TOP, -1.6)
const FACE_NORMAL := Vector3(0.0, 0.0, 1.0)
const TOP_NORMAL := Vector3(0.0, 1.0, 0.0)

var _world: Dictionary = {}
var _wrap: TorusWrap
var _extra: Array[Node] = []

func after_each() -> void:
	for node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	if is_instance_valid(_wrap):
		_wrap.queue_free()
	_wrap = null
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _wrapped_world(period: float) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	# 20, not the 10 that settles most fixtures in this suite: this world's
	# placement height leaves the body still in free fall at 10 ticks (see
	# TestWorld.place()'s doc comment -- it DROPS the body onto the floor
	# rather than resting it there), and test_height_is_never_touched needs
	# the body actually grounded before it teleports it, or ordinary gravity
	# during the settle gets mistaken for the wrap touching height.
	await step(20)
	var player: Player = _world["player"]
	_wrap = TorusWrap.new()
	_wrap.player = player
	_wrap.period = period
	get_tree().root.add_child(_wrap)
	return player

## A player hanging on a made-up ledge near the world origin, well inside
## every period this file uses -- see the constants above.
func _hanging_player(period: float) -> Player:
	var player: Player = await _wrapped_world(period)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, LEDGE_TOP, 1.0)
	shape.shape = box
	body.add_child(shape)
	player.get_parent().add_child(body)
	body.global_position = Vector3(0.0, LEDGE_TOP * 0.5, LEDGE_FACE_Z - 0.5)
	_extra.append(body)
	var query := {"valid": true, "edge": EDGE, "top": EDGE,
			"normal": TOP_NORMAL, "face_normal": FACE_NORMAL}
	player.global_position = IntoGrabMove.hanging_pose(player, player.config, query)
	player.pending_ledge = query
	player.move_manager.start(Move.GRAB)
	return player

func test_crossing_the_east_edge_lands_you_in_the_west() -> void:
	var player: Player = await _wrapped_world(100.0)
	var height: float = player.global_position.y
	player.global_position = Vector3(51.0, height, 0.0)
	await step(2)
	assert_almost_eq(player.global_position.x, -49.0, 0.01,
		"crossing +x did not put the body one period back")
	assert_almost_eq(player.global_position.z, 0.0, 0.01,
		"the crossing moved the body on an axis it should not touch")

func test_the_north_edge_wraps_the_same_way() -> void:
	var player: Player = await _wrapped_world(100.0)
	var height: float = player.global_position.y
	player.global_position = Vector3(0.0, height, -51.0)
	await step(2)
	assert_almost_eq(player.global_position.z, 49.0, 0.01,
		"crossing -z did not put the body one period back")

func test_height_is_never_touched() -> void:
	# Only the plain wraps. The tower rises out of it, and a body climbing
	# must not be dragged back down to where it started.
	#
	# Tolerance is 0.05, not the 0.01 used elsewhere in this file: teleporting
	# 40 m into open air with no floor there triggers the ordinary
	# Walking-to-Falling transition (measured ~0.038 m of gravity drop over
	# two physics ticks), independent of TorusWrap -- TorusWrap itself never
	# writes to .y. 0.05 absorbs that drift while staying two orders of
	# magnitude below any offset the wrap itself could produce.
	var player: Player = await _wrapped_world(100.0)
	player.global_position = Vector3(51.0, 40.0, 0.0)
	await step(2)
	assert_almost_eq(player.global_position.y, 40.0, 0.05,
		"the wrap moved the body vertically")

func test_a_scripted_move_forbids_the_wrap() -> void:
	# A scripted move holds WORLD-SPACE target points -- a vault's curve, a
	# line's rail. Teleporting mid-move tears the body off its own path.
	var player: Player = await _hanging_player(100.0)
	assert_true(player.move_manager.current_holds_world_path(),
		"test setup: the manager did not enter a move that holds a world path")
	var height: float = player.global_position.y
	await step(1)
	player.global_position = Vector3(51.0, height, 0.0)
	await step(2)
	assert_almost_eq(player.global_position.x, 51.0, 0.01,
		"the body was teleported while a scripted move was driving it")

## A player climbing a 3 m vertical ladder at the world origin -- the same
## catch mechanics as test_ladder_move.gd's _climbing_player(), reused here to
## exercise the LineMove family: it is NOT a ScriptedMove, so this is the
## regression test for the bug the config-driven gate replaced -- a manager
## predicate keyed on `is ScriptedMove` let a ladder through untouched.
##
## Caught AT THE ORIGIN, well inside the period, so the catch itself cannot
## be disturbed by the wrap; the body is pushed past the edge by the test
## afterward, the same way _hanging_player's caller does it.
func _laddered_player(period: float) -> Player:
	var player: Player = await _wrapped_world(period)
	var line := InterestLine.new()
	line.kind = InterestLine.Kind.LADDER
	line.curve = Curve3D.new()
	line.curve.add_point(Vector3.ZERO)
	line.curve.add_point(Vector3(0.0, 3.0, 0.0))
	get_tree().root.add_child(line)
	_extra.append(line)
	var stand_off: float = player.config.ladder.stand_off
	player.global_position = Vector3(0.0, player.global_position.y, -stand_off)
	player.rotation.y = PI
	for i in 10:
		await step(1)
		if player.move_manager.current_name == Move.LADDER:
			break
	assert_eq(player.move_manager.current_name, Move.LADDER,
		"test setup: never caught the ladder")
	return player

## Checked through the `wrapped` SIGNAL via a DIRECT call to
## _physics_process(), not the usual await step(): every tick LadderMove
## re-derives the body's position from the line's own world-space sample
## (`_line.sample(_offset)`) and TorusWrap runs after Player in tree order, so
## by the time a stepped frame's wrap check would run, a ladder that was
## never gated has often already slid the body back near the line on its
## own -- an unrelated correction that would hide the very bug this test
## exists to catch. Calling _physics_process() directly observes the gate's
## own decision on the tick the edge is crossed, before anything else can
## paper over it.
func test_a_line_move_forbids_the_wrap() -> void:
	var player: Player = await _laddered_player(100.0)
	assert_true(player.move_manager.current_holds_world_path(),
		"test setup: the manager did not report the ladder as holding a world path")
	var seen: Array[Vector3] = []
	_wrap.wrapped.connect(func(offset: Vector3) -> void: seen.append(offset))
	var height: float = player.global_position.y
	player.global_position = Vector3(51.0, height, 0.0)
	_wrap._physics_process(0.0)
	assert_eq(seen.size(), 0,
		"the wrap fired while a line-family move was driving the body")

func test_the_offset_is_announced() -> void:
	# Task 6 moves locked obstacles by this offset, so it has to be exact.
	var player: Player = await _wrapped_world(100.0)
	var seen: Array[Vector3] = []
	_wrap.wrapped.connect(func(offset: Vector3) -> void: seen.append(offset))
	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	await step(2)
	assert_eq(seen.size(), 1, "the wrap did not announce itself exactly once")
	assert_almost_eq(seen[0].x, -100.0, 0.01, "the announced offset is wrong")

extends ParkourTest

# Progress is a line: it advances when the player performs the move the
# current lesson teaches, and it never goes backwards. Beyond the counting,
# this asserts the shape of a lesson's life -- built ahead of the player, one
# block, and still visible while it leaves.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _director: TutorialDirector
var _loose: Array[Node] = []

func _extra_free(node: Node) -> void:
	_loose.append(node)

func after_each() -> void:
	for node in _loose:
		if is_instance_valid(node):
			node.queue_free()
	_loose.clear()
	if is_instance_valid(_director):
		_director.queue_free()
	_director = null
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _directed(lessons: Array[Dictionary]) -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(10)
	var player: Player = _world["player"]
	_director = TutorialDirector.new()
	_director.player = player
	_director.lessons = lessons
	get_tree().root.add_child(_director)
	await step(1)
	return player

func test_performing_the_taught_move_advances() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
		{teaches = Move.SLIDE},
	])
	assert_eq(_director.index, 0, "test setup: the director did not start at the first lesson")
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 1, "performing the taught move did not advance")

func test_an_unrelated_move_does_not_advance() -> void:
	var player: Player = await _directed([
		{teaches = Move.SLIDE},
	])
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 0, "an unrelated move advanced the lesson")

func test_a_lesson_passes_only_once() -> void:
	# Doing it twice is practice, not progress. Without this the second entry
	# would skip the NEXT lesson, which the player has not seen yet.
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
		{teaches = Move.SLIDE},
	])
	player.move_manager.start(Move.CROUCH)
	await step(2)
	player.move_manager.start(Move.WALKING)
	await step(2)
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 1, "repeating a passed lesson advanced past an unseen one")

func test_the_last_lesson_announces_the_end_once() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
	])
	var ends: Array[int] = [0]
	_director.finished.connect(func() -> void: ends[0] += 1)
	player.move_manager.start(Move.CROUCH)
	await step(2)
	player.move_manager.start(Move.WALKING)
	await step(2)
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(ends[0], 1, "the end of the tutorial fired %d times" % ends[0])

func test_an_empty_table_neither_advances_nor_crashes() -> void:
	# A level under construction has no lessons yet. It must not crash and
	# must not silently declare itself finished (which would make the tower
	# rise inexplicably). The teaching director sits still and waits.
	var player: Player = await _directed([])
	player.move_manager.start(Move.CROUCH)
	await step(2)
	assert_eq(_director.index, 0, "an empty table moved its index")

func test_a_wrap_carries_the_standing_obstacle() -> void:
	# The body is shifted one period on a crossing. An obstacle already
	# growing in front of it must take the same step, or what was dead ahead
	# is suddenly a hundred metres behind.
	var player: Player = await _directed([{teaches = Move.CROUCH}])
	var wrap := TorusWrap.new()
	wrap.player = player
	wrap.period = 100.0
	get_tree().root.add_child(wrap)
	_extra_free(wrap)
	_director.wrap = wrap
	_director.attach_wrap()

	var obstacle := TutorialObstacle.new()
	obstacle.player = player
	get_tree().root.add_child(obstacle)
	_extra_free(obstacle)
	await step(2)
	obstacle.lock()
	_director.adopt(obstacle)
	var before: Vector3 = obstacle.anchor

	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	await step(2)
	assert_almost_eq(obstacle.anchor.x, before.x - 100.0, 0.01,
		"the standing obstacle did not travel with the wrap")

func test_adopting_the_same_obstacle_twice_does_not_double_the_wrap_shift() -> void:
	# A double-adopt puts the same obstacle in _standing twice. _on_wrapped
	# loops _standing calling shift_by() on each entry, so a duplicate would
	# shift the obstacle by TWO periods on one crossing -- landing it a full
	# period behind the body shift_by exists to keep it in step with.
	var player: Player = await _directed([{teaches = Move.CROUCH}])
	var wrap := TorusWrap.new()
	wrap.player = player
	wrap.period = 100.0
	get_tree().root.add_child(wrap)
	_extra_free(wrap)
	_director.wrap = wrap
	_director.attach_wrap()

	var obstacle := TutorialObstacle.new()
	obstacle.player = player
	get_tree().root.add_child(obstacle)
	_extra_free(obstacle)
	await step(2)
	obstacle.lock()
	_director.adopt(obstacle)
	_director.adopt(obstacle)
	var before: Vector3 = obstacle.anchor

	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	await step(2)
	assert_almost_eq(obstacle.anchor.x, before.x - 100.0, 0.01,
		"adopting the same obstacle twice shifted it more than one period")

## A stand-in lesson scene: a root plus the Content node the tutorial takes.
func _lesson_scene(child_name: String) -> PackedScene:
	var root := Node3D.new()
	root.name = "Arena"
	var content := Node3D.new()
	content.name = "Content"
	var mesh := MeshInstance3D.new()
	mesh.name = child_name
	mesh.mesh = BoxMesh.new()
	content.add_child(mesh)
	root.add_child(content)
	content.owner = root
	mesh.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func test_the_first_lesson_grows_its_own_scene_in_front_of_the_player() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH, scene = _lesson_scene("Wall")},
	])
	await step(3)
	assert_eq(_director.live_count(), 1, "the first lesson did not build anything")
	var obstacle: TutorialObstacle = _director.current_obstacle()
	assert_not_null(obstacle, "no obstacle was placed")
	assert_not_null(obstacle.find_child("Wall", true, false),
		"the lesson's own geometry is not under the obstacle")
	var forward: Vector3 = -player.global_transform.basis.z
	var to_it: Vector3 = obstacle.anchor - player.global_position
	to_it.y = 0.0
	assert_gt(forward.normalized().dot(to_it.normalized()), 0.9,
		"the lesson was not built ahead of the player")

func test_passing_a_lesson_collapses_it_and_builds_the_next() -> void:
	var player: Player = await _directed([
		{teaches = Move.CROUCH, scene = _lesson_scene("First")},
		{teaches = Move.SLIDE, scene = _lesson_scene("Second")},
	])
	await step(3)
	player.move_manager.start(Move.CROUCH)
	await step(3)
	assert_not_null(_director.find_child("Second", true, false),
		"the next lesson was not built")
	# The old one is on its way out, not gone on the same frame: the player is
	# meant to see it go.
	assert_not_null(_director.find_child("First", true, false),
		"the passed lesson vanished instantly instead of collapsing")

func test_a_lesson_without_a_scene_still_advances() -> void:
	# The table is authored a row at a time; a row with no scene yet must not
	# stop the sequence from being testable.
	var player: Player = await _directed([
		{teaches = Move.CROUCH},
		{teaches = Move.SLIDE},
	])
	await step(3)
	player.move_manager.start(Move.CROUCH)
	await step(3)
	assert_eq(_director.index, 1, "a sceneless lesson blocked the sequence")

func test_the_lessons_own_geometry_fades_in_with_the_block() -> void:
	# A lesson is ONE block: the fade acts on the whole of its geometry, not on
	# the shell that carries it. GrowingSolid gathers the meshes it fades once,
	# in its own _ready(), so content hung on after the block is already in the
	# tree is in no list -- the lesson stands there opaque from the first frame
	# while the fade runs over nothing.
	await _directed([
		{teaches = Move.CROUCH, scene = _lesson_scene("Wall")},
	])
	await step(3)
	var obstacle: TutorialObstacle = _director.current_obstacle()
	var mesh: GeometryInstance3D = obstacle.find_child("Wall", true, false)
	assert_not_null(mesh, "test setup: the lesson geometry is not under the obstacle")
	var early: float = mesh.transparency
	assert_gt(early, 0.0, "the lesson was fully drawn before its block had grown")
	await step(30)
	assert_lt(mesh.transparency, early, "the lesson did not fade in as the block grew")

extends ParkourTest

# Progress is a line: it advances when the player performs the move the
# current lesson teaches, and it never goes backwards. What the lesson LOOKS
# like is Task 4's business; this asserts only the counting.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _director: TutorialDirector

func after_each() -> void:
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

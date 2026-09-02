extends ParkourTest

# The whole loop, on the real sample scene rather than a stand-in: a lesson is
# built ahead of the player, doing the move it teaches sends it away and brings
# the next, and a crossing changes nothing about where any of it stands
# relative to him.

const TestWorld = preload("res://tests/world_fixture.gd")
const SAMPLE := "res://scenes/levels/lessons/sample_wall.tscn"

var _world: Dictionary = {}
var _loose: Array[Node] = []

func after_each() -> void:
	for node in _loose:
		if is_instance_valid(node):
			node.queue_free()
	_loose.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _running_tutorial() -> Dictionary:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	# 20, not the 10 that settles most fixtures in this suite: place() DROPS
	# the body onto the floor rather than resting it there (see
	# world_fixture.gd), and measured here the body is still in free fall at
	# frame 14 and only lands around frame 16 -- see TorusWrap's own fixture,
	# which hit the same gap for the same reason. The crossing test below
	# reads player.global_position.y at 0.01 tolerance, so it needs the body
	# actually grounded, not merely close.
	await step(20)
	var player: Player = _world["player"]

	var wrap := TorusWrap.new()
	wrap.player = player
	wrap.period = 100.0
	get_tree().root.add_child(wrap)
	_loose.append(wrap)

	var director := TutorialDirector.new()
	director.player = player
	director.wrap = wrap
	var sample: PackedScene = load(SAMPLE)
	director.lessons = [
		{teaches = Move.CROUCH, scene = sample},
		{teaches = Move.SLIDE, scene = sample},
	]
	get_tree().root.add_child(director)
	_loose.append(director)
	await step(3)
	return {player = player, director = director, wrap = wrap}

func test_the_sample_scene_carries_a_content_node() -> void:
	# Guards the convention itself: a lesson whose geometry is not under
	# Content contributes nothing and does so silently.
	var content := LessonContent.take(load(SAMPLE))
	assert_not_null(content, "the sample lesson has no Content node")
	content.free()

func test_the_first_lesson_stands_in_front_of_the_player() -> void:
	var live: Dictionary = await _running_tutorial()
	var director: TutorialDirector = live["director"]
	assert_eq(director.live_count(), 1, "the loop did not build the first lesson")
	assert_not_null(director.find_child("Wall", true, false),
		"the sample lesson's geometry is not in the world")

func test_a_crossing_does_not_move_the_lesson_relative_to_the_player() -> void:
	# THE INVARIANT. A wrap crossing -- TorusWrap's own teleport -- may not
	# change the lesson's position relative to the player.
	#
	# "before" is captured AFTER the player is put at the edge and BEFORE the
	# wrap tick runs, not at the top of the test: the crossing is the only
	# event under test, and measuring across the approach to the edge as well
	# would fold 51 m of ordinary travel into what is supposed to isolate the
	# wrap's own effect.
	var live: Dictionary = await _running_tutorial()
	var player: Player = live["player"]
	var director: TutorialDirector = live["director"]
	var obstacle: TutorialObstacle = director.current_obstacle()

	player.global_position = Vector3(51.0, player.global_position.y, 0.0)
	var before: Vector3 = obstacle.anchor - player.global_position
	await step(3)

	var after: Vector3 = obstacle.anchor - player.global_position
	assert_almost_eq(after.distance_to(before), 0.0, 0.01,
		"the crossing moved the lesson relative to the player: %s -> %s" % [before, after])

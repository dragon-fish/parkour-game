extends ParkourTest

# The locomotion clip's playback rate follows how fast the body is actually
# travelling, so a cycle authored at one pace does not slide its feet across the
# ground at every other pace.
#
# Built on a SYNTHETIC body -- a bare Node3D with an AnimationPlayer carrying
# named clips -- rather than on the model that motivated it. That model is a
# CC BY-NC-SA asset the repo deliberately does not track (see .gitignore), so a
# test that loaded it would fail on any fresh clone. Nothing here needs a mesh:
# what is under test is the graph player.gd builds and the parameter
# CharacterAnimator writes.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## A body carrying just enough for _wire_body_animation() to build a graph.
func _attach_synthetic_body(player: Player) -> AnimationTree:
	var body := Node3D.new()
	body.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in [&"idle", &"run"]:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player._wire_body_animation(body)
	return player.get_node("BodyRoot").get_node_or_null("AnimationTree") as AnimationTree

func _scale_of(tree: AnimationTree) -> float:
	return float(tree.get("parameters/%s/scale" % CharacterAnimator.GRAPH_TIME_SCALE))

func test_the_graph_still_reaches_its_state_machine() -> void:
	# The state machine moved one level down to make room for the time scale,
	# which moves travel()'s parameter path with it. A wrong path is not an
	# error -- anim_tree.get() simply returns null and the body silently stops
	# animating -- so this is checked rather than assumed.
	var player: Player = await _player()
	var tree: AnimationTree = _attach_synthetic_body(player)
	assert_not_null(tree, "no AnimationTree was built at all")
	var playback = tree.get("parameters/%s/playback" % CharacterAnimator.GRAPH_STATES)
	assert_not_null(playback, "travel()'s playback is unreachable at the new path")
	var root := tree.tree_root as AnimationNodeBlendTree
	assert_not_null(root, "the graph root is not a blend tree")
	assert_true(root.has_node(CharacterAnimator.GRAPH_TIME_SCALE), \
		"the graph has no time-scale node to drive")

func test_running_faster_plays_the_clip_faster() -> void:
	var player: Player = await _player()
	var tree: AnimationTree = _attach_synthetic_body(player)
	var animator: CharacterAnimator = \
		player.get_node("BodyRoot").get_node("CharacterAnimator")
	var reference: float = player.body_run_reference_speed

	animator._drive_speed(&"run")
	var at_rest: float = _scale_of(tree)

	# travel_speed() is maintained by Player, so it is set directly here rather
	# than driven up to speed over dozens of ticks -- what is under test is the
	# mapping from speed to rate, not the acceleration curve.
	player._travel_speed = reference
	animator._drive_speed(&"run")
	assert_almost_eq(_scale_of(tree), 1.0, 0.001, \
		"running at the reference speed did not play the clip at its authored rate")

	player._travel_speed = reference * 1.5
	animator._drive_speed(&"run")
	assert_almost_eq(_scale_of(tree), 1.5, 0.001, "half again the speed did not scale the clip")
	assert_lt(at_rest, 1.0, "a standing body was already at full rate, so this proves nothing")
func test_idle_is_never_slowed_down() -> void:
	# THE OBVIOUS TRAP. Scaling every clip by travel speed means a standing body
	# plays its idle at the floor rate -- a breathing loop in slow motion,
	# slowest exactly when the body is most visibly doing nothing else. Only
	# clips whose feet are carrying the body are matched.
	var player: Player = await _player()
	var tree: AnimationTree = _attach_synthetic_body(player)
	var animator: CharacterAnimator = \
		player.get_node("BodyRoot").get_node("CharacterAnimator")

	player._travel_speed = 0.0
	animator._drive_speed(&"idle")
	assert_almost_eq(_scale_of(tree), 1.0, 0.001, "a standing idle was played in slow motion")

	player._travel_speed = 40.0
	animator._drive_speed(&"jump")
	assert_almost_eq(_scale_of(tree), 1.0, 0.001, "a jump's timing was taken from the ground")

func test_a_zero_reference_leaves_every_clip_alone() -> void:
	# The opt-out: a body whose clip cadence has not been measured should animate
	# exactly as it did before this existed, not at some guessed rate.
	var player: Player = await _player()
	var tree: AnimationTree = _attach_synthetic_body(player)
	var animator: CharacterAnimator = \
		player.get_node("BodyRoot").get_node("CharacterAnimator")

	player.body_run_reference_speed = 0.0
	player._travel_speed = 30.0
	animator._drive_speed(&"run")
	assert_almost_eq(_scale_of(tree), 1.0, 0.001, "a disabled reference still scaled the clip")

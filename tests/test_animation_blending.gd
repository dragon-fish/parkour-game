extends ParkourTest

# Every clip cross-fades into every other one, instead of cutting.
#
# The graph used to carry three transitions -- Start->idle, idle->run,
# run->End -- and travel() reached everything else by what Godot's own docs
# call teleporting: "if the path does not connect from the current state, the
# animation will play after the state teleports", with reset_on_teleport
# defaulting to true so the incoming clip restarts from frame zero too. A limb
# mid-swing appears wherever the next clip's first frame puts it.
#
# Only idle->run was ever a real transition, and with xfade_time at its 0.0
# default even that was a cut -- which is the one the owner saw, as the neck
# lurching forward on entering a run.

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

## Synthetic, not the model that motivated this: that model is CC BY-NC-SA and
## deliberately untracked, so loading it would break any fresh clone.
func _graph_for(player: Player, clips: Array) -> AnimationNodeStateMachine:
	var body := Node3D.new()
	body.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in clips:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player._wire_body_animation(body)
	var tree: AnimationTree = player.get_node("BodyRoot").get_node("AnimationTree")
	var root := tree.tree_root as AnimationNodeBlendTree
	return root.get_node(CharacterAnimator.GRAPH_STATES) as AnimationNodeStateMachine

func test_every_pair_of_clips_is_connected() -> void:
	# THE TELEPORT. run->idle and anything->jump had no edge at all, so they
	# were cuts with a rewind, not transitions.
	var player: Player = await _player()
	var clips := [&"idle", &"run", &"jump"]
	var graph: AnimationNodeStateMachine = _graph_for(player, clips)
	for from_name in clips:
		for to_name in clips:
			if from_name == to_name:
				continue
			assert_true(graph.has_transition(from_name, to_name), \
				"%s -> %s has no edge, so travel() teleports" % [from_name, to_name])

func test_no_clip_transitions_to_itself() -> void:
	# CharacterAnimator re-issues travel() every tick, by design, so an edge
	# from a state to itself is an invitation to restart the current clip sixty
	# times a second.
	var player: Player = await _player()
	var clips := [&"idle", &"run", &"jump"]
	var graph: AnimationNodeStateMachine = _graph_for(player, clips)
	for clip in clips:
		assert_false(graph.has_transition(clip, clip), \
			"%s can transition to itself" % clip)
func test_the_edges_never_fire_on_their_own() -> void:
	# ADVANCE_MODE_ENABLED, not AUTO. An unconditioned AUTO transition fires the
	# instant it is evaluated rather than when its animation finishes, which
	# with a fully connected graph would race through every state in one frame.
	var player: Player = await _player()
	var graph: AnimationNodeStateMachine = _graph_for(player, [&"idle", &"run", &"jump"])
	for i in graph.get_transition_count():
		var transition: AnimationNodeStateMachineTransition = graph.get_transition(i)
		assert_eq(transition.advance_mode, \
			AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED, \
			"an edge can advance without travel() asking it to")
func test_a_reversible_clip_gets_a_backward_twin_and_edges_to_it() -> void:
	# Walking backwards plays the run reversed. Not via a negative time scale --
	# AnimationNodeTimeScale documents reversal, but a negative value has a long
	# tail of reported trouble with LOOPING clips (godotengine/godot#27215 is
	# exactly "plays backwards, then rewinds and stops") and every clip here
	# loops. A second node with play_mode = PLAY_MODE_BACKWARD reaches the same
	# result without a negative scale existing.
	var player: Player = await _player()
	var graph: AnimationNodeStateMachine = _graph_for(player, [&"Sprint", &"idle"])
	var twin := "Sprint" + Player.BACKWARD_SUFFIX
	assert_true(graph.has_node(twin), "the reversible clip got no reversed twin")
	assert_false(graph.has_node("idle" + Player.BACKWARD_SUFFIX), \
		"a clip that is not locomotion got a reversed twin")
	var node := graph.get_node(twin) as AnimationNodeAnimation
	assert_eq(node.play_mode, AnimationNodeAnimation.PLAY_MODE_BACKWARD, \
		"the twin plays forwards, so it is just a duplicate")
	assert_eq(String(node.animation), "Sprint", "the twin points at a different clip")
	# EDGES, or travel() teleports to it -- a visible snap every time the player
	# changes direction.
	assert_true(graph.has_transition("Sprint", twin), "forward to backward is a teleport")
	assert_true(graph.has_transition(twin, "idle"), "backward to idle is a teleport")

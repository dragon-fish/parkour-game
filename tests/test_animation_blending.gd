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

func test_the_edges_actually_cross_fade() -> void:
	# A connected edge with xfade_time still at its 0.0 default is a cut with
	# extra steps -- which is exactly what idle->run was.
	var player: Player = await _player()
	var graph: AnimationNodeStateMachine = _graph_for(player, [&"idle", &"run"])
	var blended := 0
	for i in graph.get_transition_count():
		var transition: AnimationNodeStateMachineTransition = graph.get_transition(i)
		assert_almost_eq(transition.xfade_time, player.body_animation_blend_time, 0.0001, \
			"an edge was left at a %.2f s fade" % transition.xfade_time)
		blended += 1
	assert_gt(blended, 0, "there were no transitions to check at all")

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

func test_a_zero_blend_time_restores_the_hard_cut() -> void:
	var player: Player = await _player()
	player.body_animation_blend_time = 0.0
	var graph: AnimationNodeStateMachine = _graph_for(player, [&"idle", &"run"])
	for i in graph.get_transition_count():
		assert_almost_eq(graph.get_transition(i).xfade_time, 0.0, 0.0001, \
			"a zero blend time still faded")

func test_a_reversible_clip_gets_a_backward_twin_and_edges_to_it() -> void:
	# Walking backwards plays the run reversed. Not via a negative time scale --
	# AnimationNodeTimeScale documents reversal, but a negative value has a long
	# tail of reported trouble with LOOPING clips (godotengine/godot#27215 is
	# exactly "plays backwards, then rewinds and stops") and every clip here
	# loops. A second node with play_mode = PLAY_MODE_BACKWARD reaches the same
	# result without a negative scale existing.
	var player: Player = await _player()
	var graph: AnimationNodeStateMachine = _graph_for(player, [&"Jog_Fwd", &"idle"])
	var twin := "Jog_Fwd" + Player.BACKWARD_SUFFIX
	assert_true(graph.has_node(twin), "the reversible clip got no reversed twin")
	assert_false(graph.has_node("idle" + Player.BACKWARD_SUFFIX), \
		"a clip that is not locomotion got a reversed twin")
	var node := graph.get_node(twin) as AnimationNodeAnimation
	assert_eq(node.play_mode, AnimationNodeAnimation.PLAY_MODE_BACKWARD, \
		"the twin plays forwards, so it is just a duplicate")
	assert_eq(String(node.animation), "Jog_Fwd", "the twin points at a different clip")
	# EDGES, or travel() teleports to it -- a visible snap every time the player
	# changes direction.
	assert_true(graph.has_transition("Jog_Fwd", twin), "forward to backward is a teleport")
	assert_true(graph.has_transition(twin, "idle"), "backward to idle is a teleport")

func test_slide_exits_fade_for_longer_than_everything_else() -> void:
	# A slide ends into a recovery the player cannot act through, so the body
	# coming out of it should look like it is picking itself up rather than
	# changing its mind.
	var player: Player = await _player()
	var graph: AnimationNodeStateMachine = _graph_for(player, [&"Slide", &"idle", &"Jog_Fwd"])
	var slow := 0
	var normal := 0
	for i in graph.get_transition_count():
		var transition: AnimationNodeStateMachineTransition = graph.get_transition(i)
		if is_equal_approx(transition.xfade_time, player.body_slide_exit_blend_time):
			slow += 1
		elif is_equal_approx(transition.xfade_time, player.body_animation_blend_time):
			normal += 1
	assert_gt(slow, 0, "no edge got the longer slide-exit fade")
	assert_gt(normal, 0, "every edge got the slide-exit fade, not just the slide's")
	# INTO the slide is ordinary; only leaving it is slow.
	assert_almost_eq(graph.get_transition( \
		_transition_index(graph, "idle", "Slide")).xfade_time, \
		player.body_animation_blend_time, 0.0001, \
		"entering a slide got the slow fade too")

func _transition_index(graph: AnimationNodeStateMachine, from: String, to: String) -> int:
	for i in graph.get_transition_count():
		if String(graph.get_transition_from(i)) == from and String(graph.get_transition_to(i)) == to:
			return i
	return -1

func test_a_slide_into_a_crouch_does_not_get_the_long_fade() -> void:
	# The owner's distinction: a slide into a CROUCH is continuous -- the body
	# simply stays down -- while a slide into a run is the picking-yourself-up
	# the half second exists for. The first version gave every exit from a
	# slide the long fade, including the one that is not a stand-up at all.
	var player: Player = await _player()
	var graph: AnimationNodeStateMachine = \
		_graph_for(player, [&"Slide", &"Crouch_Idle", &"Jog_Fwd"])
	var to_crouch: int = _transition_index(graph, "Slide", "Crouch_Idle")
	var to_run: int = _transition_index(graph, "Slide", "Jog_Fwd")
	assert_gt(to_crouch, -1, "slide to crouch has no edge at all")
	assert_gt(to_run, -1, "slide to run has no edge at all")
	assert_almost_eq(graph.get_transition(to_crouch).xfade_time, \
		player.body_animation_blend_time, 0.0001, \
		"staying low after a slide waited out the stand-up fade")
	assert_almost_eq(graph.get_transition(to_run).xfade_time, \
		player.body_slide_exit_blend_time, 0.0001, \
		"standing up out of a slide did not get the long fade")

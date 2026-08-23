extends ParkourTest

# A clip can be trimmed to the part of it this project actually uses.
#
# ✅ THE OWNER FOUND IT: "the vault and grab animations play far too late -- the
# character has nearly landed on the other side before the frame where the hand
# plants." The packs author WHOLE ACTIONS, run-up included, and this project
# starts them at the moment of contact. So the approach half plays while the
# body is already going over, and the half that matters arrives after the move
# has ended.
#
# Their other idea was to start the animation early, predictively. This does the
# same job without touching gameplay: skip the run-up rather than guess when it
# should have begun.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A body carrying one 2 s clip, with `timings` applied to the graph.
func _node_for(timings: Dictionary) -> AnimationNodeAnimation:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var body := Node3D.new()
	body.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for clip in [&"SafetyVault", &"Idle"]:
		var animation := Animation.new()
		animation.length = 2.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player.body_clip_timings = timings
	player._wire_body_animation(body)
	var tree := player.get_node("BodyRoot/AnimationTree") as AnimationTree
	var graph := (tree.tree_root as AnimationNodeBlendTree).get_node(
		CharacterAnimator.GRAPH_STATES) as AnimationNodeStateMachine
	return graph.get_node("SafetyVault") as AnimationNodeAnimation

func test_an_untimed_clip_is_left_entirely_alone() -> void:
	# Every body attached before this existed must play exactly as it did.
	var node: AnimationNodeAnimation = await _node_for({})
	assert_false(node.use_custom_timeline, "a clip with no entry was trimmed anyway")

func test_a_start_offset_skips_the_run_up() -> void:
	var node: AnimationNodeAnimation = await _node_for({
		&"SafetyVault": [0.8, 0.0],
	})
	assert_true(node.use_custom_timeline, "the trim was not applied")
	assert_almost_eq(node.start_offset, 0.8, 0.0001, "the clip does not start where asked")
	# Length 0 means "to the end", which for a 2 s clip trimmed at 0.8 is 1.2.
	assert_almost_eq(node.timeline_length, 1.2, 0.0001,
		"a length of 0 did not run to the end of the clip")

func test_a_length_stretches_the_kept_part_to_fit() -> void:
	# The point of the length: a 1.5 s clip has to fit a 0.65 s vault, and
	# stretching is what makes the plant land inside the move rather than after
	# it. Without stretch_time_scale the trim only skips the run-up.
	var node: AnimationNodeAnimation = await _node_for({
		&"SafetyVault": [0.8, 0.65],
	})
	assert_almost_eq(node.timeline_length, 0.65, 0.0001, "the kept part was not resized")
	assert_true(node.stretch_time_scale,
		"the kept part is cut off at 0.65 s rather than stretched into it")

func test_a_malformed_entry_is_ignored_rather_than_fatal() -> void:
	# Hand-pasted from a debug tool, like the offsets beside them.
	var node: AnimationNodeAnimation = await _node_for({&"SafetyVault": 0.8})
	assert_false(node.use_custom_timeline, "a malformed entry was accepted")

# --- a trimmed clip still fills its move ----------------------------------------

func test_the_fit_measures_what_is_left_after_a_trim() -> void:
	# ✅ THE OWNER, reasoning it out before the code was read: "总计 20 帧的动画在 1s
	# 内播完，我跳过开头 6 帧，就应该是 1s 内播放 6-20 帧的动画?"
	#
	# ⚠️ IT SHOULD, AND IT DID NOT. _clip_length() returned the WHOLE animation's
	# length whatever the trim said, so the scripted fit was computed for footage
	# that was no longer being played: a clip trimmed to 70% of itself still got
	# the untrimmed clip's time scale, finished at 70% of the move, and left the
	# rest of it running on a held pose.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	var body := TestWorld.build_stub_body("", Vector3.ZERO, true, [&"idle", &"Trimmed"])
	player._attach_body(body)
	await step(2)
	var animator := player.get_node("BodyRoot/CharacterAnimator") as CharacterAnimator
	var anim_player := player.body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim_player.get_animation(&"Trimmed").length = 1.0

	assert_almost_eq(animator._clip_length(&"Trimmed"), 1.0, 0.001,
		"an untrimmed clip did not report its own length")
	# Skip the first three tenths; nothing says how long to play, so it runs on
	# to the end.
	player.body_clip_timings = {&"Trimmed": [0.3, 0.0]}
	assert_almost_eq(animator._clip_length(&"Trimmed"), 0.7, 0.001,
		"a clip trimmed at the start reported %.3f instead of what is left"
		% animator._clip_length(&"Trimmed"))
	# And an explicit length wins outright.
	player.body_clip_timings = {&"Trimmed": [0.3, 0.4]}
	assert_almost_eq(animator._clip_length(&"Trimmed"), 0.4, 0.001,
		"an explicit trim length was ignored")
	TestWorld.teardown(world)
	await step(1)

extends ParkourTest

# Trimming a clip to "play frames 11..39" must play frames 11..39.
#
# THE OWNER, on a 39-frame clip trimmed from frame 11: "最后11帧会定格，不应该是这样
# 的，期望是程序动画期间等比播放 11-39 帧."
#
# These run against a bare AnimationTree rather than the player, deliberately.
# The question they answer is what GODOT does with a given combination of
# start_offset / timeline_length / stretch_time_scale, and a player, a body, a
# blend tree and a move on top of that would only be four more things that could
# be responsible for the answer.

const CLIP := &"Clip"
const FPS := 30.0
const FRAMES := 39
const FROM_FRAME := 11

## An AnimationTree playing one clip through a state machine, with the frame
## INDEX written into a marker's x so the pose says which source frame made it.
func _rig(stretch: bool) -> Dictionary:
	var root := Node3D.new()
	var marker := Node3D.new()
	marker.name = "Marker"
	root.add_child(marker)
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	var animation := Animation.new()
	animation.length = float(FRAMES) / FPS
	animation.step = 1.0 / FPS
	var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Marker"))
	animation.position_track_insert_key(track, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(track, float(FRAMES) / FPS,
		Vector3(float(FRAMES), 0.0, 0.0))
	var library := AnimationLibrary.new()
	library.add_animation(CLIP, animation)
	anim_player.add_animation_library("", library)

	var node := AnimationNodeAnimation.new()
	node.animation = CLIP
	node.use_custom_timeline = true
	node.start_offset = float(FROM_FRAME) / FPS
	node.timeline_length = float(FRAMES - FROM_FRAME) / FPS
	node.stretch_time_scale = stretch
	var machine := AnimationNodeStateMachine.new()
	machine.add_node(CLIP, node)
	var tree := AnimationTree.new()
	tree.tree_root = machine
	tree.anim_player = NodePath("../AnimationPlayer")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	root.add_child(tree)
	add_child_autofree(root)
	tree.active = true
	await step(1)
	tree.get("parameters/playback").start(CLIP, false)
	return {"marker": marker}

## The posed frame on each of the next `ticks` physics ticks.
func _trace(rig: Dictionary, ticks: int) -> Array:
	var seen: Array = []
	for i in ticks:
		await step(1)
		seen.append(float(rig["marker"].position.x))
	return seen

func test_a_trim_plays_the_kept_frames_at_their_own_pace() -> void:
	var rig: Dictionary = await _rig(false)
	# 28 kept frames at 30 fps, one physics tick being half a clip frame.
	var seen: Array = await _trace(rig, (FRAMES - FROM_FRAME) * 2)
	assert_almost_eq(float(seen[0]), float(FROM_FRAME), 0.6,
		"the trim did not start on the frame it was asked to")
	assert_almost_eq(float(seen[seen.size() - 1]), float(FRAMES), 0.6,
		"the kept range did not reach the end of the clip in its own length")
	# ⚠️ AND NOTHING HELD ON THE WAY. A freeze is the failure being guarded
	# against here, so it is not enough to check the two ends.
	var held := 0
	for i in range(1, seen.size()):
		if is_equal_approx(float(seen[i]), float(seen[i - 1])):
			held += 1
	assert_lt(held, 3, "the pose stopped advancing partway through the trim")

func test_stretching_the_timeline_freezes_the_end_of_the_trim() -> void:
	# THE PAIR, and the reason stretch_time_scale is off in
	# Player.apply_clip_timing(). This is not a hypothetical: it is what the
	# owner watched happen, reproduced with nothing else in the way.
	#
	# stretch_time_scale maps the animation's ORIGINAL length onto
	# timeline_length, so the rate is computed from all 39 frames while
	# start_offset means only 28 are left to play. They run 39/28 = 1.39x too
	# fast, finish early, and the remainder of the timeline is a held pose.
	var rig: Dictionary = await _rig(true)
	var seen: Array = await _trace(rig, (FRAMES - FROM_FRAME) * 2)
	var trailing := 0
	for i in range(seen.size() - 1, 0, -1):
		if not is_equal_approx(float(seen[i]), float(seen[i - 1])):
			break
		trailing += 1
	assert_gt(trailing, 8,
		"stretching no longer freezes the tail -- if Godot changed, so can the flag")

func test_the_player_asks_for_the_kept_range_without_the_stretch() -> void:
	# The properties the game actually writes, which is the other half: the
	# behaviour above is only reached through this combination.
	var node := AnimationNodeAnimation.new()
	var rig: Dictionary = await _rig(false)
	var anim_player: AnimationPlayer = rig["marker"].get_parent() \
		.get_node("AnimationPlayer") as AnimationPlayer
	var player := Player.new()
	# A `to frame` of 0 means "run on to the end", stored as a length of 0.
	player.body_clip_timings[CLIP] = [float(FROM_FRAME) / FPS, 0.0]
	player.apply_clip_timing(node, CLIP, anim_player)
	player.free()
	assert_true(node.use_custom_timeline, "the trim was not applied at all")
	assert_almost_eq(node.start_offset, float(FROM_FRAME) / FPS, 0.001,
		"the trim did not start where it was told to")
	assert_almost_eq(node.timeline_length, float(FRAMES - FROM_FRAME) / FPS, 0.001,
		"a length of 0 did not become 'the rest of the clip'")
	assert_false(node.stretch_time_scale,
		"the stretch is back, and with it the frozen tail")

# A trim set AFTER the body is attached still reaches the graph.
#
# THE OWNER: "我明明调了 from 结果动画还是从第一帧开始播." The trim was in the
# dictionary and nowhere else. The game writes the table before it attaches the
# body, so _wire_body_animation() picks it up as it builds each node; the
# animation lab loads its own table from JSON afterwards, and nothing read it.
#
# Confirmed by pose rather than by properties before this was written: at a frame
# reporting a clip time of 0.1465 s with a 0.2667 s offset set, the recorded body
# matched the source clip at 0.1465 (distance 0.002) and not at 0.4132 (8.66).

const TestWorld = preload("res://tests/world_fixture.gd")

var _late_world: Dictionary = {}

func after_each() -> void:
	if _late_world.is_empty():
		return
	TestWorld.teardown(_late_world)
	_late_world = {}

func test_a_trim_set_after_the_body_is_attached_still_reaches_the_graph() -> void:
	_late_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_late_world)
	await step(20)
	var player: Player = _late_world["player"]
	var root := Node3D.new()
	root.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	for name in [&"Idle", &"Sprint", &"SafetyVault"]:
		var animation := Animation.new()
		animation.length = float(FRAMES) / FPS
		animation.step = 1.0 / FPS
		library.add_animation(name, animation)
	anim_player.add_animation_library("", library)
	root.add_child(anim_player)
	anim_player.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	# ATTACHED FIRST, TRIMMED SECOND -- the order the lab works in.
	player._attach_body(packed)
	await step(2)
	player.body_clip_timings[&"SafetyVault"] = [float(FROM_FRAME) / FPS, 0.0]
	player.refresh_clip_timings()

	var tree: AnimationTree = null
	for child in player.get_node("BodyRoot").get_children():
		if child is AnimationTree:
			tree = child
	var states: AnimationNodeStateMachine = (tree.tree_root as AnimationNodeBlendTree) \
		.get_node(CharacterAnimator.GRAPH_STATES) as AnimationNodeStateMachine
	var node := states.get_node(&"SafetyVault") as AnimationNodeAnimation
	assert_true(node.use_custom_timeline, "the trim never left the dictionary")
	assert_almost_eq(node.start_offset, float(FROM_FRAME) / FPS, 0.001,
		"the graph is still starting this clip at frame 0")
	# AND REMOVING ONE TURNS IT BACK OFF, which nothing else would do: there is
	# no entry left in the table to drive it from.
	player.body_clip_timings.erase(&"SafetyVault")
	player.refresh_clip_timings()
	assert_false(node.use_custom_timeline, "a deleted trim stayed on the node")

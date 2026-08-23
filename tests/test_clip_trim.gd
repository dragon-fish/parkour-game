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
	# Player._apply_clip_timing(). This is not a hypothetical: it is what the
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
	player._apply_clip_timing(node, CLIP, anim_player)
	player.free()
	assert_true(node.use_custom_timeline, "the trim was not applied at all")
	assert_almost_eq(node.start_offset, float(FROM_FRAME) / FPS, 0.001,
		"the trim did not start where it was told to")
	assert_almost_eq(node.timeline_length, float(FRAMES - FROM_FRAME) / FPS, 0.001,
		"a length of 0 did not become 'the rest of the clip'")
	assert_false(node.stretch_time_scale,
		"the stretch is back, and with it the frozen tail")

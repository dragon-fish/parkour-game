extends ParkourTest

# The corrective arm splay has to reach the GAME, not only the showcase.
#
# ✅ THE OWNER: "之前调过角色idel和walk动画的手往身体外偏一点避免肩膀太窄导致的
# 穿模，感觉只在角色展台生效了，普通关卡里手臂还是贴死腰."
#
# BoneSplay decides whether to apply by asking whoever drives the skeleton
# which clip is playing, and there are two possible answers with different
# shapes: an AnimationTree reports a state machine node, an AnimationPlayer
# reports current_animation. In a level BOTH exist -- CharacterAnimator builds
# the tree at runtime and the imported model brings its own player, which the
# tree then uses as a clip LIBRARY. Ask the library and it says the empty
# string, because it is not the thing playing anything.
#
# That is the failure this file exists for, and it is completely silent: no
# error, no warning, just arms that sit against the hips in game and open
# correctly on the showcase, where there is no tree and the wrong answer
# happens to be the right one.
#
# Needs the private body: the splay lives in that wrapper.

const LEVEL := "res://scenes/main.tscn"

func _splay_in_a_level() -> Node:
	var level := (load(LEVEL) as PackedScene).instantiate()
	add_child_autofree(level)
	await step(60)
	for node in level.find_children("*", "SkeletonModifier3D", true, false):
		if node.name == "ArmSplay":
			return node
	return null

func test_the_splay_asks_the_animation_tree_and_not_its_clip_library() -> void:
	var splay: Node = await _splay_in_a_level()
	if splay == null:
		pass_test("no local body, so no ArmSplay to check")
		return
	# Read straight off the node: the whole bug was this one reference being
	# latched to the wrong object, and nothing else in the chain shows it.
	assert_true(splay._driver is AnimationTree,
		"the splay is asking a %s which clip is playing; in a level that is the " \
			% ("null" if splay._driver == null else splay._driver.get_class()) \
			+ "tree's clip library, and it always answers with the empty string")

func test_the_splay_actually_opens_the_arms_while_idling() -> void:
	# The end of the chain. A driver of the right type still proves nothing if
	# the clip names it reports do not match the list the correction is scoped
	# to, so this asserts the angle that came out rather than the wiring.
	var splay: Node = await _splay_in_a_level()
	if splay == null:
		pass_test("no local body, so no ArmSplay to check")
		return
	# WAITED FOR, not counted out. A player dropped in at spawn spends its first
	# second landing, so a fixed frame count is a bet on how long that takes --
	# the first version of this bet 60 frames and lost. Poll for the state the
	# correction is scoped to, then give the blend its own time on top.
	var playback: Variant = (splay._driver as AnimationTree).get(
		"parameters/%s/playback" % CharacterAnimator.GRAPH_STATES)
	assert_not_null(playback, "the state machine has no playback to read")
	var reached := false
	for i in 300:
		await step(1)
		if splay.clips.has(String(playback.get_current_node())):
			reached = true
			break
	assert_true(reached,
		"the player never settled into any of %s, so this proves nothing" % str(splay.clips))
	await step(int(splay.blend_time * 60.0) + 10)
	assert_gt(absf(splay._applied), 0.0,
		"the state is %s, which IS in %s, and still no splay came out" \
			% [String(playback.get_current_node()), str(splay.clips)])

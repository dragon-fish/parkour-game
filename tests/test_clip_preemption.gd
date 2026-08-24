extends ParkourTest

# A scripted move's clip starts the tick the move does, and still cross-fades
# out of whatever was playing.
#
# ✅ THE OWNER REPORTED THE SAME BUG FROM BOTH SIDES, and the two reports are
# why this is a gate rather than a policy:
#
#   waiting  "比如 Jump -> Climb -> IntoGrab -> Grab -> GrabPullUp 中间几个状态逻
#            辑帧里只存在了几帧，却抢占了 GrabPullUp 的动画时间." A travel() is a
#            REQUEST: the state machine finishes the transition it is in first.
#   cutting  "和前一个动作完全没有衔接过渡." start(target, true) does arrive at
#            once -- by throwing the whole cross-fade away.
#
# AnimationNodeStateMachinePlayback in 4.7 offers no third option (verified
# against the engine's own ClassDB; godotengine/godot#66495 is the standing
# request). So the scripted clips were moved OUT of the state machine and onto
# two bare slots behind an AnimationNodeTransition, which switches inputs at any
# moment WITH its xfade and interrupts its own fade gracefully.
#
# The five tests below are the invariants of that routing. See
# CharacterAnimator._route() for the take-frame table that measured the cost.

const TestWorld = preload("res://tests/world_fixture.gd")

const A_SCRIPTED_CLIP := &"SafetyVault"
const ANOTHER_SCRIPTED_CLIP := &"StepUp"
const AN_ORDINARY_CLIP := &"Sprint"
const ANOTHER_ORDINARY_CLIP := &"Jump_Start"

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## An animator over a synthetic body carrying `clips`, with its own per-tick
## drive SWITCHED OFF so that every routing decision in these tests is one this
## file made. Left on, the animator would route to the idle clip between the
## lines and answer a question nobody asked.
##
## Synthetic rather than the real model, for the reason every other animation
## suite here is: that model is CC BY-NC-SA and deliberately untracked.
func _animator_with(clips: Array, timings: Dictionary = {}) -> CharacterAnimator:
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
	for clip in clips:
		var animation := Animation.new()
		animation.length = 2.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player.body_clip_timings = timings
	player._wire_body_animation(body)
	var animator: CharacterAnimator = \
		player.get_node("BodyRoot").get_node("CharacterAnimator")
	animator.set_physics_process(false)
	return animator

## What the gate has been ASKED to show this tick. Read rather than
## `current_state`, which only catches up once the tree has processed -- and
## "the tick it is asked for" is precisely the thing under test.
func _requested(animator: CharacterAnimator) -> String:
	return str(animator.anim_tree.get(
		"parameters/%s/transition_request" % CharacterAnimator.GRAPH_GATE))

## What the gate is actually showing, once it has processed a request.
func _showing(animator: CharacterAnimator) -> String:
	return str(animator.anim_tree.get(
		"parameters/%s/current_state" % CharacterAnimator.GRAPH_GATE))

func _slot(animator: CharacterAnimator, slot: StringName) -> AnimationNodeAnimation:
	var root := animator.anim_tree.tree_root as AnimationNodeBlendTree
	return root.get_node(slot) as AnimationNodeAnimation

func _states(animator: CharacterAnimator) -> AnimationNodeStateMachine:
	var root := animator.anim_tree.tree_root as AnimationNodeBlendTree
	return root.get_node(CharacterAnimator.GRAPH_STATES) as AnimationNodeStateMachine

func test_a_scripted_clip_claims_a_slot_on_the_tick_it_is_asked_for() -> void:
	# THE WHOLE POINT. Measured, a travel() into a scripted clip issued while the
	# graph was mid-blend arrived ELEVEN ticks later -- a short StepUp lost ten
	# of its twenty-seven frames.
	var animator: CharacterAnimator = await _animator_with(
		[&"Idle", AN_ORDINARY_CLIP, ANOTHER_ORDINARY_CLIP, A_SCRIPTED_CLIP])
	animator._route(AN_ORDINARY_CLIP)
	await step(2)
	animator._route(ANOTHER_ORDINARY_CLIP)
	await step(2)
	# The state machine is now genuinely mid-transition, which is the condition
	# that used to cost the scripted clip its opening frames. Asserted, not
	# assumed: without it the rest of this test proves nothing.
	assert_ne(String(animator._playback.get_fading_from_node()), "",
		"the state machine settled before the scripted clip was asked for")

	animator._route(A_SCRIPTED_CLIP)
	assert_eq(_requested(animator), String(CharacterAnimator.GRAPH_SCRIPTED_A),
		"the scripted clip did not claim a slot on its own tick")
	assert_eq(String(_slot(animator, CharacterAnimator.GRAPH_SCRIPTED_A).animation),
		String(A_SCRIPTED_CLIP), "the slot it claimed is not carrying the clip")
	await step(1)
	assert_eq(_showing(animator), String(CharacterAnimator.GRAPH_SCRIPTED_A),
		"the gate never arrived at the slot")

func test_two_scripted_clips_in_a_row_use_different_slots() -> void:
	# A MANTLE CHAIN is two scripted clips back to back. One slot would have to
	# cut from the first to the second; two ping-pong, so the second fades out of
	# the first exactly as it fades out of a run.
	var animator: CharacterAnimator = await _animator_with(
		[&"Idle", A_SCRIPTED_CLIP, ANOTHER_SCRIPTED_CLIP])
	animator._route(A_SCRIPTED_CLIP)
	assert_eq(_requested(animator), String(CharacterAnimator.GRAPH_SCRIPTED_A),
		"the first scripted clip did not take the first slot")
	animator._route(ANOTHER_SCRIPTED_CLIP)
	assert_eq(_requested(animator), String(CharacterAnimator.GRAPH_SCRIPTED_B),
		"the second scripted clip landed on the slot the first is still fading out of")
	assert_eq(String(_slot(animator, CharacterAnimator.GRAPH_SCRIPTED_A).animation),
		String(A_SCRIPTED_CLIP), "the outgoing slot was overwritten mid-fade")
	assert_eq(String(_slot(animator, CharacterAnimator.GRAPH_SCRIPTED_B).animation),
		String(ANOTHER_SCRIPTED_CLIP), "the incoming slot is not carrying the clip")

func test_holding_a_scripted_clip_does_not_restart_it() -> void:
	# The drive runs every tick, so "route to what is already showing" is the
	# common case and must be a no-op. Re-requesting the slot would re-enter it,
	# and the slots reset on entry -- sixty restarts a second.
	var animator: CharacterAnimator = await _animator_with([&"Idle", A_SCRIPTED_CLIP])
	animator._route(A_SCRIPTED_CLIP)
	await step(2)
	animator._route(A_SCRIPTED_CLIP)
	assert_eq(_requested(animator), "",
		"the clip already on screen was asked for again")

func test_an_ordinary_clip_hands_the_gate_back_to_the_state_machine() -> void:
	var animator: CharacterAnimator = await _animator_with(
		[&"Idle", AN_ORDINARY_CLIP, A_SCRIPTED_CLIP])
	animator._route(A_SCRIPTED_CLIP)
	await step(2)
	animator._route(AN_ORDINARY_CLIP)
	assert_eq(_requested(animator), String(CharacterAnimator.GRAPH_STATES),
		"an ordinary clip left the gate on a scripted slot")
	# AND THE MACHINE UNDERNEATH WAS TRAVELLED, which is the half that would be
	# easy to lose: the gate can be pointed at a state machine that is still
	# sitting on whatever it last played.
	await step(20)
	assert_eq(String(animator._playback.get_current_node()), String(AN_ORDINARY_CLIP),
		"the state machine was never asked to travel anywhere")

func test_a_fallback_clip_is_not_treated_as_scripted() -> void:
	# A body without the paid pack plays Jump_Start where the model plays
	# StepUp. The routing asks what the CHOSEN CLIP is, not which move chose it,
	# so the fallback goes through the state machine like any other clip -- and
	# the slots are never touched at all.
	var animator: CharacterAnimator = await _animator_with(
		[&"Idle", ANOTHER_ORDINARY_CLIP])
	assert_false(Player.SCRIPTED_MOVE_CLIPS.has(ANOTHER_ORDINARY_CLIP),
		"this test needs a clip no scripted move plays")
	animator._route(ANOTHER_ORDINARY_CLIP)
	assert_eq(_requested(animator), String(CharacterAnimator.GRAPH_STATES),
		"a fallback clip claimed a scripted slot")
	for slot in CharacterAnimator.GRAPH_SCRIPTED_SLOTS:
		assert_eq(String(_slot(animator, slot).animation), "",
			"slot %s was loaded for a clip that is not scripted" % slot)

func test_a_slot_carries_the_same_trim_as_the_state_machines_own_node() -> void:
	# The trim is the whole reason the vault reads at all -- it skips the
	# authored run-up. A slot that ignored it would play the clip this project
	# does not use, and only for the scripted moves, which are exactly the
	# trimmed ones.
	var animator: CharacterAnimator = await _animator_with(
		[&"Idle", A_SCRIPTED_CLIP], {A_SCRIPTED_CLIP: [0.8, 0.9]})
	animator._route(A_SCRIPTED_CLIP)
	var slot := _slot(animator, CharacterAnimator.GRAPH_SCRIPTED_A)
	var node := _states(animator).get_node(A_SCRIPTED_CLIP) as AnimationNodeAnimation
	assert_true(node.use_custom_timeline, "this test needs a trimmed clip to compare against")
	for property in ["use_custom_timeline", "start_offset", "timeline_length",
			"stretch_time_scale"]:
		assert_eq(slot.get(property), node.get(property),
			"the slot's %s does not match the state machine's node" % property)

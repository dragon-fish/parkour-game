extends ParkourTest

# A clip a scripted move plays may cut in front of a transition into one that
# nothing scripted plays.
#
# THE OWNER worked out the shape of it: "比如 Jump -> Climb -> IntoGrab -> Grab ->
# GrabPullUp 中间几个状态逻辑帧里只存在了几帧，却抢占了 GrabPullUp 的动画时间."
#
# Measured on a 1 m obstacle, take frames from one recording. The move asks for
# StepUp on frame 79 either way:
#
#     without   the graph arrives on frame 89   -- 10 of the move's 29 frames
#     with      the graph arrives on frame 80   -- 1
#
# Those ten frames were a Jump_Start blending in, for a Jump state that was the
# current move for exactly one tick.

const A_SCRIPTED_CLIP := &"StepUp"
const ANOTHER_SCRIPTED_CLIP := &"ClimbUp_2m"
const AN_ORDINARY_CLIP := &"Jump_Start"

func test_a_scripted_clip_cuts_in_front_of_an_ordinary_one() -> void:
	assert_true(CharacterAnimator.preempts(A_SCRIPTED_CLIP, AN_ORDINARY_CLIP, &"Sprint"),
		"the vault still queues behind a jump start it no longer wants")

func test_nothing_is_pre_empted_when_the_graph_is_settled() -> void:
	# travel() is honoured immediately when no transition is in flight, so
	# start()ing would throw away a cross-fade and buy nothing.
	assert_false(CharacterAnimator.preempts(A_SCRIPTED_CLIP, AN_ORDINARY_CLIP, &""),
		"a settled graph was interrupted for no reason")

func test_an_ordinary_clip_may_not_cut_in_front_of_a_scripted_one() -> void:
	# ONE DIRECTION ONLY. Anything symmetric starts discarding the cross-fades
	# that are doing real work.
	assert_false(CharacterAnimator.preempts(AN_ORDINARY_CLIP, A_SCRIPTED_CLIP, &"Sprint"),
		"a jump start cut in front of a vault")

func test_two_scripted_clips_queue_normally() -> void:
	# The hang into the pull-up is this case, and it is a real transition
	# between two poses the body genuinely strikes -- worth its blend.
	assert_false(CharacterAnimator.preempts(ANOTHER_SCRIPTED_CLIP, &"Climb_Idle", &"Sprint"),
		"the hang was cut off rather than blended out of")

func test_arriving_at_what_is_already_playing_changes_nothing() -> void:
	assert_false(CharacterAnimator.preempts(A_SCRIPTED_CLIP, A_SCRIPTED_CLIP, &"Sprint"),
		"a clip restarted itself mid-blend")

extends ParkourTest

# The packs ship three-part actions where this project has one state:
# Slide_Start / Slide / Slide_Exit, and a Jump_Land that is the absorb after a
# fall. Neither end of either is a Move -- neither costs the player any time --
# so CharacterAnimator plays them as ONE-SHOTS armed at the transition.
#
# Tested because both failure modes read as defects rather than as taste. A
# one-shot that never fires is an end that silently went missing; a one-shot
# that never ends is a body frozen mid-clip while the player runs around.

const TestWorld = preload("res://tests/world_fixture.gd")

## Every clip the cases below reach for. Length 1.0 each, set by the fixture.
const CLIPS: Array = [
	&"Idle", &"Walk", &"Sprint", &"Slide", &"Slide_Start", &"Slide_Exit",
	&"Jump", &"Jump_Start", &"Jump_Land",
]

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## Synthetic body, so this never depends on the untracked model.
func _animator() -> CharacterAnimator:
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
	for clip in CLIPS:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(clip, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player._wire_body_animation(body)
	return player.get_node("BodyRoot").get_node("CharacterAnimator")

## Whatever the player is asking for this tick. Zero is "nothing held".
func _hold(animator: CharacterAnimator, strafe: float, forward: float) -> void:
	var input := MoveInput.new()
	input.move = Vector2(strafe, forward)
	animator.player.last_input = input

# --- the slide's two ends -----------------------------------------------------

func test_entering_a_slide_plays_the_push_off() -> void:
	var animator: CharacterAnimator = await _animator()
	animator._arm_oneshot(Move.WALKING, Move.SLIDE)
	assert_eq(animator._oneshot_target(0.0), StringName(&"Slide_Start"), "a slide began at full speed with no push-off")

func test_leaving_a_slide_plays_the_stand_up() -> void:
	var animator: CharacterAnimator = await _animator()
	animator._arm_oneshot(Move.SLIDE, Move.WALKING)
	assert_eq(animator._oneshot_target(0.0), StringName(&"Slide_Exit"), "a slide ended with the body simply upright again")

func test_a_slide_into_a_crouch_does_not_stand_up() -> void:
	# ✅ The owner settled this for the blend times already: a slide into a
	# crouch is continuous -- the body stays down -- while a slide into a run is
	# the picking-yourself-up. Slide_Exit is a stand-up, so it belongs only to
	# the second.
	var animator: CharacterAnimator = await _animator()
	animator._arm_oneshot(Move.SLIDE, Move.CROUCH)
	assert_eq(animator._oneshot_target(0.0), Move.KEEP, "a slide into a crouch stood the body up and put it straight back down")

# --- the landing --------------------------------------------------------------

func test_landing_with_nothing_held_plays_the_absorb() -> void:
	var animator: CharacterAnimator = await _animator()
	_hold(animator, 0.0, 0.0)
	animator._arm_oneshot(Move.FALLING, Move.WALKING)
	assert_eq(animator._oneshot_target(0.0), StringName(&"Jump_Land"), "a fall ended standing, with no absorb at all")

func test_landing_with_a_direction_held_goes_straight_to_the_run() -> void:
	# The owner's call: holding a direction through a landing is the player
	# saying they are still moving, and a stand-up in the middle of that would
	# be the animation contradicting them.
	var animator: CharacterAnimator = await _animator()
	_hold(animator, 0.0, 1.0)
	animator._arm_oneshot(Move.FALLING, Move.WALKING)
	assert_eq(animator._oneshot_target(0.0), Move.KEEP, "a landing run-out played the absorb instead of running")

func test_the_absorb_is_cut_short_the_moment_a_direction_is_asked_for() -> void:
	# A fraction of a second of ignored input is the one thing this project will
	# not spend on presentation.
	var animator: CharacterAnimator = await _animator()
	_hold(animator, 0.0, 0.0)
	animator._arm_oneshot(Move.FALLING, Move.WALKING)
	assert_eq(animator._oneshot_target(0.1), StringName(&"Jump_Land"), "the absorb did not start")
	_hold(animator, 0.0, 1.0)
	assert_eq(animator._oneshot_target(0.1), Move.KEEP, "the absorb held the body still while the player asked to move")

# --- a one-shot is SHORT ------------------------------------------------------

func test_a_one_shot_ends_on_its_own_clip_length() -> void:
	# The window is READ off the clip, not configured, so it can never drift
	# from the thing it is a window for. The fixture's clips are 1.0 s.
	var animator: CharacterAnimator = await _animator()
	animator._arm_oneshot(Move.WALKING, Move.SLIDE)
	assert_eq(animator._oneshot_target(0.9), StringName(&"Slide_Start"), "the one-shot ended before its clip did")
	assert_eq(animator._oneshot_target(0.2), Move.KEEP, "the one-shot outlived its clip, freezing the body mid-slide")

func test_a_second_transition_cuts_a_one_shot_off() -> void:
	# Otherwise a stand-up outlives the moment it belongs to and plays over
	# whatever the player did next.
	var animator: CharacterAnimator = await _animator()
	animator._arm_oneshot(Move.SLIDE, Move.WALKING)
	assert_eq(animator._oneshot_target(0.1), StringName(&"Slide_Exit"), "the stand-up did not start")
	animator._arm_oneshot(Move.WALKING, Move.JUMP)
	assert_eq(animator._oneshot_target(0.0), Move.KEEP, "the stand-up carried on through a jump")

func test_a_body_without_the_clip_arms_nothing() -> void:
	# Every routing decision in this class is guarded against a body that lacks
	# the clip -- travel()ing to a name with no node is a real engine error, not
	# a graceful no-op -- and the one-shots are no exception. The fox has none
	# of these.
	var animator: CharacterAnimator = await _animator()
	animator._graph.remove_node("Slide_Start")
	animator._arm_oneshot(Move.WALKING, Move.SLIDE)
	assert_eq(animator._oneshot_target(0.0), Move.KEEP, "a one-shot was armed for a clip the body does not have")

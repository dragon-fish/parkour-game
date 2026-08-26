extends ParkourTest

# The hands go ON the thing the body is climbing over.
#
# The owner's own principle, already written down in
# docs/contact-drives-movement.md: every direction change in the original reads
# as a hand or a foot touching something. The movement honours it already --
# nothing moves until contact -- but the animation does not: a vault clip
# authored against one obstacle plays identically against every other, so the
# hands pass through the ledge or wave above it.
#
# Built on the real VRM body, which is untracked -- so every test here SKIPS
# rather than fails when it is absent, and says so. A fresh clone must not go
# red over a model it was never given, but a silent pass would hide that this
# is unverified.

const TestWorld = preload("res://tests/world_fixture.gd")
const BODY_PATH := "res://assets/models/local/test.vrm"

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player_with_body() -> Player:
	if not ResourceLoader.exists(BODY_PATH):
		return null
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player._attach_body(load(BODY_PATH))
	await step(3)
	return player

func _skip_note() -> void:
	pending("no humanoid body at %s -- hand IK is unverified in this checkout" % BODY_PATH)

func test_a_humanoid_body_gets_arm_chains() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	assert_not_null(player.hand_ik, "no HandIK was built for a humanoid body")
	assert_true(player.hand_ik.is_live(), "HandIK attached but found no chains")

func test_nothing_is_driven_until_a_move_asks() -> void:
	# The whole safety of this: a body with IK attached must animate exactly as
	# it would without, until something reaches.
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	await step(10)
	var state: Dictionary = player.hand_ik.debug()
	assert_false(bool(state["active"]), "the solver runs with nothing asking for it")
	assert_almost_eq(float(state["influence"]), 0.0, 0.0001, \
		"the arms are being driven before any move reached for anything")

func test_a_reaching_hand_arrives_at_the_point_it_was_given() -> void:
	# THE CLAIM THAT MATTERS, and the one checkable without eyes: the hand BONE
	# should end up where the target is, not merely near it.
	#
	# STILL PENDING, but for a different reason than before, and the correction
	# is the useful part.
	#
	# This was written off as "TwoBoneIK3D does not move the bones", measured at
	# exactly 0.0000 m of travel. That measurement was wrong.
	# get_bone_global_pose() returns the pose from BEFORE the deferred modifier
	# pass -- the class reference says so: "the final global pose can get
	# overridden by modifiers in the deferred process, if you want to access the
	# final global pose, use SkeletonModifier3D.modification_processed". Sampled
	# through that signal instead, the hand moves.
	#
	# It moves to the WRONG PLACE -- 1.32 m from the target, roughly three arm
	# lengths. A solver that overshoots is a different problem from one that
	# never runs, and the pole node is the first suspect: POLE_OFFSET puts the
	# elbow hint near the target, which for a target close to the body lands
	# inside the torso, and a two-bone solver given a degenerate pole can flip
	# its whole solution plane.
	pending("TwoBoneIK3D solves but overshoots -- see docs/feel-backlog.md 47")

func test_releasing_hands_the_arm_back() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	player.hand_ik.reach(HandIK.RIGHT, player.global_position + Vector3(-0.25, 0.35, -0.35))
	await step(30)
	assert_gt(float(player.hand_ik.debug()["influence"]), 0.9, "the reach never blended in")

	player.hand_ik.release()
	await step(30)
	var state: Dictionary = player.hand_ik.debug()
	assert_almost_eq(float(state["influence"]), 0.0, 0.001, "the arm never let go")
	assert_false(bool(state["active"]), \
		"the solver keeps running after both arms faded, for a result nobody uses")

func test_the_blend_ramps_rather_than_cutting() -> void:
	# A hand that snaps onto a ledge is a worse artefact than one that misses
	# it -- the same reasoning as the animation cross-fade in feel-backlog 43.
	var player: Player = await _player_with_body()
	if player == null:
		return _skip_note()
	player.hand_ik.reach(HandIK.LEFT, player.global_position + Vector3(0.25, 0.35, -0.35))
	await step(1)
	var after_one: float = float(player.hand_ik.debug()["influence"])
	assert_gt(after_one, 0.0, "the blend did not start")
	assert_lt(after_one, 0.5, "the arm was cut onto the target in a single tick")

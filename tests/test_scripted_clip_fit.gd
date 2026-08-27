extends ParkourTest

# A scripted move fits its CLIP to its own clock.
#
# THE CLIP MUST BE TIME-FITTED TO THE MOVE'S OWN DURATION, not played at its
# authored length -- otherwise the apparent playback speed doubles or halves
# depending on which side of the mismatch the move falls on. SafetyVault is
# 0.733 s; a vault_over runs for its variant's 0.650 s at walking pace, and
# SpeedVaultMove floors a fast approach at HALF that -- 0.325 s -- so under
# half the clip was ever seen before the move handed off when unfitted. The
# mantle is worse in the other direction: ClimbUp_2m is 1.300 s.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A player whose body carries `clip` at `length` seconds, with the animator
## reachable.
func _animator_with(clip: StringName, length: float) -> CharacterAnimator:
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
	for name in [clip, &"Idle", &"Sprint"]:
		var animation := Animation.new()
		animation.length = length if name == clip else 1.0
		library.add_animation(name, animation)
	anim_player.add_animation_library("", library)
	body.add_child(anim_player)
	player.get_node("BodyRoot").add_child(body)
	player._wire_body_animation(body)
	return player.get_node("BodyRoot").get_node("CharacterAnimator")

func test_a_clip_is_stretched_to_end_when_the_move_does() -> void:
	# The reported case: a 0.733 s clip in a 0.325 s window has to run at 2.26x
	# to finish with the move, and finishing with the move is the only cadence
	# that can look right when the body is on a path the move owns.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as ScriptedMove
	move.begin(player.global_position, player.global_position + Vector3(0.0, 0.0, -1.0), 0.325)
	player.move_manager.start(Move.SPEED_VAULT)
	assert_almost_eq(animator._scripted_fit(&"SafetyVault"), 0.733 / 0.325, 0.01,
		"the clip was fitted at %.2f" % animator._scripted_fit(&"SafetyVault"))

func test_a_long_clip_in_a_short_window_slows_down_instead() -> void:
	# ClimbUp_2m is 1.300 s. The fit works in both directions or it is not a
	# fit.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.4)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as ScriptedMove
	move.begin(player.global_position, player.global_position + Vector3(0.0, 0.0, -1.0), 0.8)
	player.move_manager.start(Move.SPEED_VAULT)
	assert_almost_eq(animator._scripted_fit(&"SafetyVault"), 0.5, 0.01,
		"the clip was fitted at %.2f" % animator._scripted_fit(&"SafetyVault"))

func test_an_unscripted_move_is_not_fitted_at_all() -> void:
	# Walking is not on a clock anyone owns, and its clips are speed-matched
	# instead. A fit here would fight that.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	assert_almost_eq(animator._scripted_fit(&"Sprint"), 0.0, 0.0001,
		"an ordinary walk was fitted to something")

func test_a_scripted_move_that_has_not_begun_is_not_fitted() -> void:
	# scripted_duration() is zero before begin() and once the travel is spent,
	# so the fit cannot divide by it.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	player.move_manager.start(Move.SPEED_VAULT)
	assert_almost_eq(animator._scripted_fit(&"SafetyVault"), 0.0, 0.0001,
		"a move with no travel set was fitted anyway")

# --- and it actually reaches the graph -----------------------------------------------

func test_the_fit_is_written_onto_the_animation_tree() -> void:
	# THE TESTS ABOVE ONLY COVER THE ARITHMETIC. Cutting the branch that
	# APPLIES it leaves every one of them green -- a number computed correctly
	# and never used is exactly the bug this file exists to close. This one
	# reads the graph.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as ScriptedMove
	move.begin(player.global_position, player.global_position + Vector3(0.0, 0.0, -1.0), 0.325)
	player.move_manager.start(Move.SPEED_VAULT)
	# The animator drives the graph on its own physics tick.
	animator._drive_speed(&"SafetyVault")
	var scale: float = animator.anim_tree.get(
		"parameters/%s/scale" % CharacterAnimator.GRAPH_TIME_SCALE)
	assert_almost_eq(scale, 0.733 / 0.325, 0.01,
		"the graph is running at %.2f, not the fitted rate" % scale)

func test_an_ordinary_clip_still_gets_its_speed_match() -> void:
	# The pair: the fit takes priority over speed matching, so it must not have
	# swallowed it. A body at rest scales its run clip to the floor.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	animator._drive_speed(&"Sprint")
	var scale: float = animator.anim_tree.get(
		"parameters/%s/scale" % CharacterAnimator.GRAPH_TIME_SCALE)
	assert_almost_eq(scale, CharacterAnimator.SPEED_SCALE_MIN, 0.01,
		"a standing body ran its sprint clip at %.2f" % scale)

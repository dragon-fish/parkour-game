extends ParkourTest

# A move on its own clock fits its CLIP to it.
#
# THE CLIP MUST BE TIME-FITTED TO THE MOVE'S OWN DURATION, not played at its
# authored length -- otherwise the apparent playback speed doubles or halves
# depending on which side of the mismatch the move falls on. SafetyVault is
# 0.733 s; the original's vaultOver row takes 0.65 s.

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
	# A 0.733 s clip in a 0.65 s vault has to run at 1.13x to finish with the
	# move, and finishing with the move is the only cadence
	# that can look right when the body is on a path the move owns.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as SpeedVaultMove
	# Row 3, vaultOver: its legs take 0 + 0.35 + 0.3 = 0.65 s.
	move.active_vault_type = 3
	player.move_manager.start(Move.SPEED_VAULT)
	assert_almost_eq(animator._scripted_fit(&"SafetyVault"), 0.733 / 0.65, 0.01,
		"the clip was fitted at %.2f" % animator._scripted_fit(&"SafetyVault"))

func test_a_long_clip_in_a_short_window_slows_down_instead() -> void:
	# The fit works in both directions or it is not a fit.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.4)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as SpeedVaultMove
	# Row 3, vaultOver: its legs take 0 + 0.35 + 0.3 = 0.65 s.
	move.active_vault_type = 3
	player.move_manager.start(Move.SPEED_VAULT)
	assert_almost_eq(animator._scripted_fit(&"SafetyVault"), 0.4 / 0.65, 0.01,
		"the clip was fitted at %.2f" % animator._scripted_fit(&"SafetyVault"))

func test_an_unscripted_move_is_not_fitted_at_all() -> void:
	# Walking is not on a clock anyone owns, and its clips are speed-matched
	# instead. A fit here would fight that.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	player.move_manager.start(Move.WALKING)
	assert_almost_eq(animator._scripted_fit(&"Sprint"), 0.0, 0.0001,
		"an ordinary walk was fitted to something")

func test_a_vault_with_no_row_has_no_duration() -> void:
	# scripted_duration() is zero with no row planned, so the fit cannot divide
	# by it.
	await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as SpeedVaultMove
	assert_almost_eq(move.scripted_duration(), 0.0, 0.0001, "a vault with no row has a duration")

# --- and it actually reaches the graph -----------------------------------------------

func test_the_fit_is_written_onto_the_animation_tree() -> void:
	# THE TESTS ABOVE ONLY COVER THE ARITHMETIC. Cutting the branch that
	# APPLIES it leaves every one of them green -- a number computed correctly
	# and never used is exactly the bug this file exists to close. This one
	# reads the graph.
	var animator: CharacterAnimator = await _animator_with(&"SafetyVault", 0.733)
	var player: Player = _world["player"]
	var move := player.move_manager.move_for(Move.SPEED_VAULT) as SpeedVaultMove
	# Row 3, vaultOver: its legs take 0 + 0.35 + 0.3 = 0.65 s.
	move.active_vault_type = 3
	player.move_manager.start(Move.SPEED_VAULT)
	# The animator drives the graph on its own physics tick.
	animator._drive_speed(&"SafetyVault")
	var scale: float = animator.anim_tree.get(
		"parameters/%s/scale" % CharacterAnimator.GRAPH_TIME_SCALE)
	assert_almost_eq(scale, 0.733 / 0.65, 0.01,
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

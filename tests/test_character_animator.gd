extends TestCase

# Drives the REAL Player through CharacterAnimator's three cases and checks
# where the AnimationTree's own state machine actually landed -- through the
# real node wiring (Player -> CharacterAnimator -> AnimationTree.travel()),
# not by calling _target_animation() directly. A broken NodePath, a tree
# left inactive, or a transition graph that still races itself to "End" (see
# tools/build_player_scene.gd's own note on why advance_mode must not be
# AUTO) would all fail this test exactly as they would fail the running
# game; calling the mapping function directly would have caught none of
# them.

func _spawn() -> Dictionary:
	var cfg := MovementConfig.new()
	# A stub body, not the owner's real (untracked, CC BY-NC-SA) model -- see
	# JOB 1's report. TestWorld.build_stub_body(with_animation_player=true)
	# gives Player._wire_body_animation() a real "AnimationPlayer" child with
	# idle/jump/run clips to wire the SAME AnimationTree/CharacterAnimator
	# graph against, so these tests still exercise the real node wiring
	# (Player -> CharacterAnimator -> AnimationTree.travel()) end to end,
	# just without needing the licensed asset to exist on whatever machine
	# runs this suite.
	var world := TestWorld.build(tree, cfg, TestWorld.build_stub_body("", Vector3.ZERO, true))
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world

func _current_clip(player: Player) -> StringName:
	var anim_tree := player.get_node("BodyRoot/AnimationTree") as AnimationTree
	var playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/playback")
	return playback.get_current_node()

func test_standing_still_plays_idle() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	check(player.state_machine.current_name == PlayerState.GROUND, \
		"precondition: player should have settled into Ground, got %s" % player.state_machine.current_name)
	check(player.horizontal_speed() < player.config.run_animation_speed_threshold, \
		"precondition: a freshly settled player should be at rest")

	# A few ticks for CharacterAnimator's travel() request to actually apply.
	await step(5)
	check(_current_clip(player) == &"idle", \
		"standing still did not select idle, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

func test_running_above_the_threshold_plays_run() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true
	await step(30)
	check(player.state_machine.current_name == PlayerState.GROUND, \
		"precondition: sprinting on flat ground should stay in Ground, got %s" % player.state_machine.current_name)
	check_greater(player.horizontal_speed(), player.config.run_animation_speed_threshold, \
		"precondition: the player should be moving above the run threshold")

	await step(5)
	check(_current_clip(player) == &"run", \
		"moving above the threshold did not select run, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

func test_airborne_plays_jump() -> void:
	var world := await _spawn()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.press_jump()
	await step(2)
	check(player.state_machine.current_name == PlayerState.AIR, \
		"precondition: pressing jump should leave the player airborne, got %s" % player.state_machine.current_name)

	await step(5)
	check(_current_clip(player) == &"jump", \
		"being airborne did not select jump, playing %s" % _current_clip(player))

	TestWorld.teardown(world)
	await step(1)

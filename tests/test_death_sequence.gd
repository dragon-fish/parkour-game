extends ParkourTest

# Death is NOT a Move (spec §1): PlayerDying appears once in the whole CDO
# library, on FallingUncontrolled itself, and no Move succeeds it on landing.
# The sequence therefore belongs to the level, and this test pins that
# ownership -- if it ever needs a Move to run, the design drifted.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_sequence_reports_its_own_duration() -> void:
	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	assert_gt(seq.total_duration(), 1.0, "the death sequence is too short to read")
	assert_gt(3.0, seq.total_duration(), "the death sequence outstays its welcome")
	seq.queue_free()
	await step(1)

func test_it_finishes_and_says_so() -> void:
	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	var done := {"hit": false}
	seq.finished.connect(func() -> void: done["hit"] = true)
	seq.play(null)
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 20
	for i in ticks:
		await step(1)
		if done["hit"]:
			break
	assert_true(done["hit"], "the death sequence never finished")
	seq.queue_free()
	await step(1)

func test_it_locks_player_input_while_it_plays() -> void:
	# Regression: FallUncontrolledMove flips the Move layer back to WALKING
	# the instant it lands (see fix A1/A2's own header), and the cutscene
	# only ever touches the camera. Without a gate on the player itself,
	# WalkingMove would keep reading held input and drive the body around
	# underneath a "the character already collapsed" shot.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	assert_true(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: never settled onto the floor")

	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	seq.play(player)

	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)  # held forward, never released

	var start_position: Vector3 = player.global_position
	var done := {"hit": false}
	seq.finished.connect(func() -> void: done["hit"] = true)
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 20
	for i in ticks:
		await step(1)
		if done["hit"]:
			break
	assert_true(done["hit"], "the death sequence never finished")
	assert_almost_eq(player.global_position.x, start_position.x, 0.01, \
		"held input moved the player while the death sequence was playing")
	assert_almost_eq(player.global_position.z, start_position.z, 0.01, \
		"held input moved the player while the death sequence was playing")

	# Same held input, several ticks after the sequence let go: input must be
	# usable again, or the lock leaked past the cutscene it was meant to cover.
	await step(15)
	assert_true(not is_equal_approx(player.global_position.z, start_position.z), \
		"input stayed locked after the death sequence finished")

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_a_manual_reset_mid_cutscene_does_not_leave_input_locked() -> void:
	# Arena's R key calls reset_player() directly, bypassing DeathSequence --
	# so the unlock at the end of the cutscene never reaches a body that has
	# already respawned. CameraRig.reset_state() has always covered this case
	# (it calls end_cinematic()); this pins the player's half of it.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	seq.play(player)
	await step(5)

	# The reset happens here, well before the cutscene's timer runs out.
	player.reset_state()

	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	var start_position: Vector3 = player.global_position
	await step(15)
	assert_true(not is_equal_approx(player.global_position.z, start_position.z), \
		"a manual reset during the cutscene left the player unable to move")

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_stopping_a_sequence_cancels_it_instead_of_finishing_it() -> void:
	# C REGRESSION. Arena's R key respawns directly and nothing used to tell
	# the sequence about it, so it kept running and fired `finished` at
	# total_duration() -- which Arena wires straight to reset_player(). Press R
	# 0.3 s into the collapse and ~1.1 s later the player was teleported back
	# to spawn, velocity zeroed, move manager restarted, in the middle of a
	# life they had already begun. The screen stayed grey for that whole window
	# too, because set_desaturation(0.0) also only ran at total_duration().
	#
	# `finished` must NOT fire on a stop(): it means "the collapse played out",
	# and the one listener in the game respawns on it.
	#
	# Verified to go red by making stop() leave _playing set -- `finished` then
	# fires on schedule and the last check below catches it.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	var done := {"hit": false}
	seq.finished.connect(func() -> void: done["hit"] = true)
	seq.play(player)
	await step(5)
	assert_almost_eq(player.screen_effects.desaturation, 1.0, 0.0001, \
		"test setup is wrong: the cutscene did not desaturate the screen")

	seq.stop()
	assert_almost_eq(player.screen_effects.desaturation, 0.0, 0.0001, \
		"a cancelled cutscene left the screen desaturated")

	# The input gate is checked the way this file already checks it: by driving
	# the body with held input, since Player exposes no reader for it.
	var input: ScriptedInputSource = world["input"]
	input.state.move = Vector2(0.0, 1.0)
	var start_position: Vector3 = player.global_position
	await step(15)
	assert_true(not is_equal_approx(player.global_position.z, start_position.z), \
		"a cancelled cutscene left the player unable to move")

	# Well past the point the sequence would have completed on its own.
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 30
	for i in ticks:
		await step(1)
	assert_true(not done["hit"], \
		"a cancelled cutscene still reported itself finished, which respawns the player")

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

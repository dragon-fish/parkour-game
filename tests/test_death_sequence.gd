class_name TestDeathSequence
extends TestCase

# Death is NOT a Move (spec §1): PlayerDying appears once in the whole CDO
# library, on FallingUncontrolled itself, and no Move succeeds it on landing.
# The sequence therefore belongs to the level, and this test pins that
# ownership -- if it ever needs a Move to run, the design drifted.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_sequence_reports_its_own_duration() -> void:
	var seq := DeathSequence.new()
	tree.root.add_child(seq)
	await step(1)
	check_greater(seq.total_duration(), 1.0, "the death sequence is too short to read")
	check_greater(3.0, seq.total_duration(), "the death sequence outstays its welcome")
	seq.queue_free()
	await step(1)

func test_it_finishes_and_says_so() -> void:
	var seq := DeathSequence.new()
	tree.root.add_child(seq)
	await step(1)
	var done := {"hit": false}
	seq.finished.connect(func() -> void: done["hit"] = true)
	seq.play(null)
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 20
	for i in ticks:
		await step(1)
		if done["hit"]:
			break
	check(done["hit"], "the death sequence never finished")
	seq.queue_free()
	await step(1)

func test_it_locks_player_input_while_it_plays() -> void:
	# Regression: FallUncontrolledMove flips the Move layer back to WALKING
	# the instant it lands (see fix A1/A2's own header), and the cutscene
	# only ever touches the camera. Without a gate on the player itself,
	# WalkingMove would keep reading held input and drive the body around
	# underneath a "the character already collapsed" shot.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	check(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: never settled onto the floor")

	var seq := DeathSequence.new()
	tree.root.add_child(seq)
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
	check(done["hit"], "the death sequence never finished")
	check_approx(player.global_position.x, start_position.x, 0.01, \
		"held input moved the player while the death sequence was playing")
	check_approx(player.global_position.z, start_position.z, 0.01, \
		"held input moved the player while the death sequence was playing")

	# Same held input, several ticks after the sequence let go: input must be
	# usable again, or the lock leaked past the cutscene it was meant to cover.
	await step(15)
	check(not is_equal_approx(player.global_position.z, start_position.z), \
		"input stayed locked after the death sequence finished")

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

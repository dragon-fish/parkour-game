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
	# The storyboard is 0.5 drop + 1.0 knelt + 1.5 topple + 1.0 lying still.
	assert_almost_eq(seq.total_duration(), 4.0, 0.001, 		"the death sequence no longer matches its storyboard")
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

func test_the_topple_ends_with_the_view_on_the_ground() -> void:
	# The arc pivots on the FEET, and the rig hangs off the Player node whose
	# origin is the capsule's CENTRE -- so a pose worked in rig-local terms
	# bottoms out half a body above the floor. Reported from play as "it only
	# rotated, the height never came down".
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

	var stature: float = player.standing_height() * 0.5 + cfg.camera.eye_height
	var start_y: float = player.camera_rig.global_position.y - player.global_position.y \
		+ player.standing_height() * 0.5

	# Run the whole thing, sampling the lowest the view ever gets.
	var lowest := start_y
	var ticks: int = int(seq.total_duration() * Engine.physics_ticks_per_second) + 10
	for i in ticks:
		await step(1)
		var above_ground: float = player.camera_rig.global_position.y \
			- player.global_position.y + player.standing_height() * 0.5
		lowest = minf(lowest, above_ground)

	assert_almost_eq(start_y, stature, 0.05, \
		"test setup is wrong: the view did not start at eye height above ground")
	assert_true(lowest < stature * 0.15, \
		"the topple never brought the view near the ground (lowest %.3f m of %.3f m)" \
			% [lowest, stature])

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_the_cutscene_levels_a_view_that_died_looking_down() -> void:
	# Watching the ground come up is the reflex on a fatal fall, so the pitch
	# at the moment of death is usually steeply down. The cutscene drives pitch
	# itself rather than inheriting it -- a topple played from a face-down view
	# reads as nonsense.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	# Look steeply down, the way a falling player would be.
	for i in 200:
		player.camera_rig.apply_look(Vector2(0.0, 100.0), player)
	assert_true(player.camera_rig.rotation.x < -deg_to_rad(60.0), \
		"test setup is wrong: the view is not steeply down")

	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	seq.play(player)

	# EASED over the drop, not snapped: halfway through the view should be
	# somewhere in between rather than already level.
	var half_ticks: int = int(DeathSequence.DROP_TIME * 0.5 * Engine.physics_ticks_per_second)
	for i in half_ticks:
		await step(1)
	var midway: float = player.camera_rig.rotation.x
	assert_true(midway < -0.02, \
		"the pitch snapped to level instead of easing (midway %.3f rad)" % midway)

	# By the end of the drop it should be level, whatever it started at.
	var rest: int = int(DeathSequence.DROP_TIME * Engine.physics_ticks_per_second) - half_ticks + 4
	for i in rest:
		await step(1)
	assert_almost_eq(player.camera_rig.rotation.x, 0.0, 0.05, \
		"the cutscene inherited the player's death pitch instead of levelling it")

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_the_head_travels_the_same_way_the_body_rolls() -> void:
	# A roll of -angle turns the camera's up axis toward its RIGHT, so the head
	# has to travel right too. Sending it left while rolling right cancels out
	# and reads as the head dropping straight down with the picture spinning
	# around it -- reported from play as "it lost the volume of the waist".
	#
	# A real player, not a null one: the arc's radius comes from the body's
	# stature, and a null player collapses it to the clearance floor.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)

	var seq := DeathSequence.new()
	get_tree().root.add_child(seq)
	await step(1)
	seq.play(world["player"])

	# Sample the very end of the topple, where the displacement is largest.
	var t: float = DeathSequence.DROP_TIME + DeathSequence.HOLD_TIME \
		+ DeathSequence.TOPPLE_TIME
	var pose: Array = seq._pose_at(t)
	var offset: Vector3 = pose[0]
	var roll: float = pose[1]

	assert_true(roll < -1.5, "the topple did not roll a quarter turn (%.3f rad)" % roll)
	assert_true(offset.x > 0.3, \
		"the head travelled the wrong way for the roll (x %.3f, roll %.3f)" % [offset.x, roll])

	seq.queue_free()
	TestWorld.teardown(world)
	await step(1)

func test_third_person_does_not_roll_the_camera() -> void:
	# ✅ THE OWNER: "do not play the first-person screen rotation when dying in
	# third person -- play the Death2 animation instead."
	#
	# The cinematic pose IS the first-person death: the eye falls, rolls and
	# looks at the sky because that is what the body is doing, and from inside
	# there is no body visible to do it. From outside there is one, and rolling
	# the camera on top of it reads as the world tipping over.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	player.camera_rig.third_person = true
	var sequence := DeathSequence.new()
	add_child(sequence)
	sequence.play(player)
	await step(20)
	assert_false(player.camera_rig.in_cinematic(),
		"a third-person death took the camera into a cinematic")
	assert_true(player.is_dying(), "the body was never told it was dying")
	sequence.stop()
	sequence.queue_free()
	TestWorld.teardown(world)

func test_first_person_still_falls_over() -> void:
	# The pair. Without it the test above passes on a build where the cutscene
	# never runs at all.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	player.camera_rig.third_person = false
	var sequence := DeathSequence.new()
	add_child(sequence)
	sequence.play(player)
	await step(20)
	assert_true(player.camera_rig.in_cinematic(),
		"a first-person death did not take the camera over")
	sequence.stop()
	sequence.queue_free()
	TestWorld.teardown(world)

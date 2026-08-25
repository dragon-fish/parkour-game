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

	# Same held input, after the sequence let go AND the post-respawn cover
	# ran out (RESPAWN_COVER + COVER_FADE of deliberate lock -- the owner:
	# 重置之后再覆盖0.5s并且期间禁操作): input must be usable again, or the
	# lock leaked past everything it was meant to cover.
	await step(int((DeathSequence.RESPAWN_COVER + DeathSequence.COVER_FADE) * 60.0) + 15)
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

## A body with a skeleton and a head, built at runtime so this depends on no
## untracked model.
func _attach_body(player: Player) -> void:
	var root := Node3D.new()
	root.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	library.add_animation(&"idle", animation)
	anim_player.add_animation_library("", library)
	root.add_child(anim_player)
	anim_player.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	player._attach_body(packed)

func test_a_body_dies_by_its_own_animation_rather_than_a_scripted_fall() -> void:
	# ✅ THE OWNER FOUND THIS BY ACCIDENT: dying in third person and pressing V
	# mid-clip "lines up really well with the animation". Of course it does -- a
	# third-person death already skipped the cinematic, so the eye ran the
	# ordinary path and the head-follow carried it along with the death clip.
	#
	# So the scripted fall is the FALLBACK now, not the default, and what
	# decides is whether there is a body -- not which view is running. Two
	# scripted falls fighting over the same transform is what the cinematic
	# branch was ever protecting against.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	_attach_body(player)
	var sequence := DeathSequence.new()
	add_child(sequence)
	sequence.play(player)
	await step(20)
	assert_false(player.camera_rig.in_cinematic(),
		"a body-driven death took the camera into a scripted fall as well")
	assert_almost_eq(player.camera_rig.look_debug()["pitch"],
		deg_to_rad(player.config.camera.death_pitch_deg), 0.05,
		"the eye was left with nowhere to point")
	assert_almost_eq(player.camera_rig.position.y,
		player.config.camera.eye_height + player.config.camera.death_eye_lift, 0.05,
		"the first-person eye was not lifted out of the floor")
	sequence.stop()
	sequence.queue_free()
	TestWorld.teardown(world)

func test_a_bodiless_death_still_falls_over_on_its_own() -> void:
	# The pair, and the reason the old effect was kept rather than deleted:
	# without a body there is no head to follow and nothing to watch.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	assert_null(player.body, "the fixture attached a body after all")
	var sequence := DeathSequence.new()
	add_child(sequence)
	sequence.play(player)
	await step(20)
	assert_true(player.camera_rig.in_cinematic(),
		"a bodiless death had nothing driving the camera at all")
	sequence.stop()
	sequence.queue_free()
	TestWorld.teardown(world)

func test_a_fatal_fall_is_dying_before_it_can_strike_a_landing_pose() -> void:
	# ✅ THE OWNER: "why does a third-person death always play Jump_Land and
	# THEN Death2 -- it strikes a pose before dying."
	#
	# died_from_fall is DEFERRED, so the cutscene -- and with it set_dying() --
	# did not start until the next frame, and the body spent that frame landing
	# like anyone else. The declaration moved to the tick the fall is known to
	# be fatal, which is inside landing_destination() itself.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	var move := player.move_manager.move_for(Move.FALL_UNCONTROLLED) as AirborneMove
	assert_false(player.is_dying(), "the fixture started out dying")
	# The same call MoveManager makes when the body touches down.
	move.landing_destination(20.0, false)
	assert_true(player.is_dying(),
		"the body was not dying on the tick its fall turned out to be fatal")
	TestWorld.teardown(world)

func test_a_third_person_death_looks_DOWN_at_the_body() -> void:
	# ✅ THE OWNER: "it should be -25 there, or the camera ends up underground."
	# The geometry agrees: the camera hangs BEHIND the rig, so pitching the rig
	# up swings the arm DOWN -- straight into the floor a dead body is lying on.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	_attach_body(player)
	player.camera_rig.third_person = true
	var sequence := DeathSequence.new()
	add_child(sequence)
	sequence.play(player)
	await step(20)
	assert_lt(player.camera_rig.look_debug()["pitch"], 0.0,
		"a third-person death pitched the camera up, into the ground")
	# And no eye lift out here -- the camera is metres away and has no such
	# problem.
	assert_almost_eq(player.camera_rig.position.y,
		player.config.camera.eye_height, 0.05,
		"third person took the first-person floor compensation too")
	sequence.stop()
	sequence.queue_free()
	TestWorld.teardown(world)

func test_the_respawn_stays_covered_and_locked_for_a_beat() -> void:
	# ✅ THE OWNER: "死亡的黑屏应该在重置回检查点之后再覆盖个0.5s，并且期间禁操
	# 作，因为现在这个还是能看到镜头瞬移和身体从死亡站起来." The reset fires
	# under full black; the cover then holds with the input gate shut.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(10)
	var player: Player = world["player"]
	var sequence := DeathSequence.new()
	get_tree().root.add_child(sequence)
	var done := [false]
	sequence.finished.connect(func() -> void:
		done[0] = true
		# What Arena's reset_player() does to the two states the cover must
		# re-assert: the reset unlocks input and clears the tint.
		player.reset_state()
		player.screen_effects.set_tint(player.screen_effects.tint_color(), 0.0))
	sequence.play(player)
	await step(int(sequence.total_duration() * 60.0) + 3)
	assert_true(done[0], "test setup: the sequence never finished")
	# Right after the respawn: still pitch black, still locked.
	assert_almost_eq(player.screen_effects.tint_amount, 1.0, 0.1,
		"the respawn was not covered")
	assert_true(player.is_input_locked(), "input opened the instant of the respawn")
	# After the hold and the fade: lifted and unlocked.
	await step(int((DeathSequence.RESPAWN_COVER + DeathSequence.COVER_FADE) * 60.0) + 5)
	assert_almost_eq(player.screen_effects.tint_amount, 0.0, 0.01,
		"the cover never lifted")
	assert_false(player.is_input_locked(), "the cover never gave the input back")
	sequence.queue_free()
	TestWorld.teardown(world)
	await step(1)

class_name TestDeathToRespawn
extends TestCase

# END-TO-END GUARD. tests/test_death_sequence.gd exercises DeathSequence
# alone (a null player, then a hand-built one for the input-lock test above);
# tests/test_fatal_fall_respawn.gd substitutes a bare stand-in for Arena to
# isolate the mid-move-execution respawn timing bug, and deliberately skips
# DeathSequence entirely (see its own header). Neither one runs the actual
# wiring Arena._ready() sets up: died_from_fall -> DeathSequence.play() ->
# finished -> reset_player(). This is the one test that would fail if that
# chain came unwired -- e.g. the CONNECT_DEFERRED line, or the
# `_death_sequence.finished.connect(reset_player)` line, being deleted.
#
# The respawn check below deliberately does NOT hang the assertion off
# DeathSequence.finished firing: that signal fires whether or not anything is
# listening to it, so a test built on "did `finished` fire" would stay green
# even with Arena's own connection deleted. `_resetting_physics` only turns
# true as a side effect of Arena.reset_player() actually running (it is the
# first thing that function sets before its own internal await), so polling
# it is what makes a severed wire show up as a failure here.

func test_a_fatal_fall_plays_the_death_sequence_before_respawning() -> void:
	var arena: Node3D = ArenaBuilder.new().build()
	tree.root.add_child(arena)
	await step(1)
	# Arena._ready() kicks off its own reset_player() to place the player at
	# spawn; give it, and the fall it settles from, generous room to finish.
	await step(30)

	var player: Player = arena.player
	check(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: never settled onto the floor after spawning")

	# Stage a genuine fatal fall, same recipe as
	# tests/test_uncontrolled_fall.gd:21-22 -- lift the body, then re-baseline
	# the fall tracker to the lifted height so the drop back down is measured
	# as a real one rather than netting zero against the launch height.
	player.global_position.y += arena.config.pawn.falling_uncontrolled_height + 3.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)

	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.FALL_UNCONTROLLED:
			break
	check(player.move_manager.current_name == Move.FALL_UNCONTROLLED, \
		"the staged fall never entered FallUncontrolled")

	# died_from_fall is CONNECT_DEFERRED (must stay that way -- see
	# Arena._ready()'s own comment), so the sequence starts a tick or two
	# after the body actually lands. Poll for it rather than assuming a fixed
	# tick offset.
	var saw_reset := false
	for i in 300:
		await step(1)
		if arena._resetting_physics:
			saw_reset = true
		if arena._death_sequence._playing:
			break
	check(arena._death_sequence._playing, \
		"the death sequence never started after a fatal landing")
	check(not saw_reset, \
		"reset_player() ran before the death sequence finished -- respawn was not deferred")

	# Run past total_duration() and confirm the deferred respawn actually
	# happens: reset_player() runs (observed via _resetting_physics, see the
	# file header on why that and not the `finished` signal itself is what
	# proves this), then the player is back at spawn, walking, and the
	# sequence no longer reports itself playing.
	var ticks: int = int(arena._death_sequence.total_duration() * Engine.physics_ticks_per_second) + 30
	for i in ticks:
		await step(1)
		if arena._resetting_physics:
			saw_reset = true
		if saw_reset and not arena._death_sequence._playing:
			break
	check(saw_reset, \
		"reset_player() never ran -- the death sequence's finished signal is not driving a respawn")
	check(not arena._death_sequence._playing, \
		"the death sequence still reports itself playing after the respawn should have landed")
	check(player.move_manager.current_name == Move.WALKING, \
		"the player was not back in Walking after the respawn")
	check_approx(player.global_position.x, arena.spawn_point.global_position.x, 0.5, \
		"the player did not return to the spawn point on the X axis")
	check_approx(player.global_position.y, arena.spawn_point.global_position.y, 0.5, \
		"the player did not return to the spawn point on the Y axis")
	check_approx(player.global_position.z, arena.spawn_point.global_position.z, 0.5, \
		"the player did not return to the spawn point on the Z axis")

	arena.queue_free()
	await step(1)

func test_a_manual_reset_mid_cutscene_is_not_undone_when_the_cutscene_would_have_ended() -> void:
	# C REGRESSION, and the Arena half of it -- tests/test_death_sequence.gd
	# pins DeathSequence.stop() itself; this pins that reset_player() actually
	# calls it. Without that call the cutscene runs on regardless, fires
	# `finished` at total_duration(), and Arena's own wiring turns that into a
	# SECOND respawn seconds after the player pressed R and got moving again.
	#
	# Observed through _resetting_physics for the same reason this file's
	# header gives: it only turns true as a side effect of reset_player()
	# actually running, so a severed or missing call shows up here rather than
	# hiding behind a signal that fires whether or not anyone acts on it.
	#
	# Verified to go red by removing the stop() call from reset_player().
	var arena: Node3D = ArenaBuilder.new().build()
	tree.root.add_child(arena)
	await step(1)
	await step(30)

	var player: Player = arena.player
	check(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: never settled onto the floor after spawning")

	arena._death_sequence.play(player)
	await step(5)
	check(arena._death_sequence._playing, \
		"test setup is wrong: the death sequence is not running")

	# Exactly what the R key does (Arena._unhandled_input calls this directly).
	arena.reset_player()
	await step(3)
	check(not arena._death_sequence._playing, \
		"a manual reset left the death sequence running")
	check(not arena._resetting_physics, \
		"test setup is wrong: the manual reset is still in flight")

	# Run well past the point the cancelled sequence would have completed.
	var ticks: int = int(arena._death_sequence.total_duration() * Engine.physics_ticks_per_second) + 40
	var respawned_again := false
	for i in ticks:
		await step(1)
		if arena._resetting_physics:
			respawned_again = true
	check(not respawned_again, \
		"the cancelled cutscene respawned the player anyway, long after the manual reset")

	arena.queue_free()
	await step(1)

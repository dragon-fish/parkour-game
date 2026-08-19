class_name TestFatalFallRespawn
extends TestCase

# Regression: a fatal fall crashed the game on landing with
# "state Walking did not declare grounded-ness".
#
# died_from_fall is a plain (synchronous) signal emitted from inside
# FallingMove.physics_update(). Whoever respawns on it therefore teleports the
# body WHILE a move is still executing -- and Arena.reset_player()'s own header
# says it "spans a physics frame" and must not be treated as synchronous.
# Player.reset_state() also writes `grounded` directly rather than through
# set_grounded(), so the declaration counter does not advance while the body it
# describes moves somewhere else entirely.
#
# This drives the whole sequence -- fatal drop, landing, respawn, and several
# ticks of ordinary walking afterwards -- because the assertion did not fire on
# the landing tick itself but somewhere in the ticks that followed.

const TestWorld = preload("res://tests/world_fixture.gd")

func test_a_fatal_fall_survives_its_own_respawn() -> void:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(tree, cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	check(player.move_manager.current_name == Move.WALKING, \
		"test setup is wrong: never settled onto the floor")

	# Stand in for Arena, and it must do EVERYTHING Arena.reset_player() does --
	# including restarting the move manager. That last step is the whole point:
	# a first version of this test omitted it, passed, and missed the bug
	# entirely. MoveManager.start() re-arms the declaration check, so running it
	# from inside a move's own physics_update() re-baselines the counter to a
	# value the finishing tick can no longer exceed.
	var spawn_y: float = player.global_position.y
	var respawns := {"count": 0}
	player.died_from_fall.connect(func() -> void:
		respawns["count"] += 1
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(0.0, spawn_y, 0.0)
		player.reset_state()
		player.move_manager.start(Move.WALKING))

	# Stage a genuine deep fall: lift the body, then re-baseline the counter to
	# the lifted height so the drop back down is measured as a real one. Simply
	# teleporting upward would net ZERO fall -- the body returns to the height it
	# launched from -- which is the launch-relative counter behaving correctly,
	# not a bug to work around.
	player.global_position.y += cfg.pawn.falling_uncontrolled_height + 3.0
	player.fall_tracker.reset(player.global_position.y)
	await step(1)
	check(player.move_manager.current_name == Move.FALLING, \
		"test setup is wrong: the teleport did not send the player airborne")

	# Long enough to fall the whole way and land, then keep walking. The
	# original failure appeared during the ticks AFTER the respawn, so running
	# on past the landing is the point of the test rather than incidental.
	#
	# 400, not 180: this stand-in respawns immediately on died_from_fall (it
	# does not play DeathSequence, see the comment above), but the bound is
	# kept wide enough to also cover the real Arena's now-longer respawn
	# window -- DeathSequence.total_duration() adds ~1.4s (~84 ticks at 60Hz)
	# between death and reset_player() there -- so this loop stays generous
	# relative to what the actual game does, even though nothing here forces
	# it to wait that long.
	for i in 400:
		await step(1)
		if respawns["count"] > 0 and player.move_manager.current_name == Move.WALKING:
			break

	check_greater(respawns["count"], 0, "the fatal fall never reported a death")
	check(player.move_manager.current_name == Move.WALKING, \
		"never returned to walking after the respawn")

	# The tail that used to assert. Every tick here runs MoveManager's
	# declaration invariant, so simply surviving them is the assertion.
	for i in 60:
		await step(1)
	check(player.move_manager.current_name == Move.WALKING, \
		"walking did not survive the ticks after a respawn")
	check(player.move_manager.current_name != Move.FALL_UNCONTROLLED, \
		"the respawn left the player stuck in FallUncontrolled")

	TestWorld.teardown(world)
	await step(1)

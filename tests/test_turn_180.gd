extends ParkourTest

# Q part-way up a wall kick (TdMove_180Turn): spin to face back the way you
# came, hang there for DisableMovementTime, and either kick off the wall or
# drop. The hang is the feature -- DisableMovementTime is a real field across
# the original's move library that this project had never implemented.

const TestWorld = preload("res://tests/world_fixture.gd")

## Freed after every test. Without this the walls pile up in the shared scene
## root and the NEXT test's run-up meets geometry it never placed -- which is
## how a clean per-file run and a broken full-suite run happen at once.
var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	if _world.has("wall"):
		(_world["wall"] as Node).queue_free()
	TestWorld.teardown(_world)
	_world = {}


func _world_with_wall_ahead(height: float) -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, height, 1.0)
	shape.shape = box
	wall.add_child(shape)
	get_tree().root.add_child(wall)
	# Base resting ON the floor (whose top is y = 0), so `height` is the wall's
	# real height above the ground and a test can reason about it directly.
	wall.global_position = Vector3(0.0, height * 0.5, -2.5)
	world["wall"] = wall
	_world = world
	return world

## Runs the player into the wall, waits for the climb, then presses Q.
func _turning(world: Dictionary) -> Player:
	var player: Player = world["player"]
	player.global_position = Vector3(0.0, 1.5, -1.55)
	player.velocity = Vector3(0.0, 2.0, -6.0)
	player.move_manager.start(Move.JUMP)
	await step(2)
	assert_eq(player.move_manager.current_name, Move.WALL_CLIMB, \
		"the climb never started, so there is nothing to turn out of")
	(world["input"] as ScriptedInputSource).press_turn()
	await step(1)
	return player

# --- the confirmed numbers ---------------------------------------------------

func test_the_confirmed_values_are_in_place() -> void:
	var config := MovementConfig.new()
	assert_almost_eq(config.turn_180.disable_movement_time, 0.3, 0.0001, \
		"DisableMovementTime is not 0.3")
	assert_almost_eq(config.turn_180.redo_move_time, 0.5, 0.0001, "RedoMoveTime is not 0.5")
	assert_almost_eq(config.turn_180.friction_modifier, 0.3, 0.0001, \
		"FrictionModifier is not 0.3")
	assert_almost_eq(config.turn_180.wall_kick_speed_out, 3.0, 0.0001, \
		"WallKickVelocity2D is not 300 uu/s")
	assert_almost_eq(config.turn_180.wall_kick_speed_up, 5.8, 0.0001, \
		"WallKickVelocityZ is not 580 uu/s")

func test_the_view_is_clamped_to_the_confirmed_fan() -> void:
	# MinLookConstraint = (-10000, -16384, 0): -16384 of 65536 is a quarter
	# turn, and 10000 is 55 degrees.
	var config := MovementConfig.new()
	assert_true(config.turn_180.constrain_look, "the turn does not clamp the view at all")
	assert_almost_eq(config.turn_180.max_look_constraint.x, deg_to_rad(55.0), 0.001, \
		"the pitch clamp is not 55 degrees")
	assert_almost_eq(config.turn_180.max_look_constraint.y, deg_to_rad(90.0), 0.001, \
		"the yaw clamp is not 90 degrees")

# --- entry and the window ----------------------------------------------------

func test_q_during_a_climb_starts_the_turn() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"Q during a wall climb did not start the turn")

func test_the_body_holds_still_for_the_whole_window() -> void:
	# ✅ "During the wall climb turn there is almost no falling." The hang lasts
	# the ANIMATION -- wall_turn_time, 0.5 s -- rather than DisableMovementTime,
	# which names how long INPUT is disabled and says nothing about gravity.
	# Reading it as the whole hang was this project's own conflation.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	var held := player.global_position
	await step(10)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"the turn ended early -- the wall turn is 0.5 s, which is 30 ticks")
	assert_almost_eq(player.velocity.length(), 0.0, 0.0001, \
		"the body was still moving inside the window")
	assert_almost_eq(player.global_position.distance_to(held), 0.0, 0.0001, \
		"the body drifted inside the window")

func test_the_body_comes_all_the_way_round() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	var facing_before := player.rotation.y
	# wall_turn_time is the measured 0.5 s, which is 30 ticks. 35 leaves margin,
	# and is inside kick_window (0.75 s) so the move is still running.
	await step(35)
	var turned: float = absf(wrapf(player.rotation.y - facing_before, -PI, PI))
	assert_almost_eq(turned, PI, 0.02, "the body did not come round half a turn")

func test_letting_the_window_lapse_drops_the_player() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	# Past kick_window (0.75 s, 45 ticks), not merely past the freeze. The two
	# were one number until the owner reported the grace period as too short to
	# use -- "Q has to be followed by space immediately or you slide off" -- so
	# a test that only outlasts the freeze would pass while proving nothing.
	await step(50)
	# Left the turn, rather than specifically Falling: the body is dropping by
	# then, and from 1.5 m it may well have reached the floor and gone straight
	# on to Walking. Either is the window closing; staying in Turn180 is not.
	assert_ne(player.move_manager.current_name, Move.TURN_180, \
		"the window lapsed without ever handing back")

func test_the_kick_survives_well_past_the_freeze() -> void:
	# The bug this split fixes, pinned directly: at 0.5 s the body is falling
	# again but the chance to kick is still open.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	await step(30)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"the turn ended between the freeze and the end of the kick window")
	(world["input"] as ScriptedInputSource).press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"a late kick, after the freeze but inside the window, was refused")

# --- the kick ----------------------------------------------------------------

func test_space_inside_the_window_kicks_off_the_wall() -> void:
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	# Past turn_time (0.5 s, 30 ticks) and inside kick_window (0.75 s), so this
	# is an ordinary kick rather than a pre-buffered one. The pre-buffered case
	# has its own test below.
	await step(32)
	(world["input"] as ScriptedInputSource).press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"space inside the window did not kick off the wall")
	assert_almost_eq(player.velocity.y, player.config.turn_180.wall_kick_speed_up, 0.35, \
		"the kick did not leave at WallKickVelocityZ")

func test_the_kick_throws_the_player_away_from_the_wall() -> void:
	# The wall is at -Z and the player has turned to face +Z, so the kick has
	# to send them the way they are now looking. Getting this backwards would
	# fire them into the wall they just turned away from.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	# Past turn_time (0.5 s, 30 ticks) and inside kick_window (0.75 s), so this
	# is an ordinary kick rather than a pre-buffered one. The pre-buffered case
	# has its own test below.
	await step(32)
	(world["input"] as ScriptedInputSource).press_jump()
	await step(1)
	assert_gt(player.velocity.z, 0.0, "the kick sent the player back into the wall")

func test_space_pressed_mid_turn_waits_for_the_turn_to_finish() -> void:
	# ✅ THE ORIGINAL PRE-BUFFERS THIS: "press Q, and even before the view has
	# come round, pressing space makes Faith jump out the instant it does."
	#
	# Acted on immediately, a kick taken mid-turn leaves along a facing halfway
	# between where you were and where you were going -- and choosing that
	# facing is the entire reason to press Q.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	# Early: the body has barely started coming round.
	await step(4)
	(world["input"] as ScriptedInputSource).press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"the kick fired mid-turn instead of waiting for the facing")
	# ...and it is HELD, not dropped. turn_time is 30 ticks, so by 35 the turn
	# has finished and the press must have been spent.
	await step(30)
	assert_eq(player.move_manager.current_name, Move.JUMP, \
		"the held press was never spent once the turn finished")
	assert_gt(player.velocity.z, 0.0, \
		"the pre-buffered kick left along the wrong facing")

# --- Q away from a wall ------------------------------------------------------
#
# The owner corrected the scope after the first version shipped: "why does Q
# only work off a wall? Q works almost everywhere -- anywhere the legs are not
# tied up, like a 180 while walking, or a 90 while wall running."

func test_q_while_walking_turns_the_body_right_round() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	await step(2)
	var facing_before := player.rotation.y
	(world["input"] as ScriptedInputSource).press_turn()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.TURN_180, \
		"Q while walking did not start a turn")
	# A ground turn is the measured 0.3 s, which is 18 ticks.
	await step(35)
	var turned: float = absf(wrapf(player.rotation.y - facing_before, -PI, PI))
	assert_almost_eq(turned, PI, 0.02, "a walking turn did not come round half a turn")

func test_a_walking_turn_bleeds_its_speed_away_rather_than_stopping_dead() -> void:
	# ✅ MEASURED: "speed does not drop to zero instantly, it goes to zero over
	# about 0.3 s -- it feels as though you carry the old direction's inertia
	# until you have fully come round."
	#
	# The first version kept the momentum outright, on the reasoning that
	# stopping dead would make Q a move nobody would press. Half right: what
	# makes it pressable is that the stop is GRADUAL and lands as the turn does.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	await step(2)
	player.velocity = Vector3(0.0, 0.0, -5.0)
	(world["input"] as ScriptedInputSource).press_turn()
	# A third of the way through slowdown_time: most of the speed is still there.
	await step(6)
	var mid: float = player.horizontal_speed()
	assert_gt(mid, 2.0, "a walking turn stopped the body dead (%.2f m/s left)" % mid)
	assert_lt(mid, 4.6, "a walking turn kept its speed outright (%.2f m/s left)" % mid)
	# ...and by the end there is nothing left. slowdown_time is 0.3 s, 18 ticks.
	await step(14)
	assert_lt(player.horizontal_speed(), 0.5, \
		"the speed never bled away (%.2f m/s left)" % player.horizontal_speed())

func test_a_walking_turn_keeps_only_the_measured_share_of_the_budget() -> void:
	# ✅ MEASURED: "the speed energy is not 100% preserved either -- it seems to
	# keep only up to the ~19 km/h tier. You can get back to 18-19 quickly, and
	# after that the acceleration is like normal running."
	#
	# A capped energy budget produces exactly that shape: below the cap the
	# ground acceleration alone gets you there, above it you have to re-earn the
	# speed the ordinary way.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	var input := world["input"] as ScriptedInputSource
	input.state.move = Vector2(0.0, 1.0)
	# Long enough to bank a budget well past the cap, so the clamp has something
	# to take away.
	await step(150)
	var banked: float = player.speed_cap()
	assert_gt(banked, player.config.turn_180.speed_keep_ceiling, \
		"never banked past the cap, so this test proves nothing (%.2f m/s)" % banked)
	input.press_turn()
	await step(2)
	assert_lt(player.speed_cap(), player.config.turn_180.speed_keep_ceiling + 0.1, \
		"the turn kept a budget above the measured 19 km/h (%.2f m/s)" % player.speed_cap())

func test_a_walking_turn_is_not_billed_as_a_mouse_swing() -> void:
	# The turn tax is charged on the change in WISH direction, which a scripted
	# half turn flips through 180 degrees in one tick. Billed, Q would be the
	# most expensive key on the board.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	var input := world["input"] as ScriptedInputSource
	input.state.move = Vector2(0.0, 1.0)
	# Long enough to bank a real budget, so a charge would have something to
	# take away and the assertion is not passing on an empty tank.
	await step(150)
	var banked: float = player.speed_energy.energy
	assert_gt(banked, 0.5, "never banked enough energy for the charge to show (%.2f)" % banked)
	input.press_turn()
	await step(15)
	assert_gt(player.speed_energy.energy, banked * 0.5, \
		"the scripted turn was billed as a mouse swing (%.2f -> %.2f)" \
		% [banked, player.speed_energy.energy])

func test_a_move_with_its_legs_busy_refuses_the_turn() -> void:
	# The gate is per-move data rather than a list kept somewhere else, so this
	# checks the data. Slide is the clearest case: on the floor, mid-slide.
	var config := MovementConfig.new()
	assert_false(config.slide.allows_turn, "a slide allows a turn")
	assert_false(config.grab.allows_turn, "a hang allows a turn")
	assert_false(config.speed_vault.allows_turn, "a vault allows a turn")
	assert_true(config.walking.allows_turn, "walking refuses a turn")
	# A wall run refuses too, but for the opposite reason: Q there does
	# something else entirely. See test_wall_run_look.gd.
	assert_false(config.wall_run.allows_turn, "a wall run starts a turn move")

# --- the turn goes one way ----------------------------------------------------

func test_a_wall_turn_never_doubles_back_on_itself() -> void:
	# THE TWITCH. This move's clamp is an absolute-yaw one, so apply_look pins
	# the body to reference + offset every tick from a reference captured when
	# the turn began -- while _advance_turn wrote the body directly as well. Two
	# writers a tick, pulling opposite ways, which the owner saw as "the camera
	# twitches left and right" during a wall-climb turn.
	#
	# Sampled per tick rather than end to end, because both the broken version
	# and the fixed one arrive at the same place. Only the path differs.
	var world := await _world_with_wall_ahead(6.0)
	var player: Player = await _turning(world)
	var previous: float = player.rotation.y
	var direction := 0.0
	for i in 12:
		await step(1)
		var step_taken: float = wrapf(player.rotation.y - previous, -PI, PI)
		previous = player.rotation.y
		if absf(step_taken) < 0.0005:
			continue
		if direction == 0.0:
			direction = signf(step_taken)
		assert_eq(signf(step_taken), direction, \
			"the turn reversed on tick %d (%.3f rad)" % [i, step_taken])
		assert_lt(absf(step_taken), 0.6, \
			"the turn jumped %.3f rad in one tick" % absf(step_taken))

func test_the_turn_goes_clockwise_whatever_the_approach_was() -> void:
	# ✅ MEASURED in the original: "Faith only ever turns right." Godot's yaw
	# grows counter-clockwise seen from above, so clockwise is DOWN.
	#
	# Checked from two different approach angles, because the rule this replaced
	# turned whichever way was shorter -- which made the direction a function of
	# the entry angle, and a coin flip on float noise for the head-on approach
	# the move is mostly used for.
	for approach in [-deg_to_rad(20.0), deg_to_rad(20.0)]:
		var world := await _world_with_wall_ahead(6.0)
		var player: Player = world["player"]
		player.global_position = Vector3(0.0, 1.5, -1.55)
		player.rotation.y = approach
		player.velocity = Vector3(0.0, 2.0, -6.0)
		player.move_manager.start(Move.JUMP)
		await step(2)
		assert_eq(player.move_manager.current_name, Move.WALL_CLIMB, \
			"the climb never started at %.0f degrees" % rad_to_deg(approach))
		(world["input"] as ScriptedInputSource).press_turn()
		await step(1)
		var started := player.rotation.y
		await step(6)
		assert_lt(wrapf(player.rotation.y - started, -PI, PI), 0.0, \
			"the turn went anti-clockwise from a %.0f degree approach" \
			% rad_to_deg(approach))
		after_each()

func test_the_two_turns_take_their_two_measured_times() -> void:
	# ✅ MEASURED separately, and kept as two figures because they measured
	# differently and there is no honest way to average them. A DURATION rather
	# than a rate in both cases: a turn takes the same time whatever angle it
	# covers, which is what an animation does.
	var config := MovementConfig.new()
	assert_almost_eq(config.turn_180.turn_time, 0.3, 0.0001, \
		"a ground turn is not the measured 0.3 s")
	assert_almost_eq(config.turn_180.wall_turn_time, 0.5, 0.0001, \
		"a wall turn is not the measured 0.5 s")
	# The wall turn has to finish inside the chance to kick off, or a
	# pre-buffered press could never be spent at all.
	assert_lt(config.turn_180.wall_turn_time, config.turn_180.kick_window, \
		"the wall turn outlasts the chance to kick off the wall")

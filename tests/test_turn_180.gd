extends ParkourTest

# Q part-way up a wall kick (TdMove_180Turn): spin to face back the way you
# came, hang there for DisableMovementTime, and either kick off the wall or
# drop. [ME:CONFIRMED] DisableMovementTime is a real field across the
# original's move library; the hang is the feature.

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
	assert_almost_eq(config.turn_180.climb_jump_push_away_speed, 4.0, 0.0001, \
		"JumpPushAwaySpeed is not 400 uu/s")
	assert_almost_eq(config.turn_180.climb_jump_off_z_height, 2.5, 0.0001, \
		"JumpOffZHeight is not 250 uu")

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
	# [ME:INFERRED] There is almost no falling through the whole wall-climb
	# turn. The hang lasts the ANIMATION -- wall_turn_time, 0.5 s -- not
	# DisableMovementTime, which only names how long INPUT is disabled and
	# says nothing about gravity.
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
	# Past kick_window (0.75 s, 45 ticks), not merely past the freeze. The
	# grace period to kick off must stay separate from, and longer than, the
	# movement freeze, or the window to react is too short to use.
	await step(50)
	# Left the turn, rather than specifically Falling: the body is dropping by
	# then, and from 1.5 m it may well have reached the floor and gone straight
	# on to Walking. Either is the window closing; staying in Turn180 is not.
	assert_ne(player.move_manager.current_name, Move.TURN_180, \
		"the window lapsed without ever handing back")

func test_the_kick_survives_well_past_the_freeze() -> void:
	# At 0.5 s (wall_turn_time) the body has resumed falling, but the chance
	# to kick off must still be open -- kick_window is 0.75 s.
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
	# The wall was ahead: a climb's turn, so TdMove_WallClimb180TurnJump.
	var cfg: Turn180Config = player.config.turn_180
	assert_almost_eq(player.velocity.y, sqrt(2.0 * player.config.pawn.gravity * cfg.climb_jump_off_z_height), 0.35, \
		"a climb's kick did not rise to JumpOffZHeight")

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
	# [ME:INFERRED] The original pre-buffers this press: Q, then space before
	# the view has come round, still fires the jump the instant the turn
	# finishes.
	#
	# Acted on immediately instead, a kick taken mid-turn would leave along a
	# facing halfway between where you were and where you were going -- and
	# choosing that facing is the entire reason to press Q.
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
# Q must work almost everywhere the legs are not tied up -- not only off a
# wall: a 180 while walking, a 90 while wall running.

func test_q_while_walking_turns_the_body_right_round() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	# SETTLED: two ticks after place() the body is still falling onto the
	# slab, and a Q there is a turn in the air.
	await step(30)
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
	# [ME:CONFIRMED] Speed does not drop to zero instantly; it decays to zero
	# over about 0.3 s, as though the old direction's inertia carries through
	# until the turn is complete.
	#
	# The decay must be GRADUAL and land exactly as the turn finishes: an
	# instant stop makes Q too punishing to press, and keeping the momentum
	# outright removes the point of turning at all.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	# SETTLED, or this is not a walking turn: two ticks after place() the body
	# is still FALLING onto the slab, and a forward fall turned round in the
	# air lands on its back (LayOnGroundMove), which brakes by its own rule.
	await step(30)
	assert_true(player.grounded, "test setup: the body never settled onto the floor")
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
	# [ME:INFERRED] The speed energy is not 100% preserved either: it keeps
	# only up to about the 19 km/h tier. Speed climbs back to 18-19 quickly,
	# and past that the acceleration is ordinary running.
	#
	# A capped energy budget produces exactly that shape: below the cap the
	# ground acceleration alone gets you there, above it you have to re-earn
	# the speed the ordinary way.
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
	# the turn began -- while _advance_turn writes the body directly too. Two
	# writers a tick, pulling opposite ways, reads as the camera twitching
	# left and right during a wall-climb turn.
	#
	# DO NOT sample end to end instead of per tick: a twitching path and a
	# smooth one can still land at the same final angle, so only a per-tick
	# check catches the difference.
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
	# [ME:CONFIRMED] Faith only ever turns right. Godot's yaw grows
	# counter-clockwise seen from above, so clockwise is DOWN.
	#
	# Checked from two different approach angles: turning whichever way is
	# shorter makes the direction a function of the entry angle, and is a
	# coin flip on float noise for the head-on approach the move is mostly
	# used for.
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
	# [ME:CONFIRMED] Measured separately, and kept as two figures: the ground
	# and wall turns take different amounts of time, and there is no honest
	# way to average them. Both are a DURATION rather than a rate -- a turn
	# takes the same time whatever angle it covers, which is what an
	# animation does.
	var config := MovementConfig.new()
	assert_almost_eq(config.turn_180.turn_time, 0.3, 0.0001, \
		"a ground turn is not the measured 0.3 s")
	assert_almost_eq(config.turn_180.wall_turn_time, 0.5, 0.0001, \
		"a wall turn is not the measured 0.5 s")
	# The wall turn has to finish inside the chance to kick off, or a
	# pre-buffered press could never be spent at all.
	assert_lt(config.turn_180.wall_turn_time, config.turn_180.kick_window, \
		"the wall turn outlasts the chance to kick off the wall")

## Running, then jumping, then Q at the top of the jump: returns the player the
## tick the turn is pressed.
func _turning_in_the_air(hold_forward: bool) -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	await step(30)
	var input := world["input"] as ScriptedInputSource
	input.state.move = Vector2(0.0, 1.0)
	await step(60)
	input.press_jump()
	await step(6)
	assert_eq(player.move_manager.current_name, Move.JUMP, "test setup: never took off")
	if not hold_forward:
		input.state.move = Vector2.ZERO
	input.press_turn()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.TURN_180_IN_AIR, "test setup: Q in the air did not turn")
	return player

func test_a_turn_in_the_air_keeps_the_flight() -> void:
	var player: Player = await _turning_in_the_air(true)
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	await step(20)  # through the 0.3 s turn
	var after := Vector3(player.velocity.x, 0.0, player.velocity.z)
	assert_almost_eq(after.length(), travel.length(), 0.05, "the turn bled the flight away in mid-air")

func test_the_keys_do_nothing_after_a_turn_in_the_air() -> void:
	# W is held throughout, and after the turn it points back the way the
	# flight came: unlocked, it would brake the flight until touchdown.
	var player: Player = await _turning_in_the_air(true)
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	for i in 120:
		await step(1)
		if player.grounded:
			break
		var now := Vector3(player.velocity.x, 0.0, player.velocity.z)
		assert_almost_eq(now.length(), travel.length(), 0.05,
			"a key steered the flight after a turn in the air (%s)" % player.move_manager.current_name)
		if absf(now.length() - travel.length()) > 0.05:
			return
	assert_true(player.grounded, "test setup: never landed")

func test_the_model_comes_round_with_a_turn_in_the_air() -> void:
	# Keys let go: nothing asks the model to follow the body except the turn.
	var player: Player = await _turning_in_the_air(false)
	await step(20)
	assert_almost_eq(wrapf(player.visual_yaw() - player.rotation.y, -PI, PI), 0.0, 0.05,
		"the model was left behind by a turn in the air")

## A drop past hard_landing_height, turned in the air at `turn_at` ticks after
## the take-off. Returns the player once it has come to rest on its back.
func _turned_drop(turn_at: int) -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	var player: Player = world["player"]
	await step(30)
	var input := world["input"] as ScriptedInputSource
	player.global_position = Vector3(0.0, 8.0, 0.0)
	player.fall_tracker.reset(player.global_position.y)
	player.velocity = Vector3(0.0, 6.3, -6.0)
	player.move_manager.start(Move.JUMP)
	for i in 150:
		if i == turn_at:
			input.press_turn()
		await step(1)
		if player.move_manager.current_name == Move.LAY_ON_GROUND:
			break
	assert_eq(player.move_manager.current_name, Move.LAY_ON_GROUND, "test setup: did not land on the back")
	return player

func test_a_turn_still_spinning_at_touchdown_pays_the_landing() -> void:
	# Turned late enough that the spin is not over when the feet arrive.
	var player: Player = await _turned_drop(70)
	assert_almost_eq(player.health.hp, 100.0 - player.config.landing.hard_landing_damage, 0.01,
		"a hard landing taken mid-turn cost nothing")

func test_a_hard_landing_on_the_back_flashes_red() -> void:
	var player: Player = await _turned_drop(10)
	var lying := player.move_manager.move_for(Move.LAY_ON_GROUND) as LayOnGroundMove
	assert_gt(lying._tint.a, 0.0, "a hard landing on the back showed no red")

func test_a_turn_in_the_air_reaches_for_nothing() -> void:
	# [ME:CONFIRMED 11 §11.2] 180TurnInAir holds no ledge, vault or wall
	# capability: the flight is a passenger's until it lands.
	var c: MoveConfig = MovementConfig.new().turn_180_in_air
	assert_false(c.check_for_grab or c.check_for_vault_over or c.check_for_wall_climb,
		"a turn in the air reaches for geometry")

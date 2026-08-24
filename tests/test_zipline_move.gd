extends ParkourTest

# 05 §5.5: caught from the air, ridden with no speed cap, left by crouching.
# Numbers are not asserted (they are the CDO's, and tunable); shapes are.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _line: InterestLine = null

func after_each() -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	_line = null
	if not _world.is_empty():
		TestWorld.teardown(_world)
		_world = {}

## A straight cable from `from` to `to`, world space.
func _cable(from: Vector3, to: Vector3) -> InterestLine:
	var line := InterestLine.new()
	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	line.curve = curve
	get_tree().root.add_child(line)
	return line

func _standing_player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	return _world["player"]

## Jump apex is ~0.98 m above the standing centre (0.95), so a cable at 2.3
## is inside reach_radius (0.6) at the top of a standing jump.
const CABLE_Y := 2.3

## Jumps under a level 12 m cable running +z and waits to be hanging.
func _riding_player() -> Player:
	var player: Player = await _standing_player()
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y, 11.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the cable")
	return player

func test_walking_through_the_volume_does_not_catch_it() -> void:
	var player: Player = await _standing_player()
	# Low enough that the standing capsule is inside the volume.
	_line = _cable(Vector3(0.0, 1.3, -3.0), Vector3(0.0, 1.3, 3.0))
	await step(10)
	assert_ne(player.move_manager.current_name, Move.ZIPLINE, \
		"a zipline may only be caught from the air")

func test_jumping_into_the_volume_catches_it() -> void:
	var player: Player = await _riding_player()
	assert_eq(player.move_manager.current_name, Move.ZIPLINE)
	assert_false(player.grounded, "riding a cable is not standing on the ground")

func test_the_body_hangs_below_the_cable() -> void:
	var player: Player = await _riding_player()
	await step(12)  # past fade_in_time
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var cable_at: Vector3 = _line.sample(zip.ride_offset())["position"]
	assert_almost_eq(player.global_position.y, cable_at.y - player.config.zipline.hang_offset, 0.02, \
		"the body is not hanging hang_offset below the cable")
	assert_almost_eq(player.global_position.x, cable_at.x, 0.02)
	assert_almost_eq(player.global_position.z, cable_at.z, 0.02)

func test_falling_too_fast_cannot_catch_it() -> void:
	var player: Player = await _standing_player()
	_line = _cable(Vector3(0.0, 4.0, -3.0), Vector3(0.0, 4.0, 3.0))
	# From 12 m the body passes the cable at ~15 m/s, well over fall_limit.
	player.global_position = Vector3(0.0, 12.0, 0.0)
	var caught := false
	for i in 90:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			caught = true
	assert_false(caught, "a body falling faster than fall_limit must not catch the cable")

func test_the_ride_travels_away_from_the_end_it_was_caught_at() -> void:
	var player: Player = await _riding_player()
	var before: float = player.global_position.z
	await step(20)
	assert_gt(player.global_position.z, before + 0.3, "the ride did not move along the cable")

func test_a_downhill_ride_slides_toward_the_low_end() -> void:
	# ✅ THE OWNER: "从低点朝高点方向跳起触发绳索，会逆着高度滑上去，甚至还会
	# 逐渐加速". Boarded here near the LOW end of a cable whose far end is
	# several metres higher -- the old "away from the nearer end" rule sent
	# this straight up the slope, with the min-acceleration floor (meant only
	# to carry a sagging cable's far half) happily powering the climb. A
	# zipline is one-way: that ride must not exist -- boarding near the low
	# end must slide back to the low end instead.
	var player: Player = await _standing_player()
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y + 8.0, 11.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the cable")
	await step(8)  # past fade_in_time -- baseline after the catch settles onto the wire, not mid-lerp
	var start_y: float = player.global_position.y
	var max_y: float = start_y
	for i in 20:
		await step(1)
		max_y = maxf(max_y, player.global_position.y)
	assert_lt(max_y, start_y + 0.05,
		"the ride climbed toward the high end instead of sliding to the low one (start %.2f, peak %.2f)"
			% [start_y, max_y])

func test_speed_never_drops_below_the_floor_and_keeps_rising() -> void:
	var player: Player = await _riding_player()
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var cfg: ZiplineConfig = player.config.zipline
	assert_true(zip.ride_speed() >= cfg.min_velocity - 0.001, "the ride started under min_velocity")
	var earlier: float = zip.ride_speed()
	await step(20)
	assert_gt(zip.ride_speed(), earlier, "a level cable must still accelerate (min_acceleration)")

func test_a_downhill_cable_accelerates_harder_than_a_level_one() -> void:
	var player: Player = await _riding_player()
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var level_accel: float = zip.ride_acceleration()
	_line.queue_free()
	TestWorld.teardown(_world)
	_world = {}
	await step(1)
	player = await _standing_player()
	# 30 degrees down over 12 m of run.
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y - 12.0 * tan(deg_to_rad(30.0)), 11.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the sloped cable")
	zip = player.move_manager.move_for(Move.ZIPLINE)
	assert_gt(zip.ride_acceleration(), level_accel + 0.5, "slope did not add acceleration")

func test_the_body_faces_along_the_cable() -> void:
	var player: Player = await _riding_player()
	await step(12)
	# The cable runs +z; Godot's forward is -z, so facing +z is yaw PI.
	assert_almost_eq(absf(wrapf(player.rotation.y, -PI, PI)), PI, 0.02, \
		"the body is not facing along the cable")

## The fixture cable runs +z and Godot's forward is -z, so along it is yaw PI.
const CABLE_YAW := PI

func test_the_view_can_be_turned_while_riding() -> void:
	# THE BUG. The ride re-centred the camera's yaw fan on the body EVERY tick,
	# and re-centring re-derives the player's accumulated turn from the body --
	# which this move had just written to the cable's own yaw. So every tick
	# threw away the mouse yaw apply_look() had accumulated microseconds
	# earlier (Player runs the look before the moves) and the view was welded
	# to the cable for the whole ride.
	var player: Player = await _riding_player()
	await step(12)  # past fade_in_time; the fan is centred by now
	var input: ScriptedInputSource = _world["input"]
	for i in 12:
		input.state.look = Vector2(60.0, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	var turned: float = wrapf(player.rotation.y - CABLE_YAW, -PI, PI)
	assert_gt(absf(turned), 0.05, "the view could not be turned away from the cable")
	# ...and no further than ZiplineConfig's own fan, which is the other half of
	# why the re-centring mattered: a fan nothing ever measures against cannot
	# clamp anything either.
	var fan: float = player.config.zipline.max_look_constraint.y
	assert_lt(absf(turned), fan + 0.001, \
		"the view left the cable's fan (%.1f degrees)" % rad_to_deg(turned))

func test_the_model_faces_along_the_cable_while_the_view_turns() -> void:
	# ZiplineConfig freezes the visual yaw, so Player counter-rotates BodyRoot
	# to hold the model's world heading -- and nothing updated that heading, so
	# the model rode the whole cable still facing wherever the jump came from
	# while the capsule faced along the cable.
	var player: Player = await _riding_player()
	await step(12)
	var input: ScriptedInputSource = _world["input"]
	for i in 12:
		input.state.look = Vector2(60.0, 0.0)
		await step(1)
	input.state.look = Vector2.ZERO
	assert_almost_eq(absf(wrapf(player.visual_yaw() - CABLE_YAW, -PI, PI)), 0.0, 0.02, \
		"the model is not facing along the cable")

func test_crouch_lets_go_and_keeps_the_speed_along_the_cable() -> void:
	var player: Player = await _riding_player()
	await step(12)
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var speed_before: float = zip.ride_speed()
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "crouch did not let go")
	var v: Vector3 = player.velocity
	assert_almost_eq(v.length(), speed_before, 0.2, "speed was not kept on release")
	# The test cable runs +z and is level: the velocity is along it.
	assert_gt(v.normalized().z, 0.99, "release velocity is not along the cable")
	assert_almost_eq(v.y, 0.0, 0.2, "release must not add a jump")

func test_the_end_of_the_cable_lets_go() -> void:
	var player: Player = await _riding_player()
	var reached_end := false
	for i in 300:
		await step(1)
		if player.move_manager.current_name != Move.ZIPLINE:
			reached_end = true
			break
	assert_true(reached_end, "the ride never ended")
	assert_gt(player.global_position.z, 9.0, "the body left the cable well before its end")

func test_letting_go_starts_the_redo_cooldown() -> void:
	var player: Player = await _riding_player()
	await step(5)
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()
	await step(1)
	assert_false(player.move_manager.can_enter(Move.ZIPLINE), "no cooldown after letting go")
	var cooldown: float = player.config.zipline.redo_move_time
	await step(int(cooldown * 60.0) + 2)
	assert_true(player.move_manager.can_enter(Move.ZIPLINE), "the cooldown never expired")

# --- one press, one action ---------------------------------------------------
#
# ✅ THE OWNER: "在ME里按一次按键只对应一次动作". Player._tick_timers() arms the
# roll buffer on EVERY crouch_pressed, unconditionally -- including the very
# press this move reads to let go of the cable. Left alone, that single press
# pays for two things: releasing the cable now, and (for up to
# roll_trigger_time afterwards) a skill roll at whatever the fall turns out to
# be. The fix spends the buffer at the point of release, same press, same tick.

func test_the_release_press_does_not_also_buy_a_roll_at_the_landing() -> void:
	var player: Player = await _riding_player()
	await step(12)  # past fade_in_time
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()  # the one press: lets go of the cable
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "test setup: crouch did not let go of the cable")
	# A single, flat-floor test world means an ordinary release from this low,
	# level cable lands back at the very height FallTracker was last
	# re-baselined to (ZiplineMove itself now re-baselines every tick it
	# rides -- see the fall-start-at-release fix), and would never clear the
	# roll threshold regardless of this bug -- so, exactly as
	# test_skill_roll.gd's _land_from() teleports the player to fake a real
	# drop, this stands in a synthetic launch point above the release so the
	# short physical fall back to the floor reads as a genuine one. Done
	# AFTER the release rather than before: while still riding, ZiplineMove's
	# own per-tick reset would only overwrite it again on the release tick.
	player.fall_tracker.reset(player.global_position.y + player.config.pawn.skill_roll_landing_height + 0.5)
	var saw_roll := false
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.SKILL_ROLL:
			saw_roll = true
		if player.grounded and player.move_manager.current_name != Move.SKILL_ROLL:
			break
	assert_false(saw_roll, "the same press that released the cable also fired a skill roll")

func test_a_second_later_press_still_buys_a_roll() -> void:
	# The counter-test: proves the fix removes the DOUBLE billing only, not the
	# roll itself. A genuinely new press, thrown while already falling, is its
	# own action and must still buy one.
	var player: Player = await _riding_player()
	await step(12)
	var input: ScriptedInputSource = _world["input"]
	input.press_crouch()  # press #1: releases the cable
	await step(1)
	assert_eq(player.move_manager.current_name, Move.FALLING, "test setup: crouch did not let go of the cable")
	# Same synthetic-launch trick as above, applied only after the release --
	# see that test's comment for why.
	player.fall_tracker.reset(player.global_position.y + player.config.pawn.skill_roll_landing_height + 0.5)
	input.press_crouch()  # press #2: a new press, while already airborne
	var saw_roll := false
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.SKILL_ROLL:
			saw_roll = true
			break
	assert_true(saw_roll, "a second, later press did not buy a roll")

# --- landing re-derives the ground speed budget ------------------------------
#
# ✅ THE OWNER: "落地速度 >=7.2 m/s 则地速恢复为 7.2". Left alone, the energy
# bank still holds whatever it did before catching the cable, so a fast ride
# decays right back to the pre-ride ground pace instead of grounding into a
# full sprint budget.

func test_landing_off_the_cable_restores_the_ground_speed_budget() -> void:
	var player: Player = await _standing_player()
	# Level, and long enough that MinZipAcceleration alone -- no slope needed
	# -- carries the ride well past ground_speed. Runs -Z, the player's own
	# default facing at the jump that catches it: a cable running the other
	# way would visually spin the body onto the cable's own heading, which
	# bills an unrelated mid-air turn at touchdown (Player._update_speed_energy())
	# and would muddy this test's own assertion with a cost this fix has
	# nothing to do with.
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y, -19.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the cable")
	# Held from here on: a real player landing off a fast ride is holding
	# forward, not standing on the brake. Without this the very tick that
	# lands also runs Player._update_speed_energy()'s no-input branch, which
	# calls SpeedEnergy.decay() and immediately eats into whatever this fix
	# just restored -- an artifact of standing still, not of the fix.
	input.state.move = Vector2(0.0, 1.0)
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var cfg: PawnConfig = player.config.pawn
	var exceeded := false
	for i in 200:
		await step(1)
		if zip.ride_speed() > cfg.ground_speed:
			exceeded = true
			break
	assert_true(exceeded, "test setup precondition: the ride never exceeded ground_speed")
	input.press_crouch()
	var landed := false
	for i in 200:
		await step(1)
		if player.grounded and player.move_manager.current_name == Move.WALKING:
			landed = true
			break
	assert_true(landed, "test setup: the body never landed")
	assert_true(player.speed_energy.cap() >= cfg.ground_speed - 0.01, \
		"landing off the cable did not restore the ground speed budget (cap=%.2f)" \
			% player.speed_energy.cap())

# --- the fall starts where the hands leave the cable -------------------------
#
# ✅ THE OWNER: 摔落高度从离开绳索那一刻开始计算. FallTracker measures depth below
# the last GROUND contact, and a zipline entered from a high platform never
# declares one of its own while riding -- so a long descending ride quietly
# racked up the whole cable's drop as "fall" before the hands ever let go.

func test_the_ride_does_not_accumulate_a_fall_while_still_on_the_cable() -> void:
	var player: Player = await _standing_player()
	# Descends well past hard_landing_height along its own run, which is
	# exactly the case that used to score a fall the instant it was caught.
	var drop: float = player.config.pawn.hard_landing_height + 2.0
	_line = _cable(Vector3(0.0, CABLE_Y, -1.0), Vector3(0.0, CABLE_Y - drop, 19.0))
	var input: ScriptedInputSource = _world["input"]
	input.press_jump()
	for i in 40:
		await step(1)
		if player.move_manager.current_name == Move.ZIPLINE:
			break
	assert_eq(player.move_manager.current_name, Move.ZIPLINE, "test setup: never caught the cable")
	var ticks_observed := 0
	for i in 90:
		await step(1)
		if player.move_manager.current_name != Move.ZIPLINE:
			break
		ticks_observed += 1
		assert_lt(player.fall_tracker.fall_height, 1.0, \
			"the ride's own descent accumulated as a fall while still on the cable")
	assert_gt(ticks_observed, 30, "test setup: the ride ended before the descent could be observed")

# --- the rope is visible, and F12 draws the rope, not the hang path ----------
#
# ✅ THE OWNER mistook the F12 hang-path line for the cable ("目前的实现是胶囊中心
# 点沿着绳索前进？") -- the capsule TOP rides the cable; sample() used to draw the
# HANG path (hang_offset below the wire, i.e. right where the body already is),
# so there was nothing new to see. F12 must draw the rope where it physically is.

func test_the_debug_line_draws_the_cable_hang_offset_above_the_body() -> void:
	var player: Player = await _riding_player()
	await step(12)  # past fade_in_time
	var zip: ZiplineMove = player.move_manager.move_for(Move.ZIPLINE)
	var drawn: Vector3 = zip.sample(zip.ride_offset() / _line.length())
	assert_almost_eq(drawn.y - player.global_position.y, player.config.zipline.hang_offset, 0.02, \
		"the debug line is not drawn hang_offset above the body")

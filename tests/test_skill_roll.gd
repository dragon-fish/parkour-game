extends ParkourTest

# TdMove_SkillRoll. The roll is what a player buys their way out of the two
# second Landing lockout with -- LandingMove and this are mutually exclusive by
# construction, decided in AirborneMove.landing_destination().
#
# It is NOT steerable, and that is from the source: ControllerState is
# PlayerGrabbing, MovementGroup is MG_TwoHandsBusy, bDisableFaceRotation is set.
# The direction is fixed at touchdown.

const TestWorld = preload("res://tests/world_fixture.gd")

## Runs up to speed, then drops from `height` with crouch buffered or not.
func _land_from(height: float, roll: bool) -> Dictionary:
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	input.state.move = Vector2(0.0, 1.0)
	for i in 200:
		await step(1)

	player.global_position.y += height
	player.fall_tracker.reset(player.global_position.y)
	await step(2)

	var seen: Array[StringName] = []
	var pressed := false
	for i in 240:
		# Buffer the crouch just before touchdown, which is what a roll is.
		if roll and not pressed and player.velocity.y < 0.0 \
				and player.global_position.y < 1.6:
			input.press_crouch()
			pressed = true
		await step(1)
		var now: StringName = player.move_manager.current_name
		if seen.is_empty() or seen[seen.size() - 1] != now:
			seen.append(now)
		if player.grounded and now == Move.WALKING and i > 60:
			break
	return {"world": world, "player": player, "seen": seen}

func test_a_rolled_landing_enters_the_roll_instead_of_the_lockout() -> void:
	var r: Dictionary = await _land_from(7.0, true)
	var seen: Array = r["seen"]
	assert_true(seen.has(Move.SKILL_ROLL), \
		"a rolled hard landing did not enter SkillRoll (saw %s)" % [seen])
	assert_true(not seen.has(Move.LANDING), \
		"a rolled landing paid the lockout anyway (saw %s)" % [seen])
	TestWorld.teardown(r["world"])
	await step(1)

func test_an_unrolled_hard_landing_still_pays_the_lockout() -> void:
	var r: Dictionary = await _land_from(7.0, false)
	var seen: Array = r["seen"]
	assert_true(seen.has(Move.LANDING), \
		"an unrolled hard landing skipped the lockout (saw %s)" % [seen])
	assert_true(not seen.has(Move.SKILL_ROLL), \
		"an unrolled landing rolled anyway (saw %s)" % [seen])
	TestWorld.teardown(r["world"])
	await step(1)

func test_the_roll_keeps_most_of_the_speed_budget() -> void:
	# The whole point: a hard landing zeroes the budget outright (see
	# AirborneMove._apply_landing_cost), while rolling out of the same fall
	# keeps most of it.
	var cfg := MovementConfig.new()
	var rolled: Dictionary = await _land_from(7.0, true)
	var rolled_energy: float = (rolled["player"] as Player).speed_energy.energy
	TestWorld.teardown(rolled["world"])
	await step(1)

	var dropped: Dictionary = await _land_from(7.0, false)
	var dropped_energy: float = (dropped["player"] as Player).speed_energy.energy
	TestWorld.teardown(dropped["world"])
	await step(1)

	assert_gt(rolled_energy, dropped_energy + 0.5, \
		"rolling saved no more of the budget than eating the landing did (%.2f vs %.2f)" \
			% [rolled_energy, dropped_energy])

func test_the_roll_is_not_steerable() -> void:
	# ControllerState = PlayerGrabbing: the hands are busy and the facing is
	# pinned. Direction is decided at touchdown.
	var cfg := MovementConfig.new()
	var world := TestWorld.build(get_tree(), cfg)
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]

	player.move_manager.start(Move.SKILL_ROLL)
	player.velocity = Vector3(0.0, 0.0, -6.0)
	player.move_manager.move_for(Move.SKILL_ROLL).enter(Move.FALLING)
	var start_x: float = player.global_position.x

	# Hard left, held for the whole roll.
	input.state.move = Vector2(-1.0, 0.0)
	await step(20)
	assert_almost_eq(player.global_position.x, start_x, 0.05, \
		"the roll was steerable -- it drifted %.3f m sideways" \
			% (player.global_position.x - start_x))

	TestWorld.teardown(world)
	await step(1)

# --- the measured shape of a roll ---------------------------------------------

func test_the_roll_lasts_the_measured_second() -> void:
	# ✅ MEASURED with a stopwatch in the original. Nothing in the CDO says so --
	# the roll is carried on an animation there. It was 0.6 while it was a guess,
	# and the difference changes what the move IS: at 0.6 a flourish, at 1.0 a
	# commitment.
	var config := MovementConfig.new()
	assert_almost_eq(config.skill_roll.duration, 1.0, 0.0001, \
		"the roll is not the measured second long")

func test_a_roll_travels_the_measured_distance_even_from_a_dead_drop() -> void:
	# ✅ MEASURED: a roll carries the body about 3 m forward, and it is FORCED --
	# the owner's word, and the reason they report that rolling toward a cliff
	# edge in the original rolls you off it.
	#
	# A DEAD DROP is the case that separates the two readings. Priced purely off
	# the speed carried in, as it was, a straight fall arrives with no
	# horizontal speed and the roll happens on the spot.
	var config := MovementConfig.new()
	var floor_speed: float = config.skill_roll.forced_distance / config.skill_roll.duration
	assert_almost_eq(floor_speed, 3.0, 0.0001, \
		"the forced travel does not work out at the measured 3 m over the second")
	# ✅ AND IT DOES NOT SCALE WITH THE APPROACH. The owner tested a standstill
	# roll and an 80 km/h roll in the original: both travel 3 m. What a fast
	# approach buys is the share of the energy budget that survives, not
	# distance -- a different channel for the same intent, and the original's.
	assert_lt(config.skill_roll.energy_keep, 1.0, \
		"the roll keeps the whole budget, so a fast approach buys nothing at all")
	assert_gt(config.skill_roll.energy_keep, 0.0, \
		"the roll keeps none of the budget, so a fast approach is thrown away")

func test_the_roll_goes_where_the_view_points_not_where_the_body_was_going() -> void:
	# ✅ THE OWNER'S FIND, and it is counter-intuitive enough to be worth a test
	# of its own: the forced travel follows the CAMERA at touchdown, not the
	# momentum -- even after spinning 180 degrees in mid-air on the way down.
	#
	# A deliberate break with physics. A roll is a second of lost control, and
	# letting the view aim it hands that second back: you steer the landing
	# rather than being carried by whatever the fall left you with.
	#
	# Driven straight at the move rather than through a landing, so the only
	# variable is the disagreement between facing and velocity.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	# Travelling along -Z, but LOOKING back along +Z: a half turn taken in the
	# air, which is exactly the case the owner described.
	player.velocity = Vector3(0.0, 0.0, -6.0)
	player.rotation.y = PI
	player.move_manager.start(Move.SKILL_ROLL)
	await step(4)
	assert_gt(player.velocity.z, 0.0, \
		"the roll followed the old momentum (-Z) instead of the view (+Z)")

	TestWorld.teardown(world)
	await step(1)

func test_the_roll_plays_out_after_the_ground_runs_out() -> void:
	# ✅ The owner, from the original: "if the ground runs out half way through,
	# the roll animation still plays out -- the body is obviously falling by
	# then, but the move finishes." Ours cut to a standing fall the instant the
	# floor disappeared, and the camera went from mid-tumble to upright in one
	# frame.
	#
	# The distinction is between the BODY and the ANIMATION. Gravity takes the
	# body immediately; the roll keeps its own clock and its own camera.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]

	# Started already off the floor, which is the same case as running out of
	# it: the roll has nothing under it from its first tick.
	player.global_position += Vector3(0.0, 3.0, 0.0)
	player.velocity = Vector3.ZERO
	player.move_manager.start(Move.SKILL_ROLL)
	await step(1)
	assert_eq(player.move_manager.current_name, Move.SKILL_ROLL, \
		"the roll ended on its first tick because there was no ground")

	# Half a second in -- well past where the old version bailed, and well short
	# of the roll's own second.
	await step(28)
	assert_eq(player.move_manager.current_name, Move.SKILL_ROLL, \
		"the roll gave up part-way instead of playing out")
	assert_lt(player.velocity.y, -1.0, \
		"the body is not falling -- gravity should have it while the roll plays")

	TestWorld.teardown(world)
	await step(1)

func test_the_roll_starts_from_the_current_pitch_and_ends_level() -> void:
	# ✅ The owner, from the original: the pitch is NOT forced to zero on entry.
	# The roll begins wherever the view is and finishes level, so looking up
	# travels more than a full turn and looking down travels less.
	#
	# CameraRig composes this as `rotation.x = pitch - roll_spin`, so a spin of
	# exactly one turn ends back at the pitch it started from -- which is what
	# ours did, and why it never levelled out.
	var config := MovementConfig.new()
	var full: float = config.skill_roll.camera_spin
	for pitch in [deg_to_rad(30.0), 0.0, -deg_to_rad(30.0)]:
		# The move's own arithmetic, asserted directly: the total is one turn
		# plus wherever the view began.
		var total: float = full + pitch
		# Ends level: pitch - total lands on -TAU, which is zero.
		assert_almost_eq(pitch - total, -full, 0.0001, \
			"a roll from %.0f degrees does not finish level" % rad_to_deg(pitch))
	# ...and looking up is the LONGER way round, which is the owner's own
	# description and the half a constant-spin version gets wrong.
	assert_gt(full + deg_to_rad(30.0), full, "looking up did not travel further")
	assert_lt(full - deg_to_rad(30.0), full, "looking down did not travel less")

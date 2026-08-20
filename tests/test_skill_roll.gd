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

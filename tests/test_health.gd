extends ParkourTest

# [13] Every number here was measured off the original's HUD. What is asserted
# is the SHAPE -- flat damage, a delay in front of a flat climb, one death
# test -- not the values, which are dials.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _pawn() -> PawnConfig:
	return MovementConfig.new().pawn

func test_a_fresh_body_is_whole() -> void:
	var pawn := _pawn()
	assert_eq(Health.new(pawn).hp, pawn.max_health, "a new body did not start full")

func test_regeneration_waits_out_the_delay_and_then_is_flat() -> void:
	# The delay is not dead time: it IS the window in which the wounded
	# picture is visible, because the climb back is only two seconds wide.
	var pawn := _pawn()
	var health := Health.new(pawn)
	health.damage(90.0, Health.Cause.HAZARD)
	health.tick(pawn.health_regen_delay)
	assert_almost_eq(health.hp, pawn.max_health - 90.0, 0.001, \
		"health came back before the delay was up")
	# Past it, one second buys exactly the rate and not a point more.
	var before: float = health.hp
	health.tick(1.0)
	assert_almost_eq(health.hp - before, pawn.health_regen_rate, 0.001, \
		"the climb back is not flat")

func test_the_tick_that_crosses_the_delay_only_heals_its_far_half() -> void:
	# Straddling the boundary is not an edge case: it happens exactly once
	# per wound. Healing for the whole step would pay out the delay itself.
	var pawn := _pawn()
	var health := Health.new(pawn)
	health.damage(90.0, Health.Cause.HAZARD)
	health.tick(pawn.health_regen_delay + 1.0)
	assert_almost_eq(health.hp, pawn.max_health - 90.0 + pawn.health_regen_rate, 0.001, \
		"a step across the boundary healed for its whole length")

func test_a_second_hit_restarts_the_wait() -> void:
	var pawn := _pawn()
	var health := Health.new(pawn)
	health.damage(50.0, Health.Cause.HAZARD)
	health.tick(pawn.health_regen_delay * 0.9)
	health.damage(10.0, Health.Cause.HAZARD)
	health.tick(pawn.health_regen_delay * 0.9)
	assert_almost_eq(health.hp, pawn.max_health - 60.0, 0.001, \
		"the second hit did not restart the wait")

func test_health_is_not_clamped_at_zero() -> void:
	# [13.1] The original reads -900 on the HUD after walking into a boundary
	# volume. A clamp would hide how heavy a blow was at the one moment that
	# is worth knowing.
	var pawn := _pawn()
	var health := Health.new(pawn)
	health.damage(pawn.lethal_volume_damage, Health.Cause.VOLUME)
	assert_lt(health.hp, 0.0, "the bar was clamped, so a thousand looks like a hundred")

func test_the_dead_take_no_further_damage_and_die_once() -> void:
	var pawn := _pawn()
	var health := Health.new(pawn)
	assert_true(health.damage(pawn.max_health, Health.Cause.FALL), "the killing blow was not reported")
	var at_death: float = health.hp
	assert_false(health.damage(50.0, Health.Cause.HAZARD), "a corpse died a second time")
	assert_eq(health.hp, at_death, "a corpse kept taking damage")

func test_the_dead_do_not_heal() -> void:
	var pawn := _pawn()
	var health := Health.new(pawn)
	health.damage(pawn.max_health, Health.Cause.FALL)
	health.tick(pawn.health_regen_delay + 5.0)
	assert_true(health.is_dead(), "a corpse regenerated back to life")

func test_a_fatal_fall_costs_exactly_a_full_bar() -> void:
	# [13.2] Which is what lets a death at full health and one already wounded
	# be the same arithmetic, with no "a fall is always fatal" special case.
	var pawn := _pawn()
	assert_eq(pawn.fatal_fall_damage, pawn.max_health, \
		"a fatal fall stopped being exactly a full bar, so the fall now needs a special case")

# The wiring: which sources charge what, and that a death is declared once.

func _settled() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(30)
	return world

func test_a_roll_pays_nothing_and_a_missed_roll_pays_the_flat_fee() -> void:
	# [ME:CONFIRMED 03 §3.1] The fee does not scale with height, so the player
	# never has to estimate how bad a landing was. Asserted through the move's
	# own accessor rather than by dropping a body, because what is being
	# checked is the rule, not the physics that reaches it.
	var world := await _settled()
	var player: Player = world["player"]
	var falling: FallingMove = player.move_manager.move_for(Move.FALLING)
	var cfg := player.config
	var deep: float = cfg.pawn.hard_landing_height + 4.0
	assert_eq(falling.landing_damage(deep, false), cfg.landing.hard_landing_damage, \
		"a missed roll cost nothing")
	assert_eq(falling.landing_damage(deep * 2.0, false), cfg.landing.hard_landing_damage, \
		"the fee scaled with height")
	assert_eq(falling.landing_damage(deep, true), 0.0, "a roll was charged anyway")
	assert_eq(falling.landing_damage(cfg.pawn.hard_landing_height - 0.1, false), 0.0, \
		"a landing short of the threshold was charged")

func test_a_pad_charges_nothing_though_the_lockout_still_runs() -> void:
	var world := await _settled()
	var player: Player = world["player"]
	var soft: SoftLandingMove = player.move_manager.move_for(Move.SOFT_LANDING)
	assert_eq(soft.landing_damage(100.0, false), 0.0, "the pad billed for the fall it caught")

func test_a_lethal_volume_takes_ten_bars_and_kills() -> void:
	var world := await _settled()
	var player: Player = world["player"]
	player.die_in_volume()
	assert_true(player.health.is_dead(), "a lethal volume was survived")
	assert_eq(player.health.last_cause, Health.Cause.VOLUME, "the death read as something else")
	assert_lt(player.health.hp, -player.config.pawn.max_health, \
		"a lethal volume charged something a body could plausibly have")

func test_the_death_is_announced_once_and_not_again() -> void:
	# _observe_death() runs every tick, so a body left below zero would keep
	# announcing. What stops it is the level respawning -- and, until it does,
	# the sequence having set _dying.
	var world := await _settled()
	var player: Player = world["player"]
	var deaths := [0]
	player.died.connect(func() -> void: deaths[0] += 1)
	player.take_damage(player.config.pawn.max_health, Health.Cause.HAZARD)
	await step(1)
	assert_eq(deaths[0], 1, "the death was not announced")
	player.set_dying(true)
	await step(20)
	assert_eq(deaths[0], 1, "a body already dying announced its death again")
	player.set_dying(false)

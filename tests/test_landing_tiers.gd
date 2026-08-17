class_name TestLandingTiers
extends TestCase

# The four-tier landing table (03 §3.1), stated as behaviour. Tier boundaries
# are fall HEIGHTS, not impact speeds -- that difference is the point.

func _player_stub() -> Player:
	var player := Player.new()
	player.config = MovementConfig.new()
	return player

func test_a_flat_jump_lands_in_the_free_tier() -> void:
	# The calibration this whole task exists for: base_jump_z 5.6 against
	# gravity 8.0 peaks at 1.96 m, four centimetres under the 2.0 m roll
	# threshold, so an ordinary jump can never cost speed.
	var player := _player_stub()
	var pawn := player.config.pawn
	var apex: float = pawn.base_jump_z * pawn.base_jump_z / (2.0 * pawn.gravity)
	check_approx(apex, 1.96, 0.005, "the jump arc is not the confirmed one")
	check(apex < pawn.skill_roll_landing_height, "a flat jump reaches the roll threshold")
	check(player.landing_tier(apex) == Player.TIER_FREE, "a flat jump is not in the free tier")
	check_approx(player.landing_keep_ratio(apex, false), 1.0, 0.0001, "a flat jump cost speed")
	player.free()

func test_the_free_tier_costs_nothing_at_all() -> void:
	# Not "costs a little" -- the original has a genuinely free band, which
	# the old continuous ramp from zero did not.
	var player := _player_stub()
	check_approx(player.landing_keep_ratio(1.99, false), 1.0, 0.0001, "the free band is not free")
	check_approx(player.landing_keep_ratio(0.2, false), 1.0, 0.0001, "a curb cost speed")
	player.free()

func test_a_roll_fully_negates_a_soft_landing() -> void:
	var player := _player_stub()
	check(player.landing_tier(2.5) == Player.TIER_SOFT, "2.5 m is not the soft tier")
	check(player.landing_keep_ratio(2.5, false) < 1.0, "an unrolled soft landing was free")
	check_approx(player.landing_keep_ratio(2.5, true), 1.0, 0.0001, "a rolled soft landing still cost speed")
	player.free()

func test_a_roll_only_softens_the_rollable_tier() -> void:
	# Community consensus (03 §3.1): ME1's skill roll bleeds speed of its own
	# when you keep moving forward out of it, so a roll above the soft band is
	# a discount, never a cancellation.
	var player := _player_stub()
	check(player.landing_tier(4.0) == Player.TIER_ROLLABLE, "4.0 m is not the rollable tier")
	var rolled := player.landing_keep_ratio(4.0, true)
	var unrolled := player.landing_keep_ratio(4.0, false)
	check_greater(rolled, unrolled, "rolling did not help")
	check(rolled < 1.0, "a roll fully cancelled a rollable-tier landing")
	player.free()

func test_a_hard_landing_keeps_only_the_reduction_share() -> void:
	var player := _player_stub()
	check(player.landing_tier(6.0) == Player.TIER_HARD, "6.0 m is not the hard tier")
	check_approx(player.landing_keep_ratio(6.0, false), 0.35, 0.0001, "hard landing keep ratio is wrong")
	player.free()

func test_no_tier_can_ever_add_speed() -> void:
	# The F1 panel sizes every slider to three times its default, so any keep
	# ratio is draggable past 1.0. A landing may cost speed or cost nothing;
	# it must never be a source of it.
	var player := _player_stub()
	player.config.pawn.landing_speed_reduction = -5.0
	for height in [0.5, 2.5, 4.0, 9.0]:
		check(player.landing_keep_ratio(height, false) <= 1.0, \
			"a landing at %f m added speed" % height)
		check(player.landing_keep_ratio(height, true) <= 1.0, \
			"a rolled landing at %f m added speed" % height)
	player.free()

class_name TestLandingTiers
extends TestCase

# The four-tier landing table (03 §3.1), stated as behaviour. Tier boundaries
# are fall HEIGHTS, not impact speeds -- that difference is the point.

func _player_stub() -> Player:
	var player := Player.new()
	player.config = MovementConfig.new()
	return player

func test_a_flat_jump_lands_in_the_free_tier() -> void:
	# The calibration this whole task exists for: an ordinary jump must never
	# cost speed. Measured (02 §2.4), base_jump_z 6.3 against gravity 16.0
	# peaks at 1.24 m -- 38% under the 2.0 m roll threshold.
	#
	# The margin used to read "four centimetres", which was taken as evidence of
	# deliberate tuning by DICE. That reading was an artefact of the wrong
	# gravity: under the measured values the gap is comfortable, not hairline.
	var player := _player_stub()
	var pawn := player.config.pawn
	var apex: float = pawn.base_jump_z * pawn.base_jump_z / (2.0 * pawn.gravity)
	check_approx(apex, 1.2403, 0.005, "the jump arc is not the measured one")
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

func test_everything_below_the_hard_threshold_is_free() -> void:
	# ✅ MEASURED (03 §3.1). Dropping 4.95 m WITHOUT rolling costs nothing at all
	# -- speed keeps climbing after touchdown. 5.69 m triggers Landing. So the
	# only speed gate is hard_landing_height (5.3 m); skill_roll_landing_height
	# and soft_landing_height govern animation and whether a roll may trigger,
	# never speed.
	#
	# This replaces a modelled ramp in which 2.5 m cost a little and 4.0 m cost
	# more. That ramp was plausible and wrong: the original has no partial band.
	var player := _player_stub()
	for height in [0.2, 1.99, 2.5, 4.0, 4.95, 5.29]:
		check_approx(player.landing_keep_ratio(height, false), 1.0, 0.0001, 			"an unrolled landing at %f m cost speed" % height)
		check_approx(player.landing_keep_ratio(height, true), 1.0, 0.0001, 			"a rolled landing at %f m cost speed" % height)
	player.free()

func test_a_hard_landing_without_a_roll_costs_everything() -> void:
	# ✅ MEASURED: ~7 m unrolled zeroes the speed outright and plays the knee-
	# clutch animation. Not "keeps 35%" -- the loss is total.
	var player := _player_stub()
	check(player.landing_tier(6.0) == Player.TIER_HARD, "6.0 m is not the hard tier")
	check_approx(player.landing_keep_ratio(6.0, false), 0.0, 0.0001, 		"a hard landing left speed behind")
	check_approx(player.landing_keep_ratio(9.0, false), 0.0, 0.0001, 		"a hard landing left speed behind")
	player.free()

func test_a_roll_cancels_a_hard_landing_completely() -> void:
	# ✅ MEASURED: rolling out of a ~7 m drop returns to the entry speed within
	# the roll animation. The roll is not a discount -- above the threshold it is
	# the difference between keeping everything and keeping nothing.
	var player := _player_stub()
	check_approx(player.landing_keep_ratio(6.0, true), 1.0, 0.0001, 		"a rolled hard landing still cost speed")
	player.free()

func test_no_tier_can_ever_add_speed() -> void:
	# The F1 panel sizes every slider to three times its default, so any keep
	# ratio is draggable past 1.0. A landing may cost speed or cost nothing;
	# it must never be a source of it.
	var player := _player_stub()
	for height in [0.5, 2.5, 4.0, 9.0]:
		check(player.landing_keep_ratio(height, false) <= 1.0, \
			"a landing at %f m added speed" % height)
		check(player.landing_keep_ratio(height, true) <= 1.0, \
			"a rolled landing at %f m added speed" % height)
	player.free()

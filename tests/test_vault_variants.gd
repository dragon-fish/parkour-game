class_name TestVaultVariants
extends TestCase

# The variant table, tested as a lookup. 05 §5.7 is the source; the five
# discriminating axes are height, whether there is a far side, vertical speed
# direction, horizontal momentum, and the time-to-obstacle window.

func _cfg() -> SpeedVaultConfig:
	return MovementConfig.new().speed_vault

func test_the_table_has_all_six_confirmed_variants() -> void:
	var names := PackedStringArray()
	for v in _cfg().variants:
		names.append(v["name"])
	for expected in ["auto_step_up_right_leg", "step_up_right_leg_88", "vault_onto", \
			"vault_over", "vault_over_high", "vault_onto_high"]:
		check(names.has(expected), "variant %s missing from the table" % expected)

func test_running_fast_at_a_sweet_spot_obstacle_earns_speed() -> void:
	# The reason the move is called SpeedVault: speed is the key that unlocks
	# the better animation, and the better animation pays a bonus.
	var variant := _cfg().pick_variant(1.0, true, 0.0, 6.0)
	check(variant.has("name"), "no variant matched a fast sweet-spot approach")
	check(variant["name"] == "vault_over", "a fast approach did not pick vault_over")
	check_greater(variant["speed_addition"], 0.0, "the sweet spot did not pay a bonus")

func test_walking_at_the_same_obstacle_picks_the_slow_climb() -> void:
	# Same height, same geometry -- only the momentum differs, and the
	# original resolves that into a different animation with no bonus.
	var variant := _cfg().pick_variant(1.0, true, 1.0, 1.5)
	check(variant.has("name"), "no variant matched a slow approach")
	check(variant["name"] == "step_up_right_leg_88", "a slow approach did not pick the climb")
	check_approx(variant["speed_addition"], 0.0, 0.0001, "the slow climb paid a bonus")

func test_a_high_obstacle_requires_already_being_on_the_way_up() -> void:
	# MinSpeedZ = 50: the high variants only trigger while still RISING, which
	# is what makes "you have to jump at tall things" a rule the player can
	# internalise instead of an autograb.
	var cfg := _cfg()
	check(not cfg.pick_variant(1.7, false, -1.0, 6.0).has("name"), \
		"a high obstacle matched while descending")
	check(cfg.pick_variant(1.7, false, 2.0, 6.0).has("name"), \
		"a high obstacle did not match while rising")

func test_a_high_obstacle_clamps_speed_down() -> void:
	var variant := _cfg().pick_variant(1.7, false, 2.0, 7.0)
	check(variant["clamp_speed_max"] < 7.0, "the high variant did not clamp speed down")
	check_greater(variant["duration"], 1.0, "the high variant is not markedly slower")

func test_nothing_matches_above_the_tables_own_ceiling() -> void:
	# Past 1.92 m the original leaves VaultTypes entirely and goes down the
	# wall-climb / grab / pull-up chain instead.
	check(not _cfg().pick_variant(2.5, false, 2.0, 7.0).has("name"), \
		"an out-of-range obstacle matched a vault variant")

func test_the_lookahead_window_is_time_not_distance() -> void:
	# The property that makes "faster feels smoother" fall out for free: the
	# same 0.4 s window is 1.6 m at 4 m/s and 2.88 m at 7.2 m/s.
	var cfg := _cfg()
	var variant := cfg.pick_variant(1.0, true, 0.0, 6.0)
	check(cfg.should_commit(2.0, 7.2, variant), "a fast approach did not commit at 2.0 m")
	check(not cfg.should_commit(2.0, 4.0, variant), "a slow approach committed at 2.0 m anyway")

func test_a_stationary_approach_never_commits() -> void:
	# distance / speed must not divide by zero into an infinite lookahead.
	var cfg := _cfg()
	var variant := cfg.pick_variant(1.0, true, 0.0, 6.0)
	check(not cfg.should_commit(1.0, 0.0, variant), "a standstill committed to a vault")

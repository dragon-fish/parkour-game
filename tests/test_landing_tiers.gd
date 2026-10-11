extends ParkourTest

# [ME:CONFIRMED 03 §3.1] The landing heights, stated as behaviour. Tier
# boundaries are fall HEIGHTS, not impact speeds -- that difference is the
# point. What a landing costs is LandingMove's (test_port_core.gd).

func _player_stub() -> Player:
	var player := Player.new()
	player.config = MovementConfig.new()
	return player

func test_a_flat_jump_lands_in_the_free_tier() -> void:
	# [ME:CONFIRMED 02 §2.4, emulated 15.7] BaseJumpZ 630 uu/s against the
	# falling integrator's doubled gravity peaks at 1.24 m, 38% under the
	# 2.0 m roll threshold.
	var player := _player_stub()
	var pawn := player.config.pawn
	var apex: float = pawn.base_jump_z * pawn.base_jump_z / (2.0 * pawn.gravity)
	assert_almost_eq(apex, 1.2403, 0.005, "the jump arc is not the measured one")
	assert_true(apex < pawn.skill_roll_landing_height, "a flat jump reaches the roll threshold")
	assert_true(player.landing_tier(apex) == Player.TIER_FREE, "a flat jump is not in the free tier")
	player.free()

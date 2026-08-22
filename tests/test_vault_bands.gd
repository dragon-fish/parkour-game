extends ParkourTest

# Which manoeuvre a height gets, and where the hand comes into it.
#
# ✅ THE OWNER: "a lot of heights that visually just need a step get the hand
# plant instead, and the hand is nowhere near the surface."
#
# ⚠️ A DIVERGENCE FROM THE TRANSCRIPTION, deliberately. 05 §5.7's raw CDO
# figure for the hand-planted rows is 64 uu = 0.64 m, but the classification
# rule 05 §27 converged on is not a height at all -- it is a place on the BODY:
# "hands above the waist, thin things get crossed". The waist is 0.9 m, the same
# figure crouch_capsule_height uses.
#
# The CDO also caps the step-up row at MaxMomentum = 200, i.e. a slow approach
# only. Combined with the plant starting at 0.64, that left a RUNNING player no
# way to step up anything at all -- every obstacle above the shin got a hand.

func _variant(height: float, speed_xy: float, rising: bool = true) -> String:
	var cfg := SpeedVaultConfig.new()
	# vault_over is admissible for a thin obstacle, which is the common case
	# and the one the owner is describing.
	var v: Dictionary = cfg.pick_variant(height, true, 1.0 if rising else -1.0, speed_xy)
	return String(v.get("name", ""))

func test_a_knee_high_obstacle_is_stepped_over_at_running_speed() -> void:
	# THE REPORTED CASE. Below the waist, at pace, jumping into it.
	assert_eq(_variant(0.6, 6.0), "step_up_right_leg_88",
		"a 0.60 m obstacle at 6 m/s resolved to '%s'" % _variant(0.6, 6.0))

func test_the_hand_comes_in_at_the_waist() -> void:
	assert_eq(_variant(0.95, 6.0), "vault_over",
		"a 0.95 m obstacle at 6 m/s resolved to '%s'" % _variant(0.95, 6.0))

func test_the_band_below_the_waist_belongs_to_the_step_up_at_any_speed() -> void:
	# The CDO's MaxMomentum = 200 made this row unreachable above walking pace,
	# which is what left the gap. Its whole job now is to own this band.
	for speed in [1.0, 3.0, 5.0, 7.2]:
		assert_eq(_variant(0.7, speed), "step_up_right_leg_88",
			"a 0.70 m obstacle at %.1f m/s resolved to '%s'"
			% [speed, _variant(0.7, speed)])

func test_the_high_tiers_are_untouched() -> void:
	# Nothing above the middle band moved, and the two-handed rows still ask for
	# a real jump.
	assert_eq(_variant(1.6, 6.0), "vault_over_high",
		"a 1.60 m obstacle resolved to '%s'" % _variant(1.6, 6.0))

func test_a_shin_high_lip_is_still_the_descending_rescue() -> void:
	# The bottom band did not move either: auto_step_up owns 0 to 0.48, and
	# only while falling.
	assert_eq(_variant(0.3, 2.0, false), "auto_step_up_right_leg",
		"a 0.30 m lip resolved to '%s'" % _variant(0.3, 2.0, false))

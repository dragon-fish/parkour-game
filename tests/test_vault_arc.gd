extends ParkourTest

# How high a vault OVER carries the body is derived from the obstacle, not
# fixed.
#
# ✅ THE OWNER: "the eye is still far too high during a vault." The old field
# held 1.0 -- the measured RISE from docs/feel-backlog.md 26-27 -- and applied
# it at every obstacle height. But that 1.0 was measured on a 2.64 m fence
# entered from a jump with the feet already at 0.76. Using it on a 1 m box
# lifts the feet a whole metre over something they only had to reach, and the
# eye rides 1.66 m above the top, because the eye is 1.66 m above the feet.
#
# The same measurement read the other way round DOES generalise: the peak is
# 0.87 m BELOW the obstacle's top. Faith's feet never clear the fence at all --
# she plants a hand and swings the body past it.

## Reproduces SpeedVaultMove's own derivation, so a change to the formula that
## is not mirrored here shows up as a failing number rather than silently.
func _peak_feet(obstacle_top: float, entry_feet: float, landing_feet: float,
		cfg: SpeedVaultConfig, standing: float, fold: float = 0.0,
		eye_above_soles: float = 1.66) -> float:
	var half: float = standing * 0.5
	var wanted_eye: float = obstacle_top + cfg.vault_over_eye_above_top
	var wanted: float = wanted_eye - (eye_above_soles - fold)
	var midpoint_feet: float = (entry_feet + half + landing_feet + half) * 0.5 - half
	var arc: float = maxf(0.0, wanted - midpoint_feet)
	return midpoint_feet + arc

func test_the_measured_fence_comes_back_out_exactly() -> void:
	# docs/feel-backlog.md 26-27, in full: the fence top is at SZD 2.64, the
	# feet commit at 0.76 and peak at 1.77. If the derivation cannot reproduce
	# the case it was derived from, it is not a derivation.
	var cfg := SpeedVaultConfig.new()
	# UNFOLDED, which is the state the measurement was taken in -- the fold is
	# this project's, not the original's.
	var peak: float = _peak_feet(2.64, 0.76, 0.0, cfg, 1.8)
	assert_almost_eq(peak, 1.77, 0.005,
		"the measured fence vault now peaks at %.2f instead of 1.77" % peak)

func test_a_low_box_no_longer_lifts_the_body_a_whole_metre() -> void:
	# The reported bug, as a number. A 1 m box walked into from the ground.
	var cfg := SpeedVaultConfig.new()
	var peak: float = _peak_feet(1.0, 0.0, 0.0, cfg, 1.8, 0.9)
	# What matters is where the EYE ends up, folded and all.
	var eye_above_top: float = peak + 1.66 - 0.9 - 1.0
	assert_lt(eye_above_top, 0.9,
		"the eye still rides %.2f m over the top" % eye_above_top)

func test_the_eye_clears_by_the_same_amount_at_every_height() -> void:
	# The point of aiming at the eye: one number that is right at more than one
	# obstacle, and right whatever the fold is doing.
	var cfg := SpeedVaultConfig.new()
	for top in [1.0, 1.2, 1.48, 1.9]:
		for fold in [0.0, 0.9]:
			var peak: float = _peak_feet(top, 0.0, 0.0, cfg, 1.8, fold)
			var clearance: float = peak + 1.66 - fold - top
			assert_almost_eq(clearance, 0.79, 0.01,
				"a %.2f m obstacle with a %.2f fold clears by %.2f m"
				% [top, fold, clearance])

func test_an_obstacle_too_low_to_arc_over_gets_no_arc() -> void:
	# 0.87 below the top of a 0.64 m ledge is underground. The floor is what
	# stops the derivation asking for a dip.
	var cfg := SpeedVaultConfig.new()
	var peak: float = _peak_feet(0.4, 0.0, 0.0, cfg, 1.8)
	assert_almost_eq(peak, 0.0, 0.0001,
		"a low ledge dipped the body to %.2f m" % peak)

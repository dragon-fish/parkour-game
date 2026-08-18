class_name TestSpeedEnergy
extends TestCase

# Pure logic, no physics world. This is the one layer of the rebuild that can
# be fully verified without a human playing the game, so it is tested hard.

func _pawn() -> PawnConfig:
	return PawnConfig.new()

func test_the_curve_passes_through_every_confirmed_knot() -> void:
	var pawn := _pawn()
	for knot in pawn.speed_curve:
		check_approx(SpeedEnergy.curve_at(pawn, knot.x), knot.y, 0.0001, \
			"LINEAR curve misses the confirmed knot at E=%f" % knot.x)

func test_the_smooth_curve_also_passes_through_every_confirmed_knot() -> void:
	# This is the guard against the fitted coefficients silently drifting away
	# from the knots -- see speed_curve_smooth_fit's own note.
	var pawn := _pawn()
	pawn.speed_curve_interp_mode = 1
	for knot in pawn.speed_curve:
		check_approx(SpeedEnergy.curve_at(pawn, knot.x), knot.y, 0.001, \
			"SMOOTH curve misses the confirmed knot at E=%f" % knot.x)

func test_the_curve_is_flat_past_its_last_knot() -> void:
	var pawn := _pawn()
	check_approx(SpeedEnergy.curve_at(pawn, 20.0), 7.2, 0.0001, "curve kept climbing past E=7")

func test_the_cap_never_exceeds_ground_speed_in_either_mode() -> void:
	# SMOOTH's own asymptote is 7.556, above ground_speed, so the clamp is
	# load-bearing rather than defensive.
	var pawn := _pawn()
	pawn.speed_curve_interp_mode = 1
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 100.0
	check_approx(energy.cap(), 7.2, 0.0001, "SMOOTH cap escaped ground_speed")

func test_the_cap_never_drops_below_the_base_velocity_floor() -> void:
	# The curve's own v(0) is 0, which would freeze a standing start solid.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 0.0
	check_approx(energy.cap(), pawn.speed_min_base_velocity, 0.0001, "no floor under the cap")

func test_ordinary_running_reaches_the_top_of_the_curve_in_seven_seconds() -> void:
	# The single most-cited property of the original's speed system: 7 seconds
	# from a standstill to full speed. Sprint factor / sprint factor = 1.0, so
	# one second of running is one unit of energy, and the curve's X axis is
	# in seconds by construction.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	for i in 420:
		energy.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
	check_approx(energy.cap(), 7.2, 0.01, "seven seconds of running did not reach top speed")

func test_energy_is_more_than_half_spent_in_the_first_four_tenths_of_a_second() -> void:
	# The curve's shape, stated as behaviour: 55% of the final speed arrives
	# in the first 0.4 s and the remaining 45% takes the other 6.6.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	for i in 24:
		energy.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
	check_greater(energy.cap(), 7.2 * 0.5, "the opening of the curve is not steep enough")
	check(energy.cap() < 7.2 * 0.6, "the opening of the curve overshot its 55% share")

func test_strafing_and_walking_bank_energy_more_slowly_than_running() -> void:
	var pawn := _pawn()
	var run := SpeedEnergy.new(pawn)
	var strafe := SpeedEnergy.new(pawn)
	var walk := SpeedEnergy.new(pawn)
	for i in 60:
		run.accumulate(1.0 / 60.0, SpeedEnergy.SPRINT)
		strafe.accumulate(1.0 / 60.0, SpeedEnergy.STRAFE)
		walk.accumulate(1.0 / 60.0, SpeedEnergy.WALK)
	check_greater(run.energy, strafe.energy, "strafing banked energy as fast as running")
	check_greater(strafe.energy, walk.energy, "walking banked energy as fast as strafing")
	check_approx(strafe.energy, 10.0 / 30.0, 0.001, "strafe factor is not 10/30 per second")
	check_approx(walk.energy, 7.0 / 30.0, 0.001, "walk factor is not 7/30 per second")

func test_a_full_energy_budget_decays_to_nothing_in_three_seconds() -> void:
	# SpeedEnergyDecelerationTime = 3, with the 0.5 exponent taken literally:
	# dE/dt = -k * sqrt(E), k solved so a full budget empties in exactly T.
	# Integrated with explicit Euler at the physics tick rate; the expected
	# values below were measured against that integration, not against the
	# closed form (Euler runs slightly ahead of it because |dE/dt| shrinks
	# within each step).
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	for i in 150:
		energy.decay(1.0 / 60.0)
	check_approx(energy.energy, 0.183, 0.02, "decay at 2.5 s is off the measured curve")
	for i in 30:
		energy.decay(1.0 / 60.0)
	check_approx(energy.energy, 0.0, 0.001, "a full budget did not empty in three seconds")

func test_decay_is_fast_at_first_and_slow_near_zero() -> void:
	# The shape the research describes in words. Half the elapsed time must
	# take far more than half the energy.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	for i in 90:
		energy.decay(1.0 / 60.0)
	check(energy.energy < 7.0 * 0.3, "half the decay window did not take most of the energy")
	check_greater(energy.energy, 0.0, "decay reached zero too early")

func test_energy_never_goes_negative() -> void:
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 0.5
	for i in 600:
		energy.decay(1.0 / 60.0)
	check_approx(energy.energy, 0.0, 0.0001, "energy went negative")

func test_a_full_reversal_spends_the_entire_budget() -> void:
	# The calibration the turn cost is set from: the original's own
	# SpeedTurnDecelerationFactor = 10 has an unrecoverable unit, so the knob
	# is pinned to a stated behaviour instead.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	# Stated at the curve's neutral rate (450 deg/s), so this pins the BUDGET
	# calibration without also pinning the rate gradient: 180 degrees swung at
	# 450 deg/s takes 0.4 s. See pawn.turn_rate_cost_curve.
	energy.spend_turn(PI, 0.4)
	check_approx(energy.energy, 0.0, 0.02, "a 180 degree reversal did not spend the budget")

func test_a_quarter_turn_costs_half_the_budget() -> void:
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	# 90 degrees at the neutral 450 deg/s is 0.2 s -- same reasoning as the
	# reversal test above.
	energy.spend_turn(PI * 0.5, 0.2)
	check_approx(energy.energy, 3.5, 0.02, "a 90 degree turn did not cost half the budget")

func test_turning_has_no_free_allowance() -> void:
	# 10.1 ③: the research found no "costs nothing below N degrees" threshold
	# parameter anywhere, which is what makes turning a continuous tax rather
	# than a gate. A tiny turn must still cost something.
	var pawn := _pawn()
	var energy := SpeedEnergy.new(pawn)
	energy.energy = 7.0
	energy.spend_turn(deg_to_rad(1.0), 1.0 / 60.0)
	check(energy.energy < 7.0, "a small turn was free")

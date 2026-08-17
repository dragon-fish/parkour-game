class_name SpeedEnergy
extends RefCounted

# The original's two-layer speed model (02 §2.5), which is the single largest
# source of its feel:
#
#   layer 1 (fast): actual speed --accel_rate--> the current cap
#   layer 2 (slow): the cap      <--speed_curve(energy)-- speed energy
#
# The player's input drives layer 2. Layer 1 only keeps the body glued to
# whatever ceiling layer 2 currently allows. Collapsing the two into one --
# which is what a constant ground_speed does -- is exactly what makes speed
# stop being an asset worth protecting.
#
# Deliberately RefCounted, not a Node: nothing here touches the scene tree,
# which is what lets the whole layer be tested without a physics world.

## Which accumulation factor is in force this tick. The original declares
## three (02 §2.1, all ✅ as values, ⚠️ as direction).
enum { WALK, STRAFE, SPRINT }

var energy: float = 0.0

var _pawn: PawnConfig

func _init(pawn: PawnConfig) -> void:
	_pawn = pawn

func reset() -> void:
	energy = 0.0

## The ground speed ceiling for the current energy, clamped into
## [speed_min_base_velocity, ground_speed]. The upper clamp is load-bearing
## in SMOOTH mode, whose own asymptote (A + B = 7.556) sits above
## ground_speed; the lower one keeps a standing start from being frozen at
## the curve's own v(0) = 0.
func cap() -> float:
	return clampf(curve_at(_pawn, energy), _pawn.speed_min_base_velocity, _pawn.ground_speed)

## Evaluates the speed curve at `e`. Static and taking the config explicitly
## so tests (and the arena builder) can ask about a curve without owning an
## energy budget.
static func curve_at(pawn: PawnConfig, e: float) -> float:
	if pawn.speed_curve_interp_mode == 1:
		var f := pawn.speed_curve_smooth_fit
		return f.x * (1.0 - exp(-e / f.y)) + f.z * (1.0 - exp(-e / f.w))
	var knots := pawn.speed_curve
	if knots.is_empty():
		return 0.0
	if e <= knots[0].x:
		return knots[0].y
	for i in range(1, knots.size()):
		var a := knots[i - 1]
		var b := knots[i]
		if e <= b.x:
			var span := b.x - a.x
			if span <= 0.0:
				return b.y
			return a.y + (b.y - a.y) * ((e - a.x) / span)
	# Past the last knot the original holds its final value rather than
	# extrapolating -- GroundSpeed IS the curve's ceiling (02 §2.1).
	return knots[knots.size() - 1].y

## One tick of running banks (active factor / sprint factor) seconds of
## energy, so ordinary running is 1.0 and the curve's X axis is literally
## seconds-of-running. Callers are responsible for the
## energy_accumulate_speed_ratio gate -- see Player, which owns the speed
## reading this class deliberately does not.
func accumulate(delta: float, mode: int) -> void:
	var sprint: float = maxf(_pawn.speed_sprint_velocity_acceleration_factor, 0.001)
	var factor: float = sprint
	match mode:
		WALK:
			factor = _pawn.speed_walk_velocity_acceleration_factor
		STRAFE:
			factor = _pawn.speed_strafe_velocity_acceleration_factor
	energy = minf(energy + delta * (factor / sprint), _energy_ceiling())

## dE/dt = -k * E^exponent, with k solved so a FULL budget empties in exactly
## speed_energy_deceleration_time. Explicit Euler at the physics tick rate,
## which runs slightly ahead of the closed form because the rate shrinks
## within each step -- pinned by the measured values in the tests rather than
## by the analytic solution.
func decay(delta: float) -> void:
	if energy <= 0.0:
		energy = 0.0
		return
	var e_max: float = _energy_ceiling()
	var time: float = maxf(_pawn.speed_energy_deceleration_time, 0.001)
	var exponent: float = _pawn.speed_energy_deceleration_exponent
	# Solving (d/dt)E = -k*E^p for E(0) = e_max reaching 0 at t = time gives
	# k = e_max^(1-p) / ((1-p) * time). At p = 0.5 that is 2*sqrt(e_max)/time.
	var k: float = pow(e_max, 1.0 - exponent) / (maxf(1.0 - exponent, 0.001) * time)
	energy = maxf(energy - k * pow(energy, exponent) * delta, 0.0)

## Turning is a continuous tax with no free allowance (10.1 ③): the research
## found no "costs nothing below N degrees" parameter anywhere in the game.
func spend_turn(radians: float) -> void:
	drain(_pawn.speed_turn_deceleration_factor * absf(radians))

func drain(amount: float) -> void:
	energy = maxf(energy - absf(amount), 0.0)

## The curve's own last knot -- the energy at which the cap stops climbing.
## Both the accumulation clamp and the decay rate are derived from it rather
## than from a second, separately-tunable number that could disagree with the
## curve.
func _energy_ceiling() -> float:
	var knots := _pawn.speed_curve
	return knots[knots.size() - 1].x if not knots.is_empty() else 1.0

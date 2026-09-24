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

## Which accumulation factor is in force this tick. [ME:CONFIRMED 02 §2.1]
## The original declares three raw values (7/10/30). [ME:INFERRED 02 §2.1]
## Which one maps to walk, strafe, or sprint is unverified.
enum { WALK, STRAFE, SPRINT }

var energy: float = 0.0

## Where the current decay started, and how long it has been running. The decay
## curve is evaluated from these rather than stepped incrementally, because the
## shape it now uses has an infinite slope at t = 0 -- a per-tick form would
## take an unbounded first step. Reset by anything that puts energy IN or takes
## it out for another reason.
var _decay_from: float = 0.0
var _decay_time: float = 0.0

var _pawn: PawnConfig

func _init(pawn: PawnConfig) -> void:
	_pawn = pawn

func reset() -> void:
	energy = 0.0
	_rebase_decay()

## [ME:CONFIRMED] Landing at >= 7.2 m/s restores ground speed to 7.2: the
## original re-derives the ground speed budget from the speed the body
## actually lands with. A zipline exit at 15 m/s grounds into a full sprint
## budget (the curve tops out at ground_speed); it does not decay back to
## whatever pace the player ran before catching the cable.
##
## Raise-only, via maxf(): an ordinary slow landing must not undercut a
## budget the player had already earned by running.
func restore_for_landing(speed: float) -> void:
	energy = maxf(energy, energy_for_speed(_pawn, speed))
	_rebase_decay()

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
	_rebase_decay()

## The budget draining over speed_energy_deceleration_time, from wherever it
## stood when the drain began. What it prices: a manoeuvre the player cannot
## steer (MoveConfig.energy_decays) and running across the facing. NOT a body
## that stopped -- a stop brakes the budget down with the speed, see
## MoveConfig.energy_follows_speed.
func decay(delta: float) -> void:
	if energy <= 0.0:
		energy = 0.0
		_decay_time = 0.0
		return
	if _decay_time == 0.0:
		# Pick up wherever the budget currently stands, so a caller that set
		# `energy` directly -- tests do, and so does anything restoring state
		# -- gets a curve from THAT value rather than from a stale basis.
		_decay_from = energy
	_decay_time += delta
	var time: float = maxf(_pawn.speed_energy_deceleration_time, 0.001)
	var exponent: float = _pawn.speed_energy_deceleration_exponent
	# E = E0 * (1 - (t/T)^p), with the exponent on TIME.
	#
	# [ME:UNKNOWN 02 §2.5] the research recorded both readings of these two
	# confirmed numbers and could not choose ("or the reverse, depending on how
	# the formula is written"). The other is (d/dt)E = -k*E^p, which solves to
	# E0 * (1 - t/T)^2. This one was picked back when decay also ran on a
	# pause, a job it no longer has, so the choice is open again: against a
	# vault, this reading costs a 0.3 s one about 0.4 m/s from full pace and a
	# 1 s one about 1.0, the other about 0.3 and 0.9.
	var spent: float = clampf(pow(_decay_time / time, exponent), 0.0, 1.0)
	energy = maxf(_decay_from * (1.0 - spent), 0.0)

## [ME:CONFIRMED 10.1 §3] Turning is a continuous tax with no free allowance:
## the research found no "costs nothing below N degrees" parameter anywhere
## in the game.
##
## [ME:CONFIRMED 03 §3.2] The cost is per degree AND per degree-per-second,
## measured: the original charges 5.7x more per degree for a hard flick than
## for a slow pan. `delta` is therefore required -- the angle alone cannot
## say how fast it was swung, and charging on angle alone makes planning a
## line worthless.
func spend_turn(radians: float, delta: float) -> void:
	var rate_deg: float = rad_to_deg(absf(radians)) / maxf(delta, 0.0001)
	var cost: float = _pawn.speed_turn_deceleration_factor 		* turn_rate_multiplier(rate_deg) * absf(radians)
	# THE FLOOR. Turning bills against banked energy, but never below the
	# energy that buys speed_max_base_velocity. Above that line speed is
	# something the player EARNED by running, and turning gives it back; below
	# it, speed is just walking pace, and taxing it means a flick of the mouse
	# leaves the player standing still.
	#
	# Only turning is floored. decay() still empties the budget completely when
	# the player stops, or standing still would leave them permanently primed.
	var floor_energy: float = base_floor()
	if energy <= floor_energy:
		return
	energy = maxf(energy - absf(cost), floor_energy)
	_rebase_decay()

## THE floor -- the energy that buys speed_max_base_velocity, 4.0 m/s, 14.4
## km/h. Every drain in the project stops here except decay() from a
## standstill, and they all ask this rather than each spelling the pair out,
## so the floor cannot end up meaning two slightly different things.
func base_floor() -> float:
	return energy_for_speed(_pawn, _pawn.speed_max_base_velocity)

## The energy at which the speed curve first reaches `speed` -- the inverse of
## curve_at(). Linear search over the same knots, so the two cannot disagree.
##
## Used for the turning floor above. Returns 0 for a speed at or below the
## curve's start, and the last knot's energy for anything past its end.
static func energy_for_speed(pawn: PawnConfig, speed: float) -> float:
	var knots := pawn.speed_curve
	if knots.is_empty():
		return 0.0
	if speed <= knots[0].y:
		return knots[0].x
	for i in range(1, knots.size()):
		var a := knots[i - 1]
		var b := knots[i]
		if speed <= b.y:
			var span := b.y - a.y
			if span <= 0.0:
				return b.x
			return a.x + (b.x - a.x) * ((speed - a.y) / span)
	return knots[knots.size() - 1].x

## Linear interpolation over pawn.turn_rate_cost_curve, clamped at both ends.
## Clamping rather than extrapolating on purpose: beyond the measured band the
## shape is unknown, and extrapolating a power law there would invent a cost
## nobody observed. A one-tick 90-degree snap reports ~5400 deg/s, far past the
## fastest turn ever measured, and is simply charged the fastest measured rate.
func turn_rate_multiplier(rate_deg: float) -> float:
	var knots := _pawn.turn_rate_cost_curve
	if knots.is_empty():
		return 1.0
	if rate_deg <= knots[0].x:
		return knots[0].y
	for i in range(1, knots.size()):
		if rate_deg <= knots[i].x:
			var t: float = inverse_lerp(knots[i - 1].x, knots[i].x, rate_deg)
			return lerpf(knots[i - 1].y, knots[i].y, t)
	return knots[knots.size() - 1].y

## Draws the budget down toward what buys `speed`, never raises it: the
## excess halves every PawnConfig.energy_loss_half_life seconds. See
## Player.follow_speed().
##
## A CURVE, NOT A CUT. A mistake caught quickly -- W pressed again a moment
## after letting go, a wall glanced off rather than run into -- keeps what
## has not bled yet, because whatever asked for the bleed stops asking.
func bleed_toward_speed(speed: float, delta: float) -> void:
	var bought: float = energy_for_speed(_pawn, speed)
	if bought >= energy:
		return
	var half: float = _pawn.energy_loss_half_life
	var kept: float = 0.0 if half <= 0.0 else pow(0.5, delta / half)
	energy = bought + (energy - bought) * kept
	_rebase_decay()

## Lowers the budget to what buys `speed` at once, never raises it -- for a
## loss the original takes in one go (Player.dodge_launch()).
##
## REBASES ONLY WHEN IT LOWERS. The decay curve is steepest at its start, so a
## caller asking every tick -- a slide following its own bleed, a stick held
## under its limit -- would otherwise restart that steepest stretch sixty
## times a second under whatever decay is also running.
func match_speed(speed: float) -> void:
	var bought: float = energy_for_speed(_pawn, speed)
	if bought >= energy:
		return
	energy = bought
	_rebase_decay()

## Starts a fresh decay from wherever the budget stands, for a caller about to
## run decay() for a reason of its own -- a curve left running by an earlier
## drain must not be continued toward a number that no longer applies.
func restart_decay() -> void:
	_rebase_decay()

func drain(amount: float) -> void:
	energy = maxf(energy - absf(amount), 0.0)
	_rebase_decay()

## Restarts the decay clock from wherever the budget now stands. Called by
## everything that changes energy for a reason OTHER than decay, so a decay
## that resumes afterwards falls from the new value rather than continuing an
## old curve toward a number that is no longer relevant.
func _rebase_decay() -> void:
	_decay_from = energy
	_decay_time = 0.0

## The curve's own last knot -- the energy at which the cap stops climbing.
## Both the accumulation clamp and the decay rate are derived from it rather
## than from a second, separately-tunable number that could disagree with the
## curve.
func _energy_ceiling() -> float:
	var knots := _pawn.speed_curve
	return knots[knots.size() - 1].x if not knots.is_empty() else 1.0

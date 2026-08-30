class_name BalanceMove
extends LineWalkMove

# The original's TdMove_Balance: walking a pipe at a third of walking speed
# while an inverted pendulum tries to tip you off it.
#
# THE MODEL IS A BALL ON A DOME, and the owner measured it against the original
# rather than reading it off field names -- twice the field names gave the wrong
# answer. Entering, the game drops the ball a little off the apex, to the left
# or the right at random, further the faster you came in. Everything after that
# is the ball rolling off a dome it was never stable on. Get the offset AND its
# rate to zero early and it sits at the apex for the rest of the beam, which is
# why an expert barely touches A/D after the first moment.
#
# See docs/mirrors-edge-deep-research/05-动作库总览.md §5.6.

## Lean off the beam's centreline, in the pendulum's own units. Positive is
## toward the line's right-hand normal.
var _lean: float = 0.0
var _lean_rate: float = 0.0

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.BALANCE

static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	return LineWalkMove.foot_gate_at(line, player.global_position, snap_height)

## The ONE random draw of the whole move.
##
## DO NOT ADD A SECOND. Shoving the body every few seconds destroys the exact
## thing this move rewards: the stable stretch an expert earns by zeroing the
## offset early. The owner's measurement is explicit that the wobble is NOT a
## series of random pushes.
static func entry_lean(cfg: BalanceConfig, entry_speed: float,
		ground_speed: float, sign_pick: int) -> float:
	var reference: float = maxf(ground_speed, 0.0001)
	var magnitude: float = cfg.base_wobble \
		+ cfg.entry_speed_influence * cfg.base_wobble * (entry_speed / reference)
	return magnitude * float(sign_pick)

func enter(previous: StringName) -> void:
	var entry_speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	super.enter(previous)
	if _aborted:
		return
	var pick: int = 1 if randf() < 0.5 else -1
	seed_lean(BalanceMove.entry_lean(cfg, entry_speed, config.pawn.ground_speed, pick), 0.0)

## Test seam and entry seam both: sets the pendulum's two numbers outright.
func seed_lean(lean: float, rate: float) -> void:
	_lean = lean
	_lean_rate = rate

## One tick of the pendulum.
##
## NO DAMPING TERM, NOT ONE. Nothing in here may pull _lean_rate back toward
## zero on the player's behalf: "the expert zeroes the offset AND its rate" only
## means anything while no one else is doing it for them. A damping term is the
## system steadying the player, and it takes the reward with it.
##
## THE CORRECTION TERM IS ADDED, NOT SUBTRACTED. `lateral_input` shares
## _lean's own sign convention (positive is toward the line's right-hand
## normal), so fighting a positive lean means pushing a NEGATIVE lateral_input
## -- away from the side the body is falling toward, the same instinct as
## leaning right and pushing back left. `+ gain * lateral_input` is what makes
## that opposite-signed push subtract energy from the divergence term below;
## a `-` here was tried and passes only when the input matches the lean's own
## sign, which is steering the fall rather than fighting it -- caught by
## test_correction_opposes_the_lean, which a `-` here fails.
func integrate_lean(delta: float, lateral_input: float) -> void:
	var rate: float = 1.0 / maxf(cfg.divergence_time, 0.0001)
	var accel: float = _lean * rate * rate + cfg.correction_gain * lateral_input
	_lean_rate += accel * delta
	_lean += _lean_rate * delta

func lateral_update(delta: float, lateral_input: float) -> StringName:
	integrate_lean(delta, lateral_input)
	# Falling off is GEOMETRIC: the lean is a real displacement off the
	# centreline, and past the beam's half width the feet have nothing under
	# them. Not a separate threshold that happens to be checked here.
	if absf(lateral_offset()) > cfg.beam_half_width:
		player.consume_roll()
		return FALLING
	return KEEP

func lateral_offset() -> float:
	return _lean * cfg.gravity_influence

## Read by the camera, the skeleton lean, the FOV squeeze and the debug HUD --
## one source, several presentations.
func lean() -> float:
	return _lean

func lean_rate() -> float:
	return _lean_rate

## Normalised 0..1 severity, which is what every presentation channel actually
## wants. 1 means the feet are about to miss.
func lean_severity() -> float:
	var edge: float = maxf(cfg.beam_half_width, 0.0001)
	return clampf(absf(lateral_offset()) / edge, 0.0, 1.0)

## Signed version of the above, for channels that need a direction (camera
## roll, body lean).
func signed_severity() -> float:
	return lean_severity() * signf(_lean)

## Test helper: how far the lean gets in `seconds` under a held input, without
## disturbing this instance's own state.
func duplicate_lean_after(seconds: float, lateral_input: float) -> float:
	var probe := BalanceMove.new()
	probe.cfg = cfg
	probe.seed_lean(_lean, _lean_rate)
	var step: float = 1.0 / 60.0
	var t: float = 0.0
	while t < seconds:
		probe.integrate_lean(step, lateral_input)
		t += step
	return absf(probe.lean())

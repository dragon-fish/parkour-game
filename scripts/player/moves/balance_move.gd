class_name BalanceMove
extends LineWalkMove

# The original's TdMove_Balance: walking a pipe at a third of walking speed
# [ME:CONFIRMED 05 §5.6]. An inverted pendulum tries to tip you off it -- see
# the model below.
#
# [ME:CONFIRMED 05 §5.6] Standing still on the beam still loses balance, and
# the wobble itself does not depend on speed -- both are the owner's own
# measurements, overturning two prior readings taken from the CDO's field
# names alone. [ME:INFERRED] THE MODEL FITTED TO THOSE MEASUREMENTS IS A BALL
# ON A DOME (an inverted pendulum), not a formula recovered from the
# original -- no formula exists in the dump, only names and numbers.
# Entering, the game drops the ball a little off the apex, to the left or
# the right at random, further off the faster you came in. Everything after
# that is the ball rolling off a dome it was never stable on: get the offset
# AND its rate to zero early and it sits at the apex for the rest of the
# beam, which is why an expert barely touches A/D after the first moment.
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
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	return LineWalkMove.foot_gate_at(line, feet, snap_height)

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
	# READ BEFORE super.enter(previous), NOT AFTER: LineWalkMove.enter()
	# zeroes player.velocity (see its own note on why). Move this read past
	# that call and every entry measures a standstill, entry_speed_influence
	# goes dead, and nothing in the suite notices -- see
	# test_enter_reads_entry_speed_before_super_zeroes_it, which exercises
	# THIS function rather than entry_lean() alone.
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
## zero on the player's behalf: "the expert zeroes the offset AND its rate"
## only means anything while no one else is doing it for them. A damping term
## is the system steadying the player, and it takes the reward with it.
## test_lean_diverges_when_nobody_corrects cannot see one -- its sign of
## divergence survives any damping coefficient. Only
## test_the_free_pendulum_matches_the_undamped_closed_form, which checks the
## rate against the exact undamped solution, can.
##
## THE CORRECTION TERM IS ADDED, NOT SUBTRACTED. `lateral_input` shares
## _lean's own sign convention (positive is toward the line's right-hand
## normal), so fighting a positive lean means pushing a NEGATIVE
## lateral_input -- away from the side the body is falling toward. Only
## `+ gain * lateral_input` makes that opposite-signed push subtract from the
## divergence term below; test_correction_opposes_the_lean pins the sign.
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
	if player.camera_rig != null:
		# Driven ONLY by how far balance is already lost, never by a constant
		# on entry: standing steady on the beam must look completely normal,
		# and only a body about to fall gets the roll and the tunnel.
		player.camera_rig.set_balance_lean(
			deg_to_rad(signed_severity() * cfg.max_camera_roll_deg),
			lean_severity() * cfg.fov_squeeze_deg)
	return KEEP

func exit() -> void:
	super.exit()
	# Zeroed on the way out so the roll and the squeeze do not follow the
	# player off the beam -- see LadderMove.exit()'s own tint reset for the
	# same pattern.
	if player.camera_rig != null:
		player.camera_rig.set_balance_lean(0.0, 0.0)

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
	var result: float = absf(probe.lean())
	# Move extends Node and this probe never enters the tree -- GUT counts an
	# unfreed one as an orphan.
	probe.free()
	return result

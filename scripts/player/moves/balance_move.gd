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
## The beam's own wind: a smooth bounded wander sampled by time, not a value
## drawn fresh each tick. Perlin because the owner describes being MOVED by it
## rather than rattled -- white noise averages to nothing and reads as a buzz,
## while a smooth walk leans the body one way for a moment and then the other,
## which is also why two stretches of it sometimes hand the correction back for
## free.
var _wind_noise: FastNoiseLite = BalanceMove._make_wind_noise()
var _wind_phase: float = 0.0
## 0 while the body is still on the beam, then climbing to 1 across
## fall_push_time as the capsule is carried clear of the line.
var _fall_push: float = 0.0

static func _make_wind_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	# Left at a plain 1 and sampled through wind_frequency at the call site, so
	# that dial means what it says instead of multiplying with this one.
	noise.frequency = 1.0
	return noise

func kind() -> InterestLine.Kind:
	return InterestLine.Kind.BALANCE

## Below this horizontal speed, arrival velocity carries no real direction --
## it is float noise from standing still or from a body that turned in place
## before stepping on, not a run-up. Comfortably above physics jitter, well
## below a walking pace.
const MEANINGFUL_ARRIVAL_SPEED: float = 0.05

## The beam is enterable from either end -- see this file's own header on the
## inverted pendulum for why direction otherwise has no bearing on the pendulum
## itself, only on which way W drives the body. Two candidate signals exist for
## "which way did the player mean to walk": the body's facing, or its
## horizontal velocity. Velocity wins when it is meaningful AND the body is
## moving the way it faces: a body arriving at a run chose that direction with
## its feet, which is a clearer statement of intent than whatever way it
## happened to be looking (mouse look is independent of travel). Below
## MEANINGFUL_ARRIVAL_SPEED there is no run to read, so facing is what is left
## -- covers stepping onto the beam from a standstill, or turning in place at
## one end before walking on.
##
## A BODY BACKING ONTO THE BEAM KEEPS ITS FACING. Its velocity points along
## the beam but its face points off it, and the key it is holding is S. Facing
## the body along the velocity would turn it round under the player's held S,
## which then walks it straight back off the end it just came in by -- and
## with nothing but the line holding it up, that is a fall on the first tick.
## Reported in play as "walk onto the beam backwards, enter, leave, drop".
## Keeping the facing means S carries on driving the body backwards along the
## beam, exactly as it was driving it before the catch.
func _pick_direction_sign(tangent: Vector3) -> float:
	var flat_tangent := Vector3(tangent.x, 0.0, tangent.z)
	if flat_tangent.length_squared() < 0.0001:
		return 1.0
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	var horizontal_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var arrival: Vector3 = facing
	if horizontal_velocity.length() > MEANINGFUL_ARRIVAL_SPEED \
			and horizontal_velocity.dot(facing) >= 0.0:
		arrival = horizontal_velocity
	return 1.0 if arrival.dot(flat_tangent) >= 0.0 else -1.0

static func catch_gate(player: Player, line: InterestLine, snap_height: float) -> bool:
	if not player.line_ready(line):
		return false
	var feet: Vector3 = player.global_position
	feet.y = player.probes.feet_y()
	return LineWalkMove.foot_gate_at(line, feet, snap_height)

## The ONE random draw of the whole move.
##
## THE ENTRY DRAW IS ONE OF TWO RANDOM SOURCES, and the only one that decides
## which side the beam starts against. The other is the wind in
## integrate_lean(); see BalanceConfig.wind_strength for the measurement that
## put it there.
##
## entry_speed_influence SCALES base_wobble (magnitude = base_wobble * (1 +
## entry_speed_influence * v / ground_speed)); it does not ADD to it. The
## spec's own formula (base_wobble + entry_speed_influence * v / ground_speed)
## puts a full-speed entry at 2.52 of lean against a 0.14 m beam_half_width --
## instantly off the beam. Scaling base_wobble instead keeps a standstill
## entry's non-zero wobble (constraint 2) proportionally present at speed,
## rather than swamped by an unrelated additive term.
static func entry_lean(cfg: BalanceConfig, entry_speed: float,
		ground_speed: float, sign_pick: int) -> float:
	var reference: float = maxf(ground_speed, 0.0001)
	var magnitude: float = cfg.base_wobble \
		+ cfg.entry_speed_influence * cfg.base_wobble * (entry_speed / reference)
	return magnitude * float(sign_pick)

## Above a level's own FORCE_VIEW volumes, which author at the default
## layer_priority (0) unless they deliberately raise it -- see
## ModifierVolume.layer_priority. The beam's forced first person is not
## meant to be something a level accidentally outranks by sharing that default.
const FORCE_VIEW_PRIORITY: int = 10

## True only once THIS instance has pushed its own FORCE_VIEW status --
## guards exit() against clearing a status it never applied (see exit()'s own
## note): the abort path below returns before ever reaching the push.
var _forced_first_person: bool = false

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
	_wind_noise.seed = randi()
	_wind_phase = 0.0
	_fall_push = 0.0
	# THIRD PERSON READS BADLY ON A BEAM -- beam only, not LedgeWalkMove, which
	# keeps the player's own view choice. Goes through the status system's own
	# FORCE_VIEW mechanism (the same one a level volume or a death uses,
	# resolved every tick by Player._push_forced_view()) rather than a
	# parallel flag, so every existing reader of the view already understands
	# it without change.
	var spec := StatusSpec.new()
	spec.effect = Status.Effect.FORCE_VIEW
	spec.view = Status.View.FIRST
	player.apply_status(spec, self, FORCE_VIEW_PRIORITY)
	_forced_first_person = true

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
	var accel: float = _lean * rate * rate + correction_gain_at(_lean) * lateral_input
	_lean_rate += accel * delta + _wind(delta)
	_lean += _lean_rate * delta

## The beam's own shove for this tick, or zero on the ticks between shoves.
##
## STILL NOT DAMPING, and the distinction matters: this only ever ADDS to the
## rate, in a direction that has nothing to do with the rate's own sign, so it
## cannot quietly steady a player who has stopped correcting. A body left alone
## still runs away from the apex; the shoves decide which way and when it gets
## interesting.
##
## Wound to a fresh random wait each time it fires, rather than a fixed period:
## a metronome is something a player learns to sit on, and the owner's report
## is specifically that the beam gives no warning.
func _wind(delta: float) -> float:
	if cfg.wind_strength <= 0.0:
		return 0.0
	# BOTH THE HEIGHT AND THE RATE OF THE GUSTS RIDE ON THIS. [ME:CONFIRMED] the
	# owner: 「这个频率和力度都是会随着体态变化的」-- so the phase advances more
	# slowly as the body goes, which stretches the wave out rather than merely
	# shrinking it. A body near the edge is not being buffeted quietly; it is
	# being buffeted slowly, which is what leaves room to answer.
	var composure: float = 1.0 - lean_severity()
	_wind_phase += delta * cfg.wind_frequency * composure
	var gust: float = _wind_noise.get_noise_1d(_wind_phase)
	# SCALED DOWN BY HOW FAR GONE THE BODY ALREADY IS. [ME:CONFIRMED] the owner,
	# in play: 「玩家的体态会抑制波峰的绝对值，越接近平衡波峰越激烈，越接近失控则
	# 越平缓，游戏不会让你安稳的走过独木桥，但也不会在你快要掉下去的时候给你增加
	# 压力」-- the gusts are fiercest while the player is holding it together and
	# flatten out as the beam is lost.
	#
	# DO NOT "fix" this into a constant. The pressure belongs where the player
	# is winning; adding it where they are already losing turns a recoverable
	# fall into a coin toss, and the correction boost above exists to make that
	# same stretch winnable.
	return gust * cfg.wind_strength * composure * delta

## The correction authority available at `lean`, which GROWS as the body nears
## the edge.
##
## WITHOUT THIS THERE IS A ZONE THAT CANNOT BE RECOVERED FROM, and it is not a
## matter of reflexes. The divergence term grows linearly with the lean while a
## fixed gain does not, so past `correction_gain / divergence_time^-2` even a
## held, perfect, full-strength correction still accelerates the fall. At the
## shipped dials that boundary sits around two thirds of the way to the edge,
## which leaves the last third decided before the player touched anything.
##
## The boost does not make the beam easy: reaching the edge still needs a
## prompt, sustained correction, and the rate the body has built up by then
## takes time to turn round. What it removes is the stretch where pressing the
## key correctly changes nothing at all.
func correction_gain_at(lean: float) -> float:
	var edge: float = maxf(cfg.beam_half_width, 0.0001)
	var severity: float = clampf(absf(lean) * cfg.gravity_influence / edge, 0.0, 1.0)
	var t: float = pow(severity, maxf(cfg.correction_boost_exponent, 0.01))
	return lerpf(cfg.correction_gain, cfg.correction_gain_at_edge, t)

func lateral_update(delta: float, lateral_input: float) -> StringName:
	# THE SHOVE OWNS THE BODY ONCE IT STARTS. The lean stops being integrated --
	# there is nothing left to correct, the fall is decided -- and the capsule
	# is carried off the line over fall_push_time before the handover. Falling
	# off is still geometric: the feet leave the beam because the body was moved
	# clear of it, not because a counter reached a number and teleported it.
	if _fall_push > 0.0:
		var push_time: float = maxf(cfg.fall_push_time, 0.0001)
		_fall_push += delta / push_time
		if _fall_push >= 1.0:
			player.consume_roll()
			# HANDED OVER AT THE ARC'S OWN SPEED. The arc ends heading straight
			# down at 2 * drop / time (its derivative at t = 1, see
			# lateral_offset()), and the fall has to pick up from there: a fall
			# that starts from rest after a body was visibly moving is the
			# stall the owner reported. LineWalkMove zeroed the velocity on
			# entry, so nothing else is in it to carry.
			player.velocity = Vector3.DOWN * (2.0 * cfg.fall_push_drop / push_time)
			return FALLING
		return KEEP
	integrate_lean(delta, lateral_input)
	if absf(_lean) > fall_lean():
		# Started, not finished: the next tick carries the capsule out.
		_fall_push = 0.0001
		# THE VIEW IS THE PLAYER'S AGAIN FROM THIS TICK, not from the handover:
		# the forced first person exists for the ride, and the ride is over the
		# instant balance is lost. The owner's call: the shove is watched from
		# wherever the player had chosen to watch from.
		_release_forced_view()
	if player.camera_rig != null:
		# Driven ONLY by how far balance is already lost, never by a constant
		# on entry: standing steady on the beam must look completely normal,
		# and only a body about to fall gets the roll and the tunnel.
		#
		# NEGATED: signed_severity() > 0 is a lean toward the body's right, but
		# CameraRig's own rotation.z convention tips the eye toward -X (left)
		# for a POSITIVE value -- see max_camera_roll_deg's own note for the
		# direction this must produce instead.
		player.camera_rig.set_balance_lean(
			deg_to_rad(-signed_severity() * cfg.max_camera_roll_deg),
			lean_severity() * cfg.fov_squeeze_deg)
	return KEEP

func exit() -> void:
	super.exit()
	# GUARDED ON _forced_first_person, NOT UNCONDITIONAL: remove_status() would
	# otherwise strip ANY active FORCE_VIEW entry, including one this instance
	# never applied (the abort path in enter() returns before pushing one) --
	# a level's own forced view has no relation to this move and must not be
	# collateral damage on an aborted entry.
	#
	# EVERY EXIT PATH ROUTES HERE: MoveManager.start() calls the outgoing
	# move's exit() unconditionally before entering the next one, whether that
	# is walking off either end (WALKING), jumping or crouching off
	# (FALLING), losing balance (FALLING, via lateral_update() above), or a
	# mid-beam death's respawn restarting into WALKING -- one exit(), not one
	# per cause, so there is nowhere for the restore to be missed.
	_release_forced_view()
	# Zeroed on the way out so the roll and the squeeze do not follow the
	# player off the beam -- see LadderMove.exit()'s own tint reset for the
	# same pattern.
	if player.camera_rig != null:
		player.camera_rig.set_balance_lean(0.0, 0.0)

## The shove is the one way off a beam that is a fall -- see
## LineWalkMove.exit() for what the cooldown it arms is for.
func _left_by_falling() -> bool:
	return _fall_push > 0.0

## Gives the view back. Reached twice on a lost balance -- the tick the shove
## starts (lateral_update()) and exit() -- and once on every other way off;
## the flag makes the second call a no-op rather than a second removal.
func _release_forced_view() -> void:
	if _forced_first_person:
		player.remove_status(Status.Effect.FORCE_VIEW, &"")
		_forced_first_person = false

## How far off the centreline the capsule stands. ZERO for the whole ride, and
## non-zero only during the shove that ends it.
##
## THE CAPSULE RIDES THE LINE. Sliding it sideways with the lean drags the
## visible model along with it, which reads as the character skating rather than
## wobbling -- the owner's call, and it matches the rest of the "along a line"
## family, none of which translate the body off their line either. The lean is
## carried by the camera roll and the segmented skeleton lean instead; both are
## presentation, and both already exist.
##
## THE SHOVE IS ONE QUADRATIC BEZIER, in the line's (normal, up) plane: from
## the stand, through a control point fall_push_distance out at the SAME
## height, to fall_push_distance out and fall_push_drop down. The owner's
## sketch: pushed sideways first, then taken by gravity, arriving beside and
## below the beam. That gives sideways = D * t * (2 - t) (fast off the line,
## easing out) and down = H * t * t (nothing at first, then all of it), and
## its end tangent is straight down at 2H per unit t -- which is the velocity
## the fall is handed, see lateral_update(). drop_offset() is the other half
## of this same curve; do not tune one shape without the other.
func lateral_offset() -> float:
	if _fall_push <= 0.0:
		return 0.0
	var t: float = clampf(_fall_push, 0.0, 1.0)
	return signf(_lean) * cfg.fall_push_distance * t * (2.0 - t)

## How far BELOW the line the capsule stands, metres, positive down. Zero for
## the ride; the vertical half of the shove's curve, see lateral_offset().
func drop_offset() -> float:
	if _fall_push <= 0.0:
		return 0.0
	var t: float = clampf(_fall_push, 0.0, 1.0)
	return cfg.fall_push_drop * t * t

## Read by the camera, the skeleton lean, the FOV squeeze and the debug HUD --
## one source, several presentations.
func lean() -> float:
	return _lean

func lean_rate() -> float:
	return _lean_rate

## Normalised 0..1 severity, which is what every presentation channel actually
## wants. 1 means the feet are about to miss.
##
## MEASURED OFF THE LEAN ITSELF, not off lateral_offset(): the capsule no longer
## moves with the lean, so a severity read from its position would sit at zero
## for the whole ride and then jump to 1 during the shove.
func lean_severity() -> float:
	return clampf(absf(_lean) / maxf(fall_lean(), 0.0001), 0.0, 1.0)

## The lean at which the feet run out of beam -- the edge every severity is
## measured against, and the trigger for the shove that ends the ride.
func fall_lean() -> float:
	return cfg.beam_half_width / maxf(cfg.gravity_influence, 0.0001)

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

## The lean's RATE, normalised the same way lean_severity() normalises the lean
## itself: how much of the distance to the edge this rate covers in one
## divergence time constant. Signed toward the line's right-hand normal.
##
## Exists for the tuning readout. The pendulum's whole skill is zeroing the
## offset AND its rate together, and a display that shows only the offset hides
## the half the player is actually failing at.
func signed_rate_severity() -> float:
	var edge: float = maxf(cfg.beam_half_width, 0.0001)
	var reach: float = _lean_rate * cfg.divergence_time * cfg.gravity_influence
	return clampf(reach / edge, -1.0, 1.0)

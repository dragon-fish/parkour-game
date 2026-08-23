class_name ScriptedMove
extends Move

# Shared machinery for states that DRIVE the body along a computed path rather
# than letting physics push it. Vaulting and mantling both need to pass through
# geometry that would otherwise block them, which is exactly what physics is
# there to prevent — so for the duration of the move, physics steps aside.

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _duration: float = 0.0
var _elapsed: float = 0.0
## Peak height of the vertical arc added on top of the straight from->to lerp.
## A per-call value (not a shared literal) so each concrete move can supply
## its own — the ledge state arriving next needs a different arc than vault's.
## How much of the horizontal travel the rise and the fall are each allowed,
## leaving the rest to the straight middle. A curve that carried none at all
## would stop the body dead at the foot of the obstacle and again on top of it.
const EDGE_TRAVEL := 0.15

var _arc: float = 0.0
## How far the rise runs ahead of the travel. See begin().
var _vertical_lead: float = 0.0

## `vertical_lead` in 0..1 decides the SHAPE of the path, not its speed.
##
## ⚠️ AT 0 THIS IS ONE CURVE FOR ALL THREE AXES, which is a fine description of a
## vault -- the body really does travel up and over in one motion -- and a wrong
## one for a pull-up. ✅ The owner drew it: "脚本弧线不对，它的趋势应该是先垂直向上
## 然后再往前送，而不是一个完美的弧线，否则人会穿墙." A symmetric arc cuts the
## corner, and the corner is the wall.
##
## At 1 the rise happens first and the travel waits for it, giving the hook in
## that drawing. In between, both blend, and at exactly 0 the arithmetic reduces
## to what it was -- so nothing that does not ask for a lead moves differently.
func begin(from: Vector3, to: Vector3, duration: float, arc: float = 0.0,
		vertical_lead: float = 0.0) -> void:
	_from = from
	_to = to
	_duration = maxf(duration, 0.0001)
	_elapsed = 0.0
	_arc = arc
	_vertical_lead = clampf(vertical_lead, 0.0, 1.0)

## How long the scripted travel is set to take, or 0 before begin() runs.
##
## Read by CharacterAnimator, which fits the CLIP to it. The two were never
## related before, and they had no reason to agree: SafetyVault is 0.733 s while
## a fast vault_over is floored at 0.325, so under half the clip ever played
## before the move handed off. ✅ The owner: "the fully driven vault is odd, and
## the speed feels like double." Both, from the same gap.
func scripted_duration() -> float:
	return _duration if _elapsed < _duration else 0.0

func progress() -> float:
	return clampf(_elapsed / _duration, 0.0, 1.0)

## Moves the body one tick along the path. Returns true once the path is done.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := progress()
	# Ease-out: most of the travel happens early, so the action reads as a
	# push-off rather than a constant-speed slide. The exponent is a curve-shape
	# decision, not a feel dial with a meaningful tuning range, so it stays a
	# literal here rather than moving into MovementConfig alongside _arc.
	var eased := 1.0 - pow(1.0 - t, 2.0)
	if _vertical_lead <= 0.0:
		# ONE CURVE FOR ALL THREE AXES, plus a symmetric bump. Left byte for byte
		# as it was: everything that does not ask for a lead still moves exactly
		# how it did.
		var flat := _from.lerp(_to, eased)
		flat.y += sin(t * PI) * _arc
		player.global_position = flat
		return t >= 1.0

	# ⚠️ THREE SEGMENTS, NOT ONE, and the middle one is STRAIGHT.
	#
	# ✅ THE OWNER, on a shape a single curve cannot make: "对于宽度站不下一个人的
	# 障碍，就是抬升 -> 滑过障碍顶部 -> 落地，它是多段贝塞尔曲线+直线组成的复合曲线,
	# 不应该是我们目前的单段." And with a drawing, for both this and the pull-up:
	# "其实应该先抬升到障碍的高度再往前送."
	#
	# A bump added to a straight line is symmetric about the MIDDLE OF THE
	# JOURNEY, and the obstacle is not in the middle of the journey -- it is at
	# the near end of it. So the body was still climbing while it was already
	# inside the face. Worse, it began descending at the halfway mark, which is
	# exactly where it should still be sliding along the top.
	#
	# 📌 And the source agrees about what this move IS: a VaultOver's peak was
	# measured 0.87 m BELOW the obstacle's top, with the feet never clearing it
	# (docs/feel-backlog.md 27). It is hands-on-top, carrying the body PAST the
	# obstacle -- a slide across, not a leap over. A flat middle is that slide.
	var rise_end: float = lerpf(0.5, 0.28, _vertical_lead)
	var fall_start: float = lerpf(0.5, 0.62, _vertical_lead)
	# Clear of BOTH ends, so this reads as a rise whichever way the journey
	# slopes: a pull-up finishes above where it started, a vault-over below.
	var peak: float = maxf(_from.y, _to.y) + _arc

	var height: float
	var travel: float
	if t <= rise_end:
		# UP THE FACE. Ease out into the top, and hold the travel almost still:
		# every centimetre spent forward here is spent inside the obstacle.
		var u: float = t / maxf(rise_end, 0.0001)
		height = lerpf(_from.y, peak, 1.0 - pow(1.0 - u, 2.0))
		travel = EDGE_TRAVEL * u * u
	elif t <= fall_start:
		# ACROSS THE TOP. Straight, in both axes -- this is the segment the old
		# single curve had nowhere to put.
		var u: float = (t - rise_end) / maxf(fall_start - rise_end, 0.0001)
		height = peak
		travel = lerpf(EDGE_TRAVEL, 1.0 - EDGE_TRAVEL, u)
	else:
		# DOWN THE FAR SIDE.
		var u: float = (t - fall_start) / maxf(1.0 - fall_start, 0.0001)
		height = lerpf(peak, _to.y, pow(u, 2.0))
		travel = lerpf(1.0 - EDGE_TRAVEL, 1.0, 1.0 - pow(1.0 - u, 2.0))

	var target := _from.lerp(_to, travel)
	target.y = height
	player.global_position = target
	return t >= 1.0

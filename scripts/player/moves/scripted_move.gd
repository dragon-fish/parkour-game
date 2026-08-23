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

## The CAMERA's fallback rise, in metres. Not the body's -- see camera_lift().
var _camera_arc: float = 0.0
## How far the rise runs ahead of the travel. See begin().
var _vertical_lead: float = 0.0
## The travel's shaping exponent. 1 is linear. See begin().
var _ease: float = 1.0

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
## `ease` is the exponent the travel is shaped by: 1 is a straight line at a
## constant speed, 2 is the ease-out this used to hard-code.
##
## ✅ THE OWNER, keying against it: "我发现手k动画，不如让胶囊走匀速直线，否则我还得
## 对抗那个特别奇怪的曲线." Which is their own methodology arriving at its end
## point -- see docs/capsule-leads-presentation.md. The capsule's job is to be
## PREDICTABLE, and nothing is more predictable than a straight line at a steady
## pace: an offset keyed at 40% of the way through describes a body 40% of the
## way along, and the person keying it can hold that in their head.
func begin(from: Vector3, to: Vector3, duration: float, camera_arc: float = 0.0,
		vertical_lead: float = 0.0, ease: float = 1.0) -> void:
	_from = from
	_to = to
	_duration = maxf(duration, 0.0001)
	_elapsed = 0.0
	_camera_arc = camera_arc
	_vertical_lead = clampf(vertical_lead, 0.0, 1.0)
	_ease = maxf(ease, 0.05)

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
	player.global_position = sample(t)
	return t >= 1.0

## Where the path is at `t` in 0..1.
##
## ⚠️ SPLIT OUT SO THE DEBUG VIEW CAN DRAW THE REAL CURVE. ✅ The owner: "你能不能
## 把曲线画出来啊，我真的不知道现在的曲线长什么样子." A drawer that recomputed the same
## arithmetic would be a picture of a SECOND implementation -- one that agrees
## with this until the moment a difference is what you are looking for. Same rule
## Probes follows by handing back the segments it actually fired.
func sample(t: float) -> Vector3:
	# ⚠️ LINEAR BY DEFAULT, and the ease-out that used to be hard-coded here is
	# now something a move asks for. The old comment argued it made the action
	# "read as a push-off rather than a constant-speed slide" -- which is a
	# statement about how it LOOKS, and looks are the animation's job. What the
	# capsule owes is predictability.
	var eased := 1.0 - pow(1.0 - t, _ease) if _ease != 1.0 else t
	if _vertical_lead <= 0.0:
		# ONE CURVE FOR ALL THREE AXES, and nothing added on top of it. The
		# symmetric bump that used to live here is the camera's now -- see
		# camera_lift().
		return _from.lerp(_to, eased)

	# ⚠️ THREE SEGMENTS, NOT ONE, and the middle one is STRAIGHT.
	#
	# ✅ THE OWNER, on a shape a single curve cannot make: "对于宽度站不下一个人的
	# 障碍，就是抬升 -> 滑过障碍顶部 -> 落地，它是多段贝塞尔曲线+直线组成的复合曲线,
	# 不应该是我们目前的单段."
	#
	# A bump added to a straight line is symmetric about the MIDDLE OF THE
	# JOURNEY, and the obstacle is not in the middle of the journey -- it is at
	# the near end of it. So the body was still climbing while it was already
	# inside the face, and it began descending at the halfway mark, which is
	# exactly where it should still be sliding along the top.
	#
	# 📌 And the source agrees about what this move IS: a VaultOver's peak was
	# measured 0.87 m BELOW the obstacle's top, with the feet never clearing it
	# (docs/feel-backlog.md 27). It is hands-on-top, carrying the body PAST the
	# obstacle -- a slide across, not a leap over. A flat middle is that slide.
	var rise_end: float = knee_rise()
	var fall_start: float = knee_fall()
	var peak: float = peak_height()

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
	return target

## Where the rise stops and the flat crossing begins, in 0..1.
func knee_rise() -> float:
	return lerpf(0.5, 0.28, _vertical_lead)

## Where the flat crossing ends and the drop begins, in 0..1.
func knee_fall() -> float:
	return lerpf(0.5, 0.62, _vertical_lead)

## The height the crossing happens at. Clear of BOTH ends, so this reads as a
## rise whichever way the journey slopes: a pull-up finishes above where it
## started, a vault-over below.
func peak_height() -> float:
	return maxf(_from.y, _to.y) + _camera_arc

## Everything a debug view needs to draw this path, or an empty dictionary when
## nothing is running. See sample().
func path_debug() -> Dictionary:
	if _duration <= 0.0001 or _elapsed >= _duration:
		return {}
	return {"from": _from, "to": _to, "progress": progress(),
		"lead": _vertical_lead, "arc": _camera_arc, "duration": _duration,
		"knee_rise": knee_rise(), "knee_fall": knee_fall(),
		"peak": peak_height()}

## How far the EYE is carried above the straight line, right now.
##
## ✅ THE OWNER, settling what the arc is for: "所有脚本动作，胶囊永远只走直线，只有没绑
## 角色模型和骨骼的时候，才用得到相机去模拟轨迹，所以这个轨迹只留给 fallback 的相机偏移."
##
## 🎯 SO THE ARC IS NOT A PATH ANY MORE. sample() no longer adds it: every
## scripted move travels in a straight line, with no exception left for a tall
## obstacle. What the arc was really doing was keeping the EYE out of the wall on
## a vault over something 1.5 m high, and that is a camera job -- the number was
## always derived by aiming at the eye (see SpeedVaultMove), which is the tell.
##
## ⚠️ FALLBACK ONLY. With a model attached the camera follows the head bone, and
## the head bone is where the animation puts it; adding this on top would move
## the eye twice. Player only reads it when there is no head to follow, which is
## the case the owner kept it for: a bare capsule has nothing but the eye to sell
## the motion with.
func camera_lift() -> float:
	if _camera_arc <= 0.0 or _duration <= 0.0001:
		return 0.0
	return sin(progress() * PI) * _camera_arc

## How much higher the path STARTS than it ends, in metres.
##
## ✅ THE OWNER, on why one row per obstacle is not enough: "相同的高度和宽度，不同的起
## 跳时间是不是也有单独的存档，因为起跳时间可能会导致一个完美 StepUp 变成补救型" -- and,
## on the mechanism: "进入脚本控制的瞬间，玩家的起始高度不一样啊，怎么可能轨迹一样."
##
## 🎯 MEASURED, one 1.0 x 0.4 obstacle, four jump timings that all vault:
##
##     lead 0.10   from y 1.00   rise +0.10   path 1.463 m
##     lead 0.15   from y 1.09   rise +0.19   path 1.623 m
##     lead 0.20   from y 1.35   rise +0.44   path 1.626 m
##     lead 0.30   from y 1.69   rise +0.78   path 1.756 m
##
## Same clip, same landing, same 27 frames -- and a start 0.69 m apart, which is
## a fifth of the path's length. An offset keyed at 30% through describes a
## different body in each of those.
##
## 📌 RELATIVE TO THE LANDING, not an absolute height. This has to be a number
## the same obstacle produces the same way wherever it stands in a level, and it
## has to be one ScriptedMove already knows -- no new plumbing, no dependency on
## whoever set the path up.
func entry_rise() -> float:
	if _duration <= 0.0001:
		return 0.0
	return _from.y - _to.y

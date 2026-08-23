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
var _control_bias: float = 0.0
## The travel's shaping exponent. 1 is linear. See begin().
var _ease: float = 1.0

## `control_bias` in 0..1 slides the bezier control point from the END toward
## the START. It is the only thing about the shape that varies.
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
		control_bias: float = 0.0, ease: float = 1.0) -> void:
	_from = from
	_to = to
	_duration = maxf(duration, 0.0001)
	_elapsed = 0.0
	_camera_arc = camera_arc
	_control_bias = clampf(control_bias, 0.0, 1.0)
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
## Where the body is at `t`, 0..1.
##
## ✅ ONE SHAPE FOR EVERY SCRIPTED MOVE, on the owner's call after the branches
## had piled up four deep: "先直接套用grab的规则，然后我来开需不需要微调力度." The
## pull-up's curve was the one they called perfect, so it becomes the only one --
## and what used to be a choice between a symmetric bump, a three-segment
## composite and a straight line is now a single quadratic Bezier with one dial.
##
## 🎯 THE CONTROL POINT IS THE WHOLE DESIGN. It sits at the height of the higher
## END and slides along the line between the two, so:
##
##   - the curve leaves the start rising and arrives at the end level
##   - it never goes above the destination, so nothing overshoots a rooftop
##   - pulled toward the start it bulges away from the wall; pulled toward the
##     end it hugs the face
##
## ⚠️ AND THERE IS NO LONGER A "STRAIGHT" CASE TO DIAGNOSE. Half the debugging
## today was spent telling a flat curve from a line, and asking which of four
## rules had produced it. There is one rule.
func sample(t: float) -> Vector3:
	# The ease shapes the PACE along the curve, not the curve. 1 is a steady
	# pace, which is what the capsule owes; see begin().
	var eased := 1.0 - pow(1.0 - t, _ease) if _ease != 1.0 else t
	var control := _to.lerp(_from, _control_bias)
	control.y = peak_height()
	var u: float = 1.0 - eased
	return _from * (u * u) + control * (2.0 * u * eased) + _to * (eased * eased)

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
		"lead": _control_bias, "arc": _camera_arc, "duration": _duration,
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

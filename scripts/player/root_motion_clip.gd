class_name RootMotionClip
extends RefCounted

# A coarse, piecewise-linear summary of one of the original's first-person
# root tracks: where the root has moved (forward, right, metres) and turned
# (yaw, radians clockwise) at a handful of times through the sequence.
# [ME:DERIVED] read off the decompiled AS_C1P_Unarmed tracks (60 Hz) at their
# turning points; the end values and the sequence lengths are the tracks' own.
#
# The moves that play these turn the clip into the pawn's root motion
# (Player.root_motion_velocity) or root rotation (HalfTurn) themselves. The
# track is in the frame the pawn had when the animation STARTED.

## The sequence's own length, seconds: OnCustomAnimEnd comes here.
var length: float = 0.0
## [time, forward m, right m] rows, time ascending, starting at 0.
var _moves: Array = []
## [time, yaw radians clockwise] rows.
var _turns: Array = []

static func make(seconds: float, moves: Array, turns: Array = []) -> RootMotionClip:
	var clip := RootMotionClip.new()
	clip.length = seconds
	clip._moves = moves
	clip._turns = turns
	return clip

## Root displacement at `t`, as (forward, right) metres.
func displacement(t: float) -> Vector2:
	if _moves.is_empty():
		return Vector2.ZERO
	var row: Array = _sample(_moves, t)
	return Vector2(row[0], row[1])

## Root yaw at `t`, radians clockwise.
func turn(t: float) -> float:
	if _turns.is_empty():
		return 0.0
	return float(_sample(_turns, t)[0])

## The root's velocity over the step from `t` to `t + dt`, as (forward,
## right) m/s.
func velocity(t: float, dt: float) -> Vector2:
	if dt <= 0.0:
		return Vector2.ZERO
	return (displacement(t + dt) - displacement(t)) / dt

## The same, turned into world space against the pawn's facing at the start.
func world_velocity(t: float, dt: float, facing: Vector3) -> Vector3:
	var v: Vector2 = velocity(t, dt)
	var right: Vector3 = facing.cross(Vector3.UP)
	return facing * v.x + right * v.y

static func _sample(rows: Array, t: float) -> Array:
	var last: Array = rows[rows.size() - 1]
	if t >= float(last[0]):
		return last.slice(1)
	var prev: Array = rows[0]
	if t <= float(prev[0]):
		return prev.slice(1)
	for i in range(1, rows.size()):
		var row: Array = rows[i]
		if t <= float(row[0]):
			var span: float = float(row[0]) - float(prev[0])
			var w: float = (t - float(prev[0])) / span if span > 0.0 else 1.0
			var out: Array = []
			for j in range(1, row.size()):
				out.append(lerpf(float(prev[j]), float(row[j]), w))
			return out
		prev = row
	return last.slice(1)

# --- the original's clips this project plays ------------------------------------

## fallinglandroll, the skill roll: 3.14 m forward in 1.27 s, fast-slow-fast.
static func skill_roll() -> RootMotionClip:
	return make(1.2667, [[0.0, 0.0, 0.0], [0.15, 0.97, 0.0], [0.25, 1.25, 0.0],
		[0.6, 1.42, 0.0], [0.8, 1.78, 0.0], [1.2667, 3.135, 0.0]])

## StumbleFwd: 2.55 m forward, all of it in the first 0.45 s.
static func stumble_forward() -> RootMotionClip:
	return make(1.0, [[0.0, 0.0, 0.0], [0.25, 1.16, 0.0], [0.45, 2.553, 0.0]])

## GetHitStumbleBwd: 1.11 m back, nearly all of it in the first 0.15 s.
static func stumble_backward() -> RootMotionClip:
	return make(1.0333, [[0.0, 0.0, 0.0], [0.1, -0.71, 0.0], [0.2, -0.95, 0.0],
		[0.45, -1.11, 0.0]])

## GetHitStumbleBwdFar: 3.30 m back over the first 0.95 s.
static func stumble_backward_far() -> RootMotionClip:
	return make(1.5, [[0.0, 0.0, 0.0], [0.15, -1.07, 0.0], [0.5, -2.43, 0.0],
		[0.8, -3.21, 0.0], [0.95, -3.296, 0.0]])

## GetHitStumbleBwdFar2, the hard stumble: 2.46 m back and 0.41 m right.
static func stumble_hard() -> RootMotionClip:
	return make(1.6333, [[0.0, 0.0, 0.0], [0.5, -1.32, 0.23], [1.0, -2.12, 0.34],
		[1.5, -2.47, 0.41], [1.6333, -2.458, 0.406]])

## EvadeRoll, the backward roll up off the back: 1.80 m back in 1.0 s.
static func evade_roll() -> RootMotionClip:
	return make(1.0, [[0.0, 0.0, 0.0], [0.15, -0.18, 0.0], [0.5, -1.10, 0.0],
		[0.6, -1.13, 0.0], [1.0, -1.797, 0.0]])

## RunTurn180: half a turn clockwise in 0.25 s; the sequence runs 1.03 s.
static func run_turn_180() -> RootMotionClip:
	return make(1.0333, [], [[0.0, 0.0], [0.1, deg_to_rad(109.0)], [0.2, deg_to_rad(179.0)],
		[0.25, PI]])

## StandTurn180Right: half a turn clockwise in 0.25 s; the sequence runs 0.8 s.
static func stand_turn_180() -> RootMotionClip:
	return make(0.8, [], [[0.0, 0.0], [0.1, deg_to_rad(92.0)], [0.2, deg_to_rad(169.0)],
		[0.25, PI]])

## JumpTurnFly: half a turn clockwise at an even rate over 0.3 s.
static func jump_turn_fly() -> RootMotionClip:
	return make(0.6, [], [[0.0, 0.0], [0.3, PI]])

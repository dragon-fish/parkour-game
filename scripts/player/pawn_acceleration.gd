class_name PawnAcceleration
extends RefCounted

# The original's two native acceleration functions, ported verbatim:
# ATdPawn::GetWalkAcceleration (MirrorsEdge.exe 0x012b57f0) and
# ATdPawn::GetSprintAcceleration (0x012bd920), plus the native builder that turns
# the time->speed SpeedCurve into the speed->acceleration AccelCurve they read
# (0x012c2db0). [ME:CONFIRMED emulated 15 §15.2] -- the original machine code was
# run under Ghidra's emulator on 300 random inputs and matched this arithmetic to
# its own 0.1 uu/s^2 rounding.
#
# Everything is in metres here; the conversion lives in the constants. The
# per-frame yaw input and the rounding are kept exactly as the original has
# them, including the parts that look accidental: the turn penalty depends on
# how far the view turned THIS frame, so it is frame-rate dependent, and the
# result is quantised to 0.1 uu/s^2. DO NOT smooth either of them away.
#
# Pure functions over plain values, so the arithmetic can be pinned against
# the emulated originals without a physics world.

## 1 uu = 1 cm.
const UU := 0.01
## Rotator units per radian (65536 per turn).
const ROTATOR_PER_RADIAN := 65536.0 / TAU
## The original rounds every component to 0.1 uu/s^2.
const ROUND_STEP := 0.1 * UU
## The SpeedCurve samples, per curve point, used to invert it. [ME:CONFIRMED emulated]
const INVERSE_SAMPLES_PER_POINT := 10
## Points in the generated AccelCurve, minus one. [ME:CONFIRMED emulated]
const ACCEL_CURVE_STEPS := 10
## A walk input never reads as more than this much "forward" when the energy
## decays: even dead ahead the budget drains at (1 - sqrt(0.9)) of full rate.
## [ME:CONFIRMED emulated]
const WALK_DECAY_FORWARD_CAP := 0.9
## The original's "this vector is zero" test on the normalised input.
const ZERO_INPUT := 1e-4

## Everything the two functions read off the pawn, in one place. A plain
## value bag so tests and callers build it the same way.
class State:
	var velocity := Vector3.ZERO
	## Unit forward and right of the PAWN's rotation (the original's
	## FRotationMatrix(Rotation) X and Y axes), horizontal.
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var falling := false
	## PhysicsVolume.GroundFriction of the volume the pawn is in.
	var ground_friction := 8.0
	## TdPawn.SpeedSprintEnergy, m/s. Written by both functions.
	var sprint_energy := 0.0

## TdPawn's speed parameters, metric. Built from PawnConfig by the caller.
class Params:
	var ground_speed := 7.2
	var speed_max_base_velocity := 4.0
	var speed_min_base_velocity := 0.1
	var speed_walk_velocity_acceleration_factor := 7.0
	var speed_strafe_velocity_acceleration_factor := 10.0
	var speed_sprint_velocity_acceleration_factor := 30.0
	var speed_energy_deceleration_time := 3.0
	var speed_energy_deceleration_exponent := 0.5
	var speed_turn_deceleration_factor := 10.0
	## (speed m/s, acceleration m/s^2), CIM_Linear, from build_accel_curve().
	var accel_curve := PackedVector2Array()

## FInterpCurve<float>::Eval for linear points: clamped to the end values.
static func eval_linear(points: PackedVector2Array, x: float) -> float:
	if points.is_empty():
		return 0.0
	if points.size() < 2 or x <= points[0].x:
		return points[0].y
	if x >= points[points.size() - 1].x:
		return points[points.size() - 1].y
	for i in range(1, points.size()):
		if x < points[i].x:
			var span: float = points[i].x - points[i - 1].x
			if span <= 0.0:
				return points[i - 1].y
			return lerpf(points[i - 1].y, points[i].y, (x - points[i - 1].x) / span)
	return points[points.size() - 1].y

## FInterpCurve::AddPoint: sorted by InVal, an equal key goes after the ones
## already there.
static func _add_point(points: PackedVector2Array, in_val: float, out_val: float) -> void:
	var i := 0
	while i < points.size() and points[i].x <= in_val:
		i += 1
	points.insert(i, Vector2(in_val, out_val))

## SpeedCurve (time s -> speed m/s) to AccelCurve (speed m/s -> m/s^2): invert
## the curve by sampling it, then forward-difference it over 0.5 / steps s at
## evenly spaced speeds. [ME:CONFIRMED emulated 15 §15.2]
static func build_accel_curve(speed_curve: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if speed_curve.is_empty():
		return out
	var t_max: float = speed_curve[speed_curve.size() - 1].x
	var v_max: float = speed_curve[speed_curve.size() - 1].y
	var n: int = speed_curve.size() * INVERSE_SAMPLES_PER_POINT
	var inverse := PackedVector2Array()
	for j in range(n + 1):
		var t: float = j * t_max / n
		_add_point(inverse, eval_linear(speed_curve, t), t)
	var h: float = 0.5 / ACCEL_CURVE_STEPS
	for i in range(ACCEL_CURVE_STEPS + 1):
		var s: float = i * v_max / ACCEL_CURVE_STEPS
		var t: float = eval_linear(inverse, s)
		_add_point(out, s, (eval_linear(speed_curve, t + h) - eval_linear(speed_curve, t)) * (1.0 / h))
	return out

## The original's int(PlayerInput.aTurn): this frame's yaw input in rotator
## units, truncated toward zero.
static func turn_units(yaw_delta_radians: float) -> int:
	return int(yaw_delta_radians * ROTATOR_PER_RADIAN)

static func _safe_normal(v: Vector3) -> Vector3:
	var sq := v.length_squared()
	if sq == 1.0:
		return v
	if sq < 1e-8:
		return Vector3.ZERO
	return v / sqrt(sq)

static func _is_zero(v: Vector3) -> bool:
	return absf(v.x) < ZERO_INPUT and absf(v.y) < ZERO_INPUT and absf(v.z) < ZERO_INPUT

static func _round(a: Vector3) -> Vector3:
	return Vector3(floorf(a.x / ROUND_STEP + 0.5), floorf(a.y / ROUND_STEP + 0.5), \
		floorf(a.z / ROUND_STEP + 0.5)) * ROUND_STEP

## ATdPawn::GetWalkAcceleration. `forward_in` / `strafe_in` are aForward /
## aStrafe. Decays s.sprint_energy. The turn input is accepted and ignored,
## as in the original: walking pays no turn penalty.
static func walk(s: State, p: Params, forward_in: float, strafe_in: float, _turn: int, dt: float) -> Vector3:
	var dir := _safe_normal(s.forward * forward_in + s.right * strafe_in)
	if _is_zero(dir):
		s.sprint_energy = 0.0
		return Vector3.ZERO
	if s.sprint_energy > 0.0:
		var ahead: float = clampf(dir.dot(s.forward), 0.0, WALK_DECAY_FORWARD_CAP)
		s.sprint_energy -= (p.ground_speed - p.speed_max_base_velocity) \
			* (1.0 - pow(ahead, p.speed_energy_deceleration_exponent)) \
			/ p.speed_energy_deceleration_time * dt
		s.sprint_energy = maxf(s.sprint_energy, 0.0)
	var top: float = p.speed_max_base_velocity - p.speed_min_base_velocity + s.sprint_energy
	var want_forward: float = dir.dot(s.forward) * p.speed_min_base_velocity + top * forward_in
	var want_right: float = dir.dot(s.right) * p.speed_min_base_velocity + top * strafe_in
	var a: Vector3 = s.forward * (want_forward - s.velocity.dot(s.forward)) * p.speed_walk_velocity_acceleration_factor \
		+ s.right * (want_right - s.velocity.dot(s.right)) * p.speed_strafe_velocity_acceleration_factor
	if not s.falling:
		a += s.velocity * s.ground_friction * 0.1
	return _round(a)

## ATdPawn::GetSprintAcceleration. Writes s.sprint_energy = speed above the
## base velocity. Light weapon (no weapon) only: this project carries none.
static func sprint(s: State, p: Params, forward_in: float, strafe_in: float, turn: int, dt: float) -> Vector3:
	var flat := Vector2(s.velocity.x, s.velocity.z)
	var speed: float = flat.length()
	var dir := _safe_normal(s.forward * forward_in + s.right * strafe_in)
	if _is_zero(dir):
		s.sprint_energy = 0.0
		return Vector3.ZERO
	s.sprint_energy = maxf(speed - p.speed_max_base_velocity, 0.0)
	var a: Vector3 = dir * eval_linear(p.accel_curve, speed)
	if not s.falling:
		# Turns the velocity toward the input: the gap between where the speed
		# points and where the stick points, closed at up to
		# SpeedSprintVelocityAccelerationFactor per second.
		var gap := Vector3(dir.x * speed - s.velocity.x, 0.0, dir.z * speed - s.velocity.z)
		var gap_len: float = gap.length()
		var steer: float = minf(p.speed_sprint_velocity_acceleration_factor * gap_len, gap_len / dt)
		a += _safe_normal(gap) * steer + s.velocity * s.ground_friction * 0.1
	# The turn penalty: a share of the velocity proportional to how far the
	# view turned this frame. Applies in the air too.
	a -= s.velocity * p.speed_turn_deceleration_factor * absf(float(turn)) / 32768.0
	return _round(a)

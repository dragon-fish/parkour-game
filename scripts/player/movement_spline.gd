class_name MovementSpline
extends RefCounted

# The original's TdMovementVolume spline natives, evaluated over an
# InterestLine. [ME:CONFIRMED emulated 0x012a9490 / 0x012a9580 / 0x012a9740,
# N7 §2]
#
# The original's spline is a QUADRATIC BEZIER, Start .. End with Middle as its
# control point; SplineLocations is that curve sampled at t = i / N (N =
# NumSplineSegments) in the editor and cooked. An extracted line's points ARE
# the cooked SplineLocations, so here the line's points are SplineLocations, N
# is one less than their count, and Start / End are the first and last.
# [ME:DERIVED] Middle is not on the line: it is the control point that
# reproduces the interior samples, by least squares -- exact for the
# original's own samples, the chord's middle for a two-point line.
#
# FindClosestPointOnDSpline, as written: the nearest of the first N points
# (End is never a candidate), searched from the hint by descending both ways
# when a hint is given; then the segment towards the nearer neighbour, the
# point projected on it WITHOUT a clamp, and the parameter (segment index) +
# |s| clamped to 0..1 -- a point behind the segment's start counts forward.

var locations: PackedVector3Array = PackedVector3Array()
var start: Vector3 = Vector3.ZERO
var middle: Vector3 = Vector3.ZERO
var end: Vector3 = Vector3.ZERO
## NumSplineSegments.
var num_segments: int = 1

## The spline of `line` where it stands now (a line may ride a mover).
static func of(line: InterestLine) -> MovementSpline:
	var s := MovementSpline.new()
	if line == null or line.curve == null:
		return s
	for i in line.curve.point_count:
		s.locations.append(line.to_global(line.curve.get_point_position(i)))
	s._fit()
	return s

## Start, End, NumSplineSegments, and the Middle the samples imply.
func _fit() -> void:
	var count: int = locations.size()
	if count == 0:
		return
	start = locations[0]
	end = locations[count - 1]
	num_segments = maxi(count - 1, 1)
	var sum := Vector3.ZERO
	var weight: float = 0.0
	for i in range(1, count - 1):
		var t: float = float(i) / float(num_segments)
		var w: float = 2.0 * t * (1.0 - t)
		sum += (locations[i] - start * (1.0 - t) * (1.0 - t) - end * t * t) * w
		weight += w * w
	middle = sum / weight if weight > 0.0 else (start + end) * 0.5

## GetLocationOnSpline(ParamT).
func location_at(param_t: float) -> Vector3:
	var t: float = clampf(param_t, 0.0, 1.0)
	var u: float = 1.0 - t
	return start * u * u + middle * 2.0 * t * u + end * t * t

## GetSlopeOnSpline(ParamT): the Bezier's direction there, normalised (zero
## when it has none).
func slope_at(param_t: float) -> Vector3:
	var t: float = clampf(param_t, 0.0, 1.0)
	var d: Vector3 = (middle - start) * (1.0 - t) + (end - middle) * t
	return PawnPhysics.safe_normal(d)

## FindClosestPointOnDSpline(InLocation, ClosestLocation, NParamT,
## LowestIndexHint): [ClosestLocation, NParamT]. A hint below 0 (the
## default) searches every candidate.
func find_closest(at: Vector3, hint: int = -1) -> Array:
	var count: int = locations.size()
	if count == 0:
		return [Vector3.ZERO, -1.0]
	if count < 2:
		return [locations[0], 0.0]
	var n: int = mini(num_segments, count)
	var idx: int = 0
	if hint < 0:
		var best: float = INF
		for i in n:
			var d: float = locations[i].distance_squared_to(at)
			if d < best:
				best = d
				idx = i
	else:
		var best: float = INF
		idx = hint
		for i in range(hint, n):
			var d: float = locations[i].distance_squared_to(at)
			if d >= best:
				break
			best = d
			idx = i
		# Past the points the original reads beyond its array; the descent
		# starts from the last point that exists instead.
		for i in range(mini(hint - 1, count - 1), -1, -1):
			var d: float = locations[i].distance_squared_to(at)
			if d >= best:
				break
			best = d
			idx = i
	idx = clampi(idx, 1, count - 1)
	if idx != count - 1 and locations[idx + 1].distance_squared_to(at) < locations[idx - 1].distance_squared_to(at):
		idx += 1
	var a: Vector3 = locations[idx - 1]
	var seg: Vector3 = locations[idx] - a
	var length_sq: float = seg.length_squared()
	if length_sq <= 0.0:
		return [a, float(idx - 1)]
	var s: float = (at - a).dot(seg) / length_sq
	return [a + seg * s, float(idx - 1) + clampf(absf(s), 0.0, 1.0)]

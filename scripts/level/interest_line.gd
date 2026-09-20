@tool
class_name InterestLine
extends Path3D

# A line in the level that a hand or a foot can interact ALONG. 05 §5.6.5: the
# original marks every "along a line" move (zipline, swing, balance) with a
# volume, and never infers one from geometry -- a cable and a power line look
# the same to a probe.
#
# The line is a Curve3D so it can sag: a zipline may be a drooping curve,
# not necessarily straight. A straight line is its two-point case.
#
# The Area3D is BUILT HERE, not placed by hand: the level author draws the
# curve and nothing else. Capsules are laid between consecutive baked points.
#
# Assumes the node is unscaled. closest_offset() / sample() convert through
# to_local()/to_global(), which is exact for translation and rotation; a scale
# would change arc lengths the curve's own baked table knows nothing about.

enum Kind { ZIPLINE, SWING, BALANCE, LADDER, LEDGE_WALK }

## The reach a line of each kind starts with, metres. Picking a kind in the
## inspector (or in code) writes the kind's entry into reach_radius, which
## stays editable after that -- the number a level author sees IS the number
## the volume is built from.
##
## ONE NUMBER, NOT THE ORIGINAL'S VOLUME. An extracted level used to take this
## from the box the original draws around each line, which reads 2.2 to 6.2 m.
## That box is not a reach: a TdSwingVolume says WHERE the move is allowed and
## which bar it is about -- the builder already uses it for that, clipping bars
## against the hull -- while how far a hand stretches is a matter of feel. Run
## as a reach it put a capsule across the whole width of the Subway's tunnel,
## so the bar was catchable from the far rail, and 182 such volumes tracking
## the geometry they now covered took the chapter to 4 fps.
##
## A BAR REACHES FURTHER: at 0.6 m a jump at a swing bar had to be nearly
## exact, and a fall past it was missed outright. 1.0 m was tried on the
## Stormdrain boss bar and holds.
## A CABLE REACHES FURTHEST. At 0.6 m one was hard to catch at speed and 1.2 m
## was still short. 2.4 m is the value being tried, and it is only safe at all
## because the pull onto the line now runs at a fixed SPEED -- see
## LineMove.approach_seconds(). Under the old fixed time, every metre added
## here was a metre the body got yanked across in the same 0.1 s.
## A ledge stays at 0.6 m so it does not catch a body that only passes near
## it. DO NOT widen it back to cover a wide walkway feeding a narrow ledge:
## that pulled bodies off climbs and wall runs onto ledges overhead.
const KIND_REACH := {
	Kind.ZIPLINE: 2.4,
	Kind.SWING: 1.0,
	Kind.BALANCE: 0.6,
	Kind.LADDER: 0.6,
	Kind.LEDGE_WALK: 0.6,
}

@export var kind: Kind = Kind.ZIPLINE:
	set(value):
		kind = value
		reach_radius = KIND_REACH[value]
## How far from the line a body counts as able to reach it, in metres.
## Seeded from KIND_REACH whenever `kind` is set; a value written after that
## (a scene file lists kind before this property) wins.
@export var reach_radius: float = 0.6
## Lets a level forbid THIS line by name -- see Status.Effect.BLOCK_INTEREST_LINE.
## Empty means the line cannot be singled out; it still obeys a blanket ban on
## its whole kind.
@export var tag: StringName = &""

## Half the span the finite-difference tangent is taken over.
const TANGENT_STEP := 0.05

## One colour per kind: the editor gizmo's and the trigger overlay's (F3),
## which draw nothing else of a line at runtime -- the level's own cables and
## poles are what the player sees.
const KIND_COLORS := {
	Kind.ZIPLINE: Color(0.3, 0.8, 1.0),
	Kind.SWING: Color(1.0, 0.6, 0.2),
	Kind.BALANCE: Color(0.95, 0.85, 0.2),
	Kind.LADDER: Color(0.95, 0.35, 0.35),
	Kind.LEDGE_WALK: Color(0.7, 0.45, 1.0),
}

var _area: Area3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		# EDITOR CONVENIENCE ONLY: a fresh line starts as a 3 m vertical, so
		# there is always a quick starting point to drag from instead of
		# drawing from nothing. Everything else about this node (volume,
		# rope) is runtime-built and stays that way.
		if curve == null or curve.point_count == 0:
			curve = Curve3D.new()
			curve.add_point(Vector3.ZERO)
			curve.add_point(Vector3(0.0, 3.0, 0.0))
		return
	add_to_group("interest_lines")
	_build_area()

func length() -> float:
	return curve.get_baked_length() if curve != null else 0.0

## The node's own -Z, flattened. Read by two kinds, which mean OPPOSITE things
## by it: on a LADDER it is the side the body climbs from (out of the wall), on
## a LEDGE_WALK it points AT the wall the body walks along. Other kinds never
## ask.
func front() -> Vector3:
	var f: Vector3 = -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

## Arc length of the point on the line nearest `world_pos`.
func closest_offset(world_pos: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_pos))

## World position and unit tangent at arc length `offset`, clamped to the line.
##
## The tangent is a finite difference rather than sample_baked_with_rotation():
## which axis that transform points "forward" is a convention worth not
## depending on, and a difference of two positions has no convention to get
## wrong.
func sample(offset: float) -> Dictionary:
	var total: float = length()
	var s: float = clampf(offset, 0.0, total)
	var here: Vector3 = to_global(curve.sample_baked(s))
	var ahead: Vector3 = to_global(curve.sample_baked(minf(s + TANGENT_STEP, total)))
	var behind: Vector3 = to_global(curve.sample_baked(maxf(s - TANGENT_STEP, 0.0)))
	var tangent: Vector3 = ahead - behind
	if tangent.length_squared() < 0.000001:
		tangent = Vector3.FORWARD
	return {"position": here, "tangent": tangent.normalized()}

func _build_area() -> void:
	if curve == null or curve.point_count < 2:
		push_error("InterestLine '%s' needs a curve with at least two points" % name)
		return
	_area = Area3D.new()
	_area.name = "Volume"
	# Only the body, never the level it runs through -- see
	# Arena.PLAYER_LAYER. A swing volume in a tunnel otherwise tracks
	# the tunnel, one capsule at a time.
	_area.collision_mask = Arena.PLAYER_LAYER
	var points: PackedVector3Array = curve.get_baked_points()
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg_length: float = (b - a).length()
		if seg_length < 0.001:
			continue
		var capsule := CapsuleShape3D.new()
		capsule.radius = reach_radius
		capsule.height = seg_length + 2.0 * reach_radius
		var shape := CollisionShape3D.new()
		shape.shape = capsule
		shape.transform = _segment_transform(a, b, seg_length)
		_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	add_child(_area)

## An orthonormal basis whose local Y runs along a..b, centred between them --
## what both a CapsuleShape3D and a CylinderMesh need, since both take their
## height along local Y. The other two axes only need to be perpendicular.
func _segment_transform(a: Vector3, b: Vector3, seg_length: float) -> Transform3D:
	var y: Vector3 = (b - a) / seg_length
	var helper: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = helper.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_interest_line"):
		body.enter_interest_line(self)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_interest_line"):
		body.exit_interest_line(self)

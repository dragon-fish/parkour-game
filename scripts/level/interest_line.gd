@tool
class_name InterestLine
extends Path3D

# A line in the level that a hand or a foot can interact ALONG. 05 §5.6.5: the
# original marks every "along a line" move (zipline, swing, balance) with a
# volume, and never infers one from geometry -- a cable and a power line look
# the same to a probe.
#
# The line is a Curve3D so it can sag: the owner's own note is that a zipline
# "有可能是下垂的曲线，不一定是直线". A straight line is its two-point case.
#
# The Area3D is BUILT HERE, not placed by hand: the level author draws the
# curve and nothing else. Capsules are laid between consecutive baked points.
#
# Assumes the node is unscaled. closest_offset() / sample() convert through
# to_local()/to_global(), which is exact for translation and rotation; a scale
# would change arc lengths the curve's own baked table knows nothing about.

enum Kind { ZIPLINE, SWING, BALANCE, LADDER }

@export var kind: Kind = Kind.ZIPLINE
## How far from the line a body counts as able to reach it, in metres.
@export var reach_radius: float = 0.6

## Half the span the finite-difference tangent is taken over.
const TANGENT_STEP := 0.05

## The rope's own thickness, metres. Cosmetic only -- reach_radius, not this,
## is what a body actually catches against.
const ROPE_RADIUS := 0.02

var _area: Area3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		# EDITOR CONVENIENCE ONLY: a fresh line starts as a 3 m vertical --
		# ✅ the owner: "怎么快速拉一个垂直向上的线啊" -- drag the top point
		# from there instead of drawing from nothing. Everything else about
		# this node (volume, rope) is runtime-built and stays that way.
		if curve == null or curve.point_count == 0:
			curve = Curve3D.new()
			curve.add_point(Vector3.ZERO)
			curve.add_point(Vector3(0.0, 3.0, 0.0))
		return
	add_to_group("interest_lines")
	_build_area()
	_build_rope()

func length() -> float:
	return curve.get_baked_length() if curve != null else 0.0

## The side a body climbs this line from: the node's own -Z, flattened.
## Meaningful for LADDER (the authored "正面"); other kinds never ask.
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

## A whitebox interactable must be visible -- the marker IS the rope. Built
## the same way the reach volume above is, one CylinderMesh per baked segment,
## sharing a single material. Runtime children only, exactly like the Area3D:
## nothing here is packed, so the committed scenes this line might sit in are
## untouched by it.
func _build_rope() -> void:
	if curve == null or curve.point_count < 2:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.15, 0.17)
	var points: PackedVector3Array = curve.get_baked_points()
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var seg_length: float = (b - a).length()
		if seg_length < 0.001:
			continue
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = ROPE_RADIUS
		cylinder.bottom_radius = ROPE_RADIUS
		cylinder.height = seg_length
		cylinder.material = material
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = cylinder
		mesh_instance.transform = _segment_transform(a, b, seg_length)
		add_child(mesh_instance)

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

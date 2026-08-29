@tool
class_name BarbedWire
extends Path3D

# Concertina wire along a curve: a coil wound about the path, with barbs
# sticking out of it. GEOMETRY ONLY.
#
# It carries no hazard volume and no collision. A level that wants the wire to
# hurt puts a ModifierVolume beside it; a level that wants the wall unclimbable
# gives the wall a collider the ledge probe will not accept -- Probes.ledge_query()
# refuses any surface whose normal.y is below PawnConfig.walkable_floor_z (0.71),
# so a ridge taller than half its width is enough. Keeping those three apart is
# what lets a run of wire be decorative in one place and lethal in another.
#
# THE CURVE IS THE AXIS THE COIL IS WOUND ABOUT, not the wire itself. Drag the
# path along the top of a wall and the coil follows it.
#
# One ArrayMesh, not one node per segment. InterestLine builds its rope as a
# MeshInstance3D per baked segment, which is fine for a zipline's thirty-odd
# points; a coil samples several times per turn and would reach thousands.
#
# Runtime child only: nothing here is packed, so a scene holding one of these
# stores the curve and nothing else.

## Turns of the coil per metre of path. The single dial for how tight the
## concertina reads.
@export var coils_per_metre: float = 3.0:
	set(value):
		coils_per_metre = maxf(value, 0.01)
		_rebuild()

## How far the coil stands off the path. This is the loop's radius, not the
## wire's.
@export var coil_radius: float = 0.3:
	set(value):
		coil_radius = maxf(value, 0.001)
		_rebuild()

## The strand's own thickness.
@export var wire_radius: float = 0.02:
	set(value):
		wire_radius = maxf(value, 0.001)
		_rebuild()

## Sides of the tube's cross-section. Three is a visible triangle in close-up;
## above six buys nothing at the size wire is actually seen from.
@export_range(3, 8, 1) var wire_sides: int = 5:
	set(value):
		wire_sides = clampi(value, 3, 8)
		_rebuild()

## Points sampled per turn. Too few and the coil reads as a polygon; this is
## the biggest lever on the triangle count, so it is the one to drop first when
## the warning fires.
@export_range(4, 24, 1) var samples_per_coil: int = 12:
	set(value):
		samples_per_coil = clampi(value, 4, 24)
		_rebuild()

## Barbs per metre of PATH, not of wire -- the wire is several times longer
## than the path it wraps, so this stays meaningful when the coil tightens.
@export var barbs_per_metre: float = 5.0:
	set(value):
		barbs_per_metre = maxf(value, 0.0)
		_rebuild()

@export var barb_length: float = 0.07:
	set(value):
		barb_length = maxf(value, 0.0)
		_rebuild()

@export var barb_radius: float = 0.012:
	set(value):
		barb_radius = maxf(value, 0.001)
		_rebuild()

## Which barbs land where. FIXED, NOT RANDOM PER RUN: the editor and the game
## have to agree about the same piece of wire, and a run that reshuffled itself
## on every reload would make a level look different every time it was opened.
@export var barb_seed: int = 0:
	set(value):
		barb_seed = value
		_rebuild()

## Left null for the default dark steel.
@export var material: Material = null:
	set(value):
		material = value
		_rebuild()

## Above this the configuration warning fires. Not a limit -- a long run of
## tight coil legitimately costs this much -- but a number worth seeing before
## an editor starts to crawl.
const TRIANGLE_BUDGET := 60000

var _mesh_instance: MeshInstance3D = null

func _ready() -> void:
	if not curve_changed.is_connected(_rebuild):
		curve_changed.connect(_rebuild)
	_rebuild()

## How many triangles the current settings ask for. Exposed because it is the
## one number an author needs when the warning fires and they have to choose
## which dial to give up.
func triangle_estimate() -> int:
	if curve == null:
		return 0
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return 0
	var rings: int = int(length * coils_per_metre * float(samples_per_coil))
	var tube: int = rings * wire_sides * 2
	var barbs: int = int(length * barbs_per_metre) * 4
	return tube + barbs

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if curve == null or curve.point_count < 2:
		warnings.append("The curve needs at least two points: there is no path to wind a coil about.")
		return warnings
	if curve.get_baked_length() <= 0.001:
		warnings.append("The curve has no length: every point sits on top of the last.")
	if wire_radius >= coil_radius:
		warnings.append("wire_radius is not smaller than coil_radius, so the coil closes into a rod.")
	var triangles: int = triangle_estimate()
	if triangles > TRIANGLE_BUDGET:
		warnings.append("About %d triangles. samples_per_coil is the cheapest dial to drop." % triangles)
	return warnings

func _rebuild() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()
		_mesh_instance = null
	update_configuration_warnings()
	if curve == null or curve.point_count < 2:
		return
	var length: float = curve.get_baked_length()
	if length <= 0.001 or wire_radius >= coil_radius:
		return
	var built: ArrayMesh = _build_mesh(length)
	if built == null:
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Wire"
	_mesh_instance.mesh = built
	add_child(_mesh_instance)

func _build_mesh(length: float) -> ArrayMesh:
	var centres: PackedVector3Array = PackedVector3Array()
	var radials: PackedVector3Array = PackedVector3Array()
	_sample_coil(length, centres, radials)
	if centres.size() < 2:
		return null

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_tube(tool, centres)
	_add_barbs(tool, length, centres, radials)
	tool.set_material(material if material != null else _default_material())
	return tool.commit()

## Walks the path once, emitting the coil's centre line and, beside each point,
## the direction that points away from the axis there -- which is where a barb
## on that point has to face.
func _sample_coil(length: float, centres: PackedVector3Array, radials: PackedVector3Array) -> void:
	var step: float = 1.0 / maxf(coils_per_metre * float(samples_per_coil), 0.001)
	var count: int = int(length / step) + 1
	# PARALLEL TRANSPORT, not a Frenet frame. Frenet is built from the curve's
	# second derivative and is undefined on a straight run -- which is what
	# most wire is -- so it flips the coil about at random where the path
	# happens to be flat. Carrying the frame forward keeps it continuous, and
	# on a straight line it simply never turns.
	var previous_tangent: Vector3 = _tangent_at(0.0, length)
	var normal: Vector3 = _seed_normal(previous_tangent)
	for i in range(count):
		var distance: float = minf(float(i) * step, length)
		var tangent: Vector3 = _tangent_at(distance, length)
		var turn: Vector3 = previous_tangent.cross(tangent)
		if turn.length_squared() > 0.000001:
			var angle: float = previous_tangent.angle_to(tangent)
			normal = normal.rotated(turn.normalized(), angle)
		# Re-orthogonalised every step: the rotations above accumulate float
		# error, and a frame that drifts off the tangent slowly shears the coil.
		normal = (normal - tangent * normal.dot(tangent)).normalized()
		previous_tangent = tangent
		var binormal: Vector3 = tangent.cross(normal)
		var theta: float = TAU * coils_per_metre * distance
		var radial: Vector3 = normal * cos(theta) + binormal * sin(theta)
		centres.append(curve.sample_baked(distance) + radial * coil_radius)
		radials.append(radial)

func _tangent_at(distance: float, length: float) -> Vector3:
	var ahead: float = minf(distance + 0.01, length)
	var behind: float = maxf(distance - 0.01, 0.0)
	var delta: Vector3 = curve.sample_baked(ahead) - curve.sample_baked(behind)
	if delta.length_squared() < 0.000001:
		return Vector3.FORWARD
	return delta.normalized()

## Any unit vector perpendicular to the tangent will do to start the transport;
## only its continuity from there matters.
func _seed_normal(tangent: Vector3) -> Vector3:
	var helper: Vector3 = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return helper.cross(tangent).normalized()

## A tube swept along the coil's centre line. Normals are the radial direction
## from that centre line, which is exact for a tube -- generate_normals() would
## average across the barbs sharing a position and round the strand off.
func _add_tube(tool: SurfaceTool, centres: PackedVector3Array) -> void:
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in range(centres.size()):
		var forward: Vector3 = _centre_tangent(centres, i)
		var side: Vector3 = _seed_normal(forward)
		var up: Vector3 = forward.cross(side)
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in range(wire_sides):
			var a: float = TAU * float(k) / float(wire_sides)
			var out: Vector3 = side * cos(a) + up * sin(a)
			ring.append(centres[i] + out * wire_radius)
			ring_normals.append(out)
		rings.append(ring)
		normals.append(ring_normals)
	for i in range(rings.size() - 1):
		for k in range(wire_sides):
			var n: int = (k + 1) % wire_sides
			_quad(tool,
				rings[i][k], normals[i][k], rings[i][n], normals[i][n],
				rings[i + 1][n], normals[i + 1][n], rings[i + 1][k], normals[i + 1][k])

func _centre_tangent(centres: PackedVector3Array, i: int) -> Vector3:
	var a: Vector3 = centres[maxi(i - 1, 0)]
	var b: Vector3 = centres[mini(i + 1, centres.size() - 1)]
	var delta: Vector3 = b - a
	if delta.length_squared() < 0.000001:
		return Vector3.FORWARD
	return delta.normalized()

## Barbs are spread over the PATH and then looked up on the coil, so tightening
## the coil moves them around the loop rather than multiplying them.
func _add_barbs(tool: SurfaceTool, length: float, centres: PackedVector3Array, \
		radials: PackedVector3Array) -> void:
	var count: int = int(length * barbs_per_metre)
	if count <= 0 or barb_length <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = barb_seed
	for i in range(count):
		var at: int = rng.randi_range(0, centres.size() - 1)
		var base: Vector3 = centres[at]
		var out: Vector3 = radials[at]
		var tip: Vector3 = base + out * barb_length
		var side: Vector3 = _seed_normal(out)
		var up: Vector3 = out.cross(side)
		# Four faces, flat-shaded: a barb is two or three centimetres of metal
		# and nothing about it is worth a smooth normal.
		for k in range(4):
			var a: float = TAU * float(k) / 4.0
			var b: float = TAU * float(k + 1) / 4.0
			var p0: Vector3 = base + (side * cos(a) + up * sin(a)) * barb_radius
			var p1: Vector3 = base + (side * cos(b) + up * sin(b)) * barb_radius
			var face: Vector3 = (p1 - p0).cross(tip - p0)
			if face.length_squared() < 0.000000001:
				continue
			var n: Vector3 = face.normalized()
			tool.set_normal(n)
			tool.add_vertex(p0)
			tool.set_normal(n)
			tool.add_vertex(p1)
			tool.set_normal(n)
			tool.add_vertex(tip)

func _quad(tool: SurfaceTool, a: Vector3, na: Vector3, b: Vector3, nb: Vector3, \
		c: Vector3, nc: Vector3, d: Vector3, nd: Vector3) -> void:
	tool.set_normal(na)
	tool.add_vertex(a)
	tool.set_normal(nb)
	tool.add_vertex(b)
	tool.set_normal(nc)
	tool.add_vertex(c)
	tool.set_normal(na)
	tool.add_vertex(a)
	tool.set_normal(nc)
	tool.add_vertex(c)
	tool.set_normal(nd)
	tool.add_vertex(d)

func _default_material() -> StandardMaterial3D:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.22, 0.22, 0.24)
	steel.metallic = 0.7
	steel.roughness = 0.45
	return steel

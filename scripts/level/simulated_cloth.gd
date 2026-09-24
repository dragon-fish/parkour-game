class_name SimulatedCloth
extends SoftBody3D
## What the original's PhysX cloth had that a SoftBody3D does not: wind, and a
## blend of the simulation over the rest pose.
##
## Both are per placement in the original, on the SkeletalMeshComponent, and
## the level builder writes them here. Nothing runs for a cloth with neither.

## ClothWind turned into world space, uu / 100. UDK's declaration: the force on
## each vertex is "based on the dot product between the wind vector and the
## surface normal". A strip lying along the wind takes none; let it droop and
## its face turns into the wind and is lifted back -- which is the flapping.
@export var wind := Vector3.ZERO
## [ME:CONFIRMED] ClothBlendWeight: how much of the simulation is drawn over the
## rest pose. The vent strips carry 0.1 to 0.3 -- blown hard and drawn at a
## fraction of it, which is a flutter rather than a flapping.
@export_range(0.0, 1.0) var blend_weight := 1.0
## Acceleration per unit of `wind`, in m/s^2. A dial: the original's unit for
## ClothWind and the gravity its cloth fell under are both unmeasured, so what
## one metre of wind is worth is judged by eye. The original's SP01a vent strips
## stand out into the duct and flap: at 1 they hang limp, from about 5 they
## flap, at 10 they beat about the horizontal every second or so.
@export var wind_scale := 10.0

## How far past its rest pose a cloth may reach and still count as in view.
const SWING_M := 0.5

var _indices := PackedInt32Array()
## Vertices some face uses. A soft body drops the rest, and asking for their
## position is an engine error.
var _used := PackedInt32Array()
## One visual vertex per simulated point. A soft body welds vertices sharing a
## position into one point, so pushing every copy would push a seam twice.
var _pushed := PackedInt32Array()
var _rest := PackedVector3Array()
var _drawn: MeshInstance3D
## The rest pose's bounds, world space, grown by how far a cloth swings.
var _corners := PackedVector3Array()
var _drawn_arrays := []
var _drawn_material: Material
## +1 or -1: which way this mesh's winding puts a face normal relative to the
## normals it was authored with, so the drawn copy is lit on the right side.
var _winding := 1.0


func _ready() -> void:
	SettingsStore.follow_physics_props(self)
	if wind == Vector3.ZERO and blend_weight >= 1.0:
		set_physics_process(false)
		return
	var arrays := mesh.surface_get_arrays(0)
	_indices = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# DO NOT take global_transform as the rest frame: a soft body moves its own
	# node about once it simulates. The parent's frame and the local transform
	# are what the points started from.
	var frame := transform
	if get_parent() is Node3D:
		frame = (get_parent() as Node3D).global_transform * transform
	_rest.resize(vertices.size())
	for i in vertices.size():
		_rest[i] = frame * vertices[i]
	var used := {}
	for index in _indices:
		used[index] = true
	# The builder puts a cloth's vertices in the order the soft body numbers its
	# points (GeometryBuilder._cloth_mesh), which is what keeps Jolt's pin guard
	# from refusing free ones. A mesh laid out any other way -- a PlaneMesh is
	# fine, it already is in that order -- gets an engine error a tick for every
	# vertex the guard misreads, and no wind on it.
	var pinned := {}
	for i: int in get("pinned_points"):
		pinned[vertices[i]] = true
	var seen := {}
	for i in vertices.size():
		if not used.has(i):
			continue
		_used.append(i)
		if pinned.has(vertices[i]) or seen.has(vertices[i]):
			continue
		seen[vertices[i]] = true
		_pushed.append(i)
	if blend_weight < 1.0:
		_start_drawing(arrays, frame)
	var bounds := mesh.get_aabb().grow(SWING_M)
	for corner in 8:
		_corners.append(frame * bounds.get_endpoint(corner))


func _physics_process(_delta: float) -> void:
	if not _in_view():
		return
	var points := _rest.duplicate()
	for i in _used:
		points[i] = get_point_transform(i)
	var normals := _normals(points)
	if wind != Vector3.ZERO and not _pushed.is_empty():
		var acceleration := wind * wind_scale
		var point_mass := total_mass / _pushed.size()
		for i in _pushed:
			var n := normals[i]
			apply_force(i, n * n.dot(acceleration) * point_mass)
	if _drawn != null:
		_draw(points, normals)


## The physics_props setting. PROCESS_MODE_DISABLED takes a soft body out of
## the server and putting it back resumes the simulation where it left off;
## PackagePresence switches the placement node above this one, never this.
## DO NOT query a disabled soft body's points: under Jolt that is an error with
## no physics space to ask -- which is why this script stops with it.
func simulate(on: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## [ME:CONFIRMED] every cloth component in the game sets
## bAutoFreezeClothWhenNotRendered. Here the wind and the blend stop, which are
## what this script costs: a GDScript pass over every point, every tick.
##
## Tested against the camera's frustum on the CPU. DO NOT swap in a
## VisibleOnScreenNotifier3D: it reads the renderer's culling, which a headless
## run does not have, so nothing could check that the wind blows at all.
func _in_view() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	for plane in camera.get_frustum():
		var outside := true
		for corner in _corners:
			if not plane.is_point_over(corner):
				outside = false
				break
		if outside:
			return false
	return true


## Per-vertex normals from the points as they stand, area-weighted, on the side
## the mesh's winding puts them.
func _normals(points: PackedVector3Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(points.size())
	for t in range(0, _indices.size(), 3):
		var a := _indices[t]
		var b := _indices[t + 1]
		var c := _indices[t + 2]
		var face := (points[b] - points[a]).cross(points[c] - points[a])
		normals[a] += face
		normals[b] += face
		normals[c] += face
	for i in normals.size():
		normals[i] = normals[i].normalized() * _winding
	return normals


## The simulation is hidden and a copy drawn in its place, the rest pose moved
## toward it by blend_weight. layers = 0 rather than visible = false: a hidden
## soft body leaves the simulation.
func _start_drawing(arrays: Array, frame: Transform3D) -> void:
	var authored: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	if not authored.is_empty() and not _used.is_empty():
		var first := _used[0]
		var agree := _normals(_rest)[first].dot(frame.basis * authored[first])
		_winding = -1.0 if agree < 0.0 else 1.0
	_drawn_material = get_surface_override_material(0)
	if _drawn_material == null:
		_drawn_material = mesh.surface_get_material(0)
	_drawn_arrays = arrays.duplicate()
	_drawn_arrays[Mesh.ARRAY_TANGENT] = null
	_drawn = MeshInstance3D.new()
	_drawn.name = "Drawn"
	_drawn.top_level = true
	_drawn.mesh = ArrayMesh.new()
	_drawn.material_override = material_override
	_drawn.cast_shadow = cast_shadow
	_drawn.visibility_range_end = visibility_range_end
	add_child(_drawn)
	_drawn.global_transform = Transform3D.IDENTITY
	layers = 0
	# The rest pose, until the first tick draws over it -- and for good, with
	# physics props off, when no tick ever does.
	_draw(_rest, _normals(_rest))


func _draw(points: PackedVector3Array, normals: PackedVector3Array) -> void:
	var vertices := PackedVector3Array()
	vertices.resize(_rest.size())
	for i in _rest.size():
		vertices[i] = _rest[i].lerp(points[i], blend_weight)
	_drawn_arrays[Mesh.ARRAY_VERTEX] = vertices
	_drawn_arrays[Mesh.ARRAY_NORMAL] = normals
	var drawn := _drawn.mesh as ArrayMesh
	drawn.clear_surfaces()
	drawn.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _drawn_arrays)
	drawn.surface_set_material(0, _drawn_material)

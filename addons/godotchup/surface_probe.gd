@tool
extends RefCounted

# Finds the surface under a viewport ray, without physics.
#
# DO NOT reach for intersect_ray() here. The editor runs no physics step, so a
# StaticBody's shape sits in no space that can be queried -- the call returns
# nothing and the failure looks like a missed click rather than a wrong API.
# Culling mesh instances against the ray and intersecting their triangles works
# in the editor, and has the better property besides: a surface needs no
# collider to be drawn on.
#
# The approach is the one Godot 3D Cursor takes (addons/godot_3d_cursor, ISC).

## Returns {"position": Vector3, "normal": Vector3, "node": Node} in world
## space, or {} when the ray meets nothing.
static func raycast(camera: Camera3D, from: Vector3, to: Vector3,
		scene_root: Node) -> Dictionary:
	var world: World3D = camera.get_world_3d()
	if world == null:
		return {}
	var best: Dictionary = {}
	var best_distance: float = INF
	for id in RenderingServer.instances_cull_ray(from, to, world.scenario):
		var candidate: Object = instance_from_id(id)
		if not (candidate is Node):
			continue
		var node: Node = candidate as Node
		# Culling sees the whole scenario, which includes whatever the editor
		# itself is drawing. Only geometry belonging to the scene being edited
		# is a legitimate surface to build on.
		if scene_root != null and not scene_root.is_ancestor_of(node) and node != scene_root:
			continue
		var hit: Dictionary = {}
		if node is MeshInstance3D:
			hit = _hit_mesh(node as MeshInstance3D, from, to)
		elif node is CSGShape3D:
			hit = _hit_csg(node as CSGShape3D, from, to)
		if hit.is_empty():
			continue
		var distance: float = from.distance_to(hit["position"])
		if distance < best_distance:
			best_distance = distance
			best = hit
	return best

static func _hit_faces(faces: PackedVector3Array, owner_transform: Transform3D,
		from: Vector3, to: Vector3, node: Node) -> Dictionary:
	if faces.is_empty():
		return {}
	var triangles := TriangleMesh.new()
	if not triangles.create_from_faces(faces):
		return {}
	var inverse: Transform3D = owner_transform.affine_inverse()
	var hit: Dictionary = triangles.intersect_segment(inverse * from, inverse * to)
	if hit.is_empty():
		return {}
	return {
		"position": owner_transform * (hit["position"] as Vector3),
		"normal": (owner_transform.basis * (hit["normal"] as Vector3)).normalized(),
		"node": node,
	}

static func _hit_mesh(instance: MeshInstance3D, from: Vector3, to: Vector3) -> Dictionary:
	if instance.mesh == null:
		return {}
	return _hit_faces(instance.mesh.get_faces(), instance.global_transform, from, to, instance)

static func _hit_csg(shape: CSGShape3D, from: Vector3, to: Vector3) -> Dictionary:
	# Only the root of a CSG tree has a resolved shape; a child operand's own
	# geometry is not what is on screen.
	var root: CSGShape3D = shape
	while root != null and not root.is_root_shape():
		var parent: Node = root.get_parent()
		root = parent as CSGShape3D
	if root == null:
		return {}
	var baked: ArrayMesh = root.bake_static_mesh()
	if baked == null or baked.get_surface_count() == 0:
		return {}
	return _hit_faces(baked.get_faces(), root.global_transform, from, to, root)

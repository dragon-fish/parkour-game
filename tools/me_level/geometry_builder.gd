@tool
extends RefCounted

# Geometry scene of one extracted level: placements referencing the mesh
# library, the compiled BSP, and the original's lights. Nothing editable lives
# here -- the shell holds interactions, and the scene is regenerated freely.

const Common := preload("res://tools/me_level/me_level_common.gd")
const MeLibrary := preload("res://tools/me_level/mesh_library.gd")
const ENVIRONMENT_SCRIPT := preload("res://tools/me_level/me_environment.gd")
const LIGHTS_SCRIPT := preload("res://tools/me_level/me_lights.gd")

## Meshes a hand grips. InterestLine volumes drive those moves, so a solid mesh
## only stops the capsule short of the line it is reaching for.
## ZipLineBase_01_Line is the cable itself; 01b/01c/01d are the brackets it
## runs through. The 5.6 m S_ZipLineBase_01 post is deliberately absent:
## running through it reads wrong. A geometric test (does a hand line run
## along the mesh) was measured against this list and lost: it also freed
## billboards and catwalk supports a ladder runs past, and missed every swing
## pole, whose line is not in the manifest.
const GRIP_MESH_MARKERS: Array[String] = ["LadderSystem", "SwingPole",
		"ZipLineBase_01_Line", "ZipLineBase_01b", "ZipLineBase_01c",
		"ZipLineBase_01d", "S_Cable_01"]
## Climbable drainpipes use the same generic segments as the rooftop pipe runs
## a runner steps over, so a pipe is passable only where a ladder line runs
## along it. DO NOT match pipes by name alone.
const PIPE_GRIP_REACH_M := 0.6

const BSP_MATERIAL_FAMILY := "roof"

## Metres from the camera past which an extracted light fades out, and over
## how far. Stormdrain's densest view (the pillar hall) keeps 336 lights
## within 80 m, under project.godot's max_clustered_elements. A dial.
## A placement is not drawn past this many times its own size, within
## [VISIBLE_RANGE_MIN, VISIBLE_RANGE_MAX] metres. A dial.
const VISIBLE_RANGE_PER_METRE := 40.0
const VISIBLE_RANGE_MIN := 30.0
const VISIBLE_RANGE_MAX := 3000.0
## Placements at least this many metres across go into the level's occluder.
const OCCLUDER_MIN_EXTENT := 40.0

const LIGHT_FADE_BEGIN := 60.0
const LIGHT_FADE_LENGTH := 20.0


func build(manifest: Dictionary, root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	var geometry := Node3D.new()
	geometry.name = "Geometry"
	root.add_child(geometry)
	# InterpActors: moved by the level's Matinee nodes, so kept apart under
	# names those can address. AnimatableBody3D carries whoever stands on it.
	# Added LAST: shells override Lights by index (see sp01_edge.tscn).
	var movers := Node3D.new()
	movers.name = "Movers"
	var pipe_line := _ladder_samples(manifest["annotations"])
	var names := Common.NameAllocator.new()
	var library := {}
	var counts := {none = 0, simple = 0, per_poly = 0, grip = 0, stretched = 0}
	_stretched_shapes.clear()
	for placement: Dictionary in manifest["placements"]:
		var mesh_name: String = placement["mesh"]
		if not library.has(mesh_name):
			library[mesh_name] = load(MeLibrary.path_for(mesh_name))
		var mesh: ArrayMesh = library[mesh_name]
		var collision: String = placement["collision"]
		if collision != "none" and _is_grip(mesh_name, placement, pipe_line):
			collision = "none"
			counts.grip += 1
		counts[collision] += 1
		var mover: bool = placement.get("mover", false)
		var node: Node3D
		if mover:
			node = AnimatableBody3D.new()
			node.name = Common.mover_name(placement["package"], placement["name"])
		else:
			node = Node3D.new() if collision == "none" else StaticBody3D.new()
			node.name = names.take(mesh_name)
		node.set_meta("me_collision", collision)
		if placement["soft_landing"]:
			node.add_to_group("soft_landing", true)
		var instance := MeshInstance3D.new()
		instance.name = "Mesh"
		instance.mesh = mesh
		# Hidden in the original: collision without a picture. Kept as a node so
		# the editor can still show it.
		instance.visible = not placement["hidden"]
		if placement.get("shadow_only", false):
			# The original's bake occluder: keeps the sun out, never seen. Visible
			# whatever its HiddenGame, which would stop the shadow too.
			instance.visible = true
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_apply_overrides(instance, placement)
		# Not drawn past VISIBLE_RANGE_PER_METRE its own size: 13,000 placements
		# drew the whole chapter from inside a corridor.
		var extent: float = (Common.transform_of(placement).basis * mesh.get_aabb().size).abs().length()
		instance.visibility_range_end = clampf(extent * VISIBLE_RANGE_PER_METRE, VISIBLE_RANGE_MIN, VISIBLE_RANGE_MAX)
		node.add_child(instance)
		var transform := Common.transform_of(placement)
		var stretch := Basis()
		if collision != "none" and not _is_uniform(transform.basis):
			# Godot physics does not support non-uniform scale on a body or its
			# shapes: the collision stops matching what is drawn. The body keeps
			# rotation only; the mesh carries the stretch and the shapes bake it.
			var rotation := transform.basis.orthonormalized()
			if rotation.determinant() < 0.0:
				rotation.x = -rotation.x
			stretch = rotation.inverse() * transform.basis
			transform.basis = rotation
			instance.transform = Transform3D(stretch)
			counts.stretched += 1
		node.transform = transform
		# PrePivot: the mesh and its shapes sit this far off the node, whose
		# origin stays the actor's -- the pivot a matinee turns it about. Turned
		# with the actor but NOT scaled (UE3: Location + R*(S*v - PrePivot)),
		# then brought into the node's own frame, which may carry the scale.
		var pre_pivot := Common.v3(placement.get("pre_pivot", [0.0, 0.0, 0.0]))
		var turned := Common.transform_of(placement).basis.orthonormalized() * -pre_pivot
		var offset := transform.basis.inverse() * turned
		instance.transform.origin = offset
		if collision == "simple":
			var shape_names := Common.NameAllocator.new()
			for shape: Shape3D in mesh.get_meta("simple_shapes"):
				_add_shape(node, _stretched(shape, stretch), shape_names.take("Collision"), offset)
		elif collision == "per_poly":
			_add_shape(node, _stretched(mesh.get_meta("per_poly_shape"), stretch), "Collision", offset)
		(movers if mover else geometry).add_child(node)
	print("[me_level] placements: ", counts)
	var bsp := _build_bsp(manifest["bsp"])
	root.add_child(bsp)
	root.add_child(_build_lights(manifest["lights"]))
	root.add_child(movers)
	var look = manifest.get("environment")
	if look is Dictionary:
		root.add_child(_environment(look))
	var occluder := _build_occluder(geometry, bsp)
	if occluder != null:
		root.add_child(occluder)
	return root


## One occluder of the level's large, still, solid surfaces and its BSP.
## Measured in Stormdrain: 15 ms a frame in the lift corridor down to 6 with the
## visibility ranges, the whole city behind the walls no longer drawn. Only
## placements at least OCCLUDER_MIN_EXTENT across: the same result as taking
## everything down to 8 m, at 520 thousand triangles instead of 1.3 million.
## Movers move and hidden, masked or translucent surfaces do not hide what is
## behind them: none of those.
static func _build_occluder(geometry: Node3D, bsp: Node3D) -> OccluderInstance3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node: Node3D in geometry.get_children():
		var instance := node.get_node_or_null("Mesh") as MeshInstance3D
		if instance == null or not instance.visible or instance.mesh == null:
			continue
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var xform := node.transform * instance.transform
		if (xform.basis * instance.mesh.get_aabb().size).abs().length() < OCCLUDER_MIN_EXTENT:
			continue
		_add_occluding(instance, xform, vertices, indices)
	var bsp_mesh := bsp.get_node_or_null("Mesh") as MeshInstance3D
	if bsp_mesh != null:
		_add_occluding(bsp_mesh, bsp.transform * bsp_mesh.transform, vertices, indices)
	if indices.is_empty():
		return null
	var shape := ArrayOccluder3D.new()
	shape.set_arrays(vertices, indices)
	var occluder := OccluderInstance3D.new()
	occluder.name = "Occluder"
	occluder.occluder = shape
	return occluder


static func _add_occluding(instance: MeshInstance3D, xform: Transform3D,
		vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	for surface in instance.mesh.get_surface_count():
		var material := instance.get_surface_override_material(surface)
		if material == null:
			material = instance.mesh.surface_get_material(surface)
		if material is BaseMaterial3D and (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var arrays := instance.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := vertices.size()
		for p in positions:
			vertices.append(xform * p)
		if arrays[Mesh.ARRAY_INDEX] != null:
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
		else:
			for i in positions.size():
				indices.append(base + i)


## The level's own look, applied at runtime to its Arena (me_environment.gd).
static func _environment(look: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Environment"
	node.set_script(ENVIRONMENT_SCRIPT)
	if look.has("sun_direction"):
		node.set("sun_direction", Common.v3(look["sun_direction"]))
	var post: Dictionary = look.get("post_process", {})
	for channel in ["r", "g", "b", "a"]:
		var points := PackedVector2Array()
		for p: Array in post.get("curve_" + channel, []):
			points.append(Vector2(p[0], p[1]))
		node.set("curve_" + channel, points)
	if post.has("midtones"):
		node.set("midtones", Common.v3(post["midtones"]))
	return node


var _stretched_shapes := {}
## The mesh library that built the meshes, for placement material overrides.
## Null leaves every mesh on its own materials.
var library = null


static func _is_uniform(basis: Basis) -> bool:
	var scale := basis.get_scale().abs()
	return basis.determinant() > 0.0 and absf(scale.x - scale.y) < 0.001 and absf(scale.y - scale.z) < 0.001


## A copy of a library shape with the placement's stretch baked in, shared by
## every placement of the same shape and stretch.
func _stretched(shape: Shape3D, stretch: Basis) -> Shape3D:
	if stretch == Basis():
		return shape
	var key := [shape.get_instance_id(), stretch]
	if _stretched_shapes.has(key):
		return _stretched_shapes[key]
	var copy: Shape3D
	if shape is ConvexPolygonShape3D:
		var points := PackedVector3Array()
		for p in (shape as ConvexPolygonShape3D).points:
			points.append(stretch * p)
		copy = ConvexPolygonShape3D.new()
		copy.points = points
	else:
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		var mirrored := stretch.determinant() < 0.0
		var out := PackedVector3Array()
		out.resize(faces.size())
		for i in range(0, faces.size(), 3):
			# A mirror flips winding; keep the faces' front where it was.
			out[i] = stretch * faces[i]
			out[i + 1] = stretch * faces[i + 2 if mirrored else i + 1]
			out[i + 2] = stretch * faces[i + 1 if mirrored else i + 2]
		copy = ConcavePolygonShape3D.new()
		(copy as ConcavePolygonShape3D).set_faces(out)
	_stretched_shapes[key] = copy
	return copy


## The placement's own materials, per original element, onto every surface
## built from that element.
func _apply_overrides(instance: MeshInstance3D, placement: Dictionary) -> void:
	var overrides: Array = placement.get("materials", [])
	if overrides.is_empty() or library == null:
		return
	var elements: PackedInt32Array = instance.mesh.get_meta("surface_elements", PackedInt32Array())
	for surface in elements.size():
		var element: int = elements[surface]
		if element >= overrides.size() or not overrides[element] is Dictionary:
			continue
		var material: Material = library.override_material(overrides[element])
		if material != null:
			instance.set_surface_override_material(surface, material)


func _add_shape(node: Node3D, shape: Shape3D, name: String, offset := Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	collision.name = name
	collision.shape = shape
	collision.position = offset
	node.add_child(collision)


func _is_grip(mesh_name: String, placement: Dictionary, pipe_line: PackedVector3Array) -> bool:
	for marker in GRIP_MESH_MARKERS:
		if mesh_name.contains(marker):
			return true
	if not mesh_name.to_lower().contains("pipe") or pipe_line.is_empty():
		return false
	var box: Dictionary = placement["aabb"]
	var bounds := AABB(Common.v3(box["min"]), Common.v3(box["max"]) - Common.v3(box["min"]))
	for p in pipe_line:
		if bounds.grow(PIPE_GRIP_REACH_M).has_point(p):
			return true
	return false


static func _ladder_samples(annotations: Array) -> PackedVector3Array:
	var samples := PackedVector3Array()
	for a: Dictionary in annotations:
		if a["kind"] != "ladder":
			continue
		var points := line_points(a)
		for i in range(points.size() - 1):
			var steps := maxi(1, ceili(points[i].distance_to(points[i + 1]) / 0.25))
			for s in steps + 1:
				samples.append(points[i].lerp(points[i + 1], float(s) / steps))
	return samples


## A volume's own line: its spline when it has one (a zipline's sag), else start..end.
static func line_points(annotation: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if annotation.has("spline"):
		for p: Array in annotation["spline"]:
			out.append(Common.v3(p))
	elif annotation.has("start") and annotation.has("end"):
		out.append(Common.v3(annotation["start"]))
		out.append(Common.v3(annotation["end"]))
	return out


func _build_bsp(faces: Array) -> StaticBody3D:
	# Final BSP nodes preserve subtractive openings. Raw additive brush bounds
	# would fill doorways and miss sloping walkways.
	var body := StaticBody3D.new()
	body.name = "BSP"
	var triangles := PackedVector3Array()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Dictionary in faces:
		var points: Array[Vector3] = []
		for raw: Array in face["vertices"]:
			points.append(Common.v3(raw))
		var normal := Common.v3(face["normal"]).normalized()
		for i in range(1, points.size() - 1):
			var a := points[0]
			var b := points[i]
			var c := points[i + 1]
			if (b - a).cross(c - a).dot(normal) > 0.0:
				var swap := b
				b = c
				c = swap
			for p in [a, b, c]:
				surface.set_normal(normal)
				surface.add_vertex(p)
				triangles.append(p)
	if triangles.is_empty():
		return body
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Common.MATERIAL_PALETTE[BSP_MATERIAL_FAMILY]
	material.roughness = 0.95
	instance.material_override = material
	body.add_child(instance)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(triangles)
	_add_shape(body, shape, "Collision")
	return body


func _build_lights(lights: Array) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Lights"
	parent.set_script(LIGHTS_SCRIPT)
	var scale: float = parent.energy_scale
	var names := Common.NameAllocator.new()
	for entry: Dictionary in lights:
		var light: Light3D
		match str(entry["class"]):
			"PointLight", "TdAreaLight":
				# TdAreaLight carries a PointLightComponent; its baked area shape is not used.
				var omni := OmniLight3D.new()
				omni.omni_range = float(entry["radius_m"])
				light = omni
			"SpotLight", "SpotLightMovable":
				var spot := SpotLight3D.new()
				spot.spot_range = float(entry["radius_m"])
				spot.spot_angle = clampf(float(entry["outer_cone_deg"]), 1.0, 89.0)
				light = spot
			_:
				push_error("[me_level] unknown light class %s" % entry["class"])
				continue
		light.name = names.take(str(entry["name"]))
		# UE lights shine along the actor's +X.
		var forward := Common.basis_of(entry["basis"]).x.normalized()
		var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		light.transform = Transform3D(Basis.looking_at(forward, up), Common.v3(entry["position"]))
		light.light_color = Color(entry["color"][0], entry["color"][1], entry["color"][2])
		# Faded out and culled past LIGHT_FADE_BEGIN. The original bakes its
		# lights into lightmaps; here every one is live, Stormdrain has 1146,
		# and past the renderer's per-view cluster budget it drops lights by
		# view -- lamps came on only when looked at from close by.
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_FADE_BEGIN
		light.distance_fade_length = LIGHT_FADE_LENGTH
		light.set_meta("me_brightness", float(entry["brightness"]))
		light.light_energy = float(entry["brightness"]) * scale
		parent.add_child(light)
	return parent

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
## MATCHED AS SUBSTRINGS, because the original names its parts by family and
## spells a family more than one way: a zipline's cable is ZipLineBase_01_Line
## in most chapters and ZipLinePiece01 in the Mall, and listing them one at a
## time meant the Mall's cable kept its per-poly collision -- a body hanging
## 0.9 m under it rode two metres before the cable it hung from threw it off.
const GRIP_MESH_MARKERS: Array[String] = ["LadderSystem", "SwingPole",
		"ZipLine", "S_Cable_01"]
## Exceptions to the families above, matched whole. The 5.6 m S_ZipLineBase_01
## post is the one part of a zipline a runner can collide with and should:
## running through the post reads wrong, and only its brackets and its cable
## are things a hand is meant to pass into.
const GRIP_MESH_SOLID: Array[String] = ["S_ZipLineBase_01"]
## Climbable drainpipes use the same generic segments as the rooftop pipe runs
## a runner steps over, so a pipe is passable only where a ladder line runs
## along it. DO NOT match pipes by name alone.
const PIPE_GRIP_REACH_M := 0.6

const BSP_MATERIAL_FAMILY := "roof"
## What the original names a BSP surface it compiles but never draws.
const BSP_UNDRAWN_MATERIAL := "RemoveSurfaceMaterial"

## The layer hanging cloth lives on, alone, so a query can leave it out by mask
## -- see CameraConfig.third_person_probe_mask.
const CLOTH_LAYER := 4
## The layer a free rigid body lives on, so a body that must not stop the
## player can be left out of the player's mask while its own mask still sees
## the player -- and is shoved aside by it.
const PROP_LAYER := 8
## A cloth never weighs less than this, whatever its density says.
const CLOTH_MIN_MASS_KG := 0.05

## A placement is not drawn past this many times its own size, within
## [VISIBLE_RANGE_MIN, VISIBLE_RANGE_MAX] metres. A dial.
const VISIBLE_RANGE_PER_METRE := 40.0
const VISIBLE_RANGE_MIN := 30.0
const VISIBLE_RANGE_MAX := 3000.0
## Placements at least this many metres across go into the level's occluder.
const OCCLUDER_MIN_EXTENT := 40.0
const RUNNER_VISION_SCRIPT := preload("res://scripts/level/runner_vision_target.gd")
const CLOTH_SCRIPT := preload("res://scripts/level/simulated_cloth.gd")

## Metres from the camera past which an extracted light fades out, and over
## how far. Stormdrain's densest view (the pillar hall) keeps 336 lights
## within 80 m, under project.godot's max_clustered_elements. A dial.
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
	# Added LAST: shells can override Lights by index.
	var movers := Node3D.new()
	movers.name = "Movers"
	var pipe_line := _ladder_samples(manifest["annotations"])
	var names := Common.NameAllocator.new()
	var mover_nodes := {}
	var library := {}
	var counts := {none = 0, simple = 0, per_poly = 0, grip = 0, stretched = 0, slide = 0}
	_stretched_shapes.clear()
	for placement: Dictionary in manifest["placements"]:
		var mesh_name: String = placement["mesh"]
		if not library.has(mesh_name):
			library[mesh_name] = load(MeLibrary.path_for(mesh_name))
		var mesh: ArrayMesh = library[mesh_name]
		var collision: String = placement["collision"]
		var rigid: Dictionary = placement.get("rigid", {})
		if collision != "none" and rigid.is_empty() and _is_grip(mesh_name, placement, pipe_line):
			collision = "none"
			counts.grip += 1
		counts[collision] += 1
		var mover: bool = placement.get("mover", false)
		var node: Node3D
		if mover:
			node = AnimatableBody3D.new()
			node.name = Common.mover_name(placement["package"], placement["name"])
			mover_nodes[Common.actor_id(placement["package"], placement["name"])] = node
		elif not rigid.is_empty():
			node = _rigid_body(rigid)
			node.name = names.take(mesh_name)
		else:
			node = Node3D.new() if collision == "none" else StaticBody3D.new()
			node.name = names.take(mesh_name)
		node.set_meta("me_collision", collision)
		node.set_meta(Common.PACKAGE_META, Common.package_key(placement["package"]))
		node.set_meta(Common.ACTOR_META, Common.actor_id(placement["package"], placement["name"]))
		if placement["soft_landing"]:
			node.add_to_group("soft_landing", true)
		var cloth := _is_cloth(mesh)
		var instance: MeshInstance3D = CLOTH_SCRIPT.new() if cloth else MeshInstance3D.new()
		instance.name = "Mesh"
		# A soft body deforms the mesh it is given, so it cannot share the
		# library's copy with the other placements of the same curtain.
		instance.mesh = _cloth_mesh(mesh) if cloth else mesh
		if cloth:
			_hang_cloth(instance as SoftBody3D, Common.transform_of(placement))
			var drive: Dictionary = placement.get("cloth", {})
			# ClothWind is in the placement's own space; turned, not scaled.
			var wind := Common.v3(drive.get("wind", [0.0, 0.0, 0.0]))
			instance.set("wind", Common.transform_of(placement).basis.orthonormalized() * wind)
			instance.set("blend_weight", float(drive.get("blend", 1.0)))
		# Hidden in the original: collision without a picture. Kept as a node so
		# the editor can still show it.
		instance.visible = not placement["hidden"]
		if placement.get("shadow_only", false):
			# The original's bake occluder: keeps the sun out, never seen. Visible
			# whatever its HiddenGame, which would stop the shadow too.
			instance.visible = true
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_apply_overrides(instance, placement)
		if cloth:
			_cloth_draws_both_sides(instance as SoftBody3D)
		var rest: MeshInstance3D = _cloth_rest(mesh) if cloth else null
		if rest != null:
			rest.visible = instance.visible
			_apply_overrides(rest, placement)
		if placement.has("runner_vision"):
			node.add_child(_runner_vision_target(placement, mesh))
		# Not drawn past VISIBLE_RANGE_PER_METRE its own size: 13,000 placements
		# drew the whole chapter from inside a corridor.
		var extent: float = (Common.transform_of(placement).basis * mesh.get_aabb().size).abs().length()
		instance.visibility_range_end = clampf(extent * VISIBLE_RANGE_PER_METRE, VISIBLE_RANGE_MIN, VISIBLE_RANGE_MAX)
		node.add_child(instance)
		if rest != null:
			rest.visibility_range_end = instance.visibility_range_end
			node.add_child(rest)
		var transform := Common.transform_of(placement)
		var stretch := Basis()
		var scaled := not transform.basis.is_equal_approx(transform.basis.orthonormalized())
		if (collision != "none" and not _is_uniform(transform.basis)) or ((cloth or not rigid.is_empty()) and scaled):
			# Godot physics does not support non-uniform scale on a body or its
			# shapes: the collision stops matching what is drawn. The body keeps
			# rotation only; the mesh carries the stretch and the shapes bake it.
			# A soft body drops its node's scale altogether, uniform or not, so a
			# cloth hung at 1.5 simulated -- and drew -- at 1.0: its stretch goes
			# into its own copy of the mesh instead. A rigid body loses it the
			# first time the simulation writes its transform back.
			var rotation := transform.basis.orthonormalized()
			if rotation.determinant() < 0.0:
				rotation.x = -rotation.x
			stretch = rotation.inverse() * transform.basis
			transform.basis = rotation
			if cloth:
				_bake_stretch(instance.mesh, stretch)
			else:
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
		if rest != null:
			rest.transform = Transform3D(stretch, offset)
		if collision == "simple":
			var shape_names := Common.NameAllocator.new()
			for shape: Shape3D in mesh.get_meta("simple_shapes"):
				_add_shape(node, _stretched(shape, stretch), shape_names.take("Collision"), offset)
		elif collision == "per_poly":
			if mesh.has_meta("per_poly_shape"):
				_add_shape(node, _stretched(mesh.get_meta("per_poly_shape"), stretch), "Collision", offset)
			if mesh.has_meta("slide_shape"):
				# [ME:CONFIRMED] the chute's material carries PM_ConcreteWetSlide,
				# whose property sets bEnableUncontrolledSlide: standing on it
				# is the RumpSlide. Its own body, so the group names exactly
				# those faces and not the wall the same mesh also is.
				var chute := StaticBody3D.new()
				chute.name = "SlideSurface"
				chute.add_to_group(Probes.UNCONTROLLED_SLIDE_GROUP, true)
				_add_shape(chute, _stretched(mesh.get_meta("slide_shape"), stretch), "Collision", offset)
				node.add_child(chute)
				counts.slide += 1
		(movers if mover else geometry).add_child(node)
	_nest_movers(mover_nodes, manifest["placements"])
	print("[me_level] placements: ", counts)
	# One BSP body and one occluder per package: a package that is not in
	# the level (PackagePresence) must neither block nor cull.
	var faces_of := {}
	for face: Dictionary in manifest["bsp"]:
		faces_of.get_or_add(Common.package_key(face["package"]), []).append(face)
	var bsp_of := {}
	for key: String in faces_of:
		var body := _build_bsp(faces_of[key])
		body.name = "BSP" if bsp_of.is_empty() else "BSP%d" % (bsp_of.size() + 1)
		body.set_meta(Common.PACKAGE_META, key)
		bsp_of[key] = body
		root.add_child(body)
	root.add_child(_build_lights(manifest["lights"]))
	root.add_child(movers)
	var look = manifest.get("environment")
	if look is Dictionary:
		root.add_child(_environment(look, look_dials))
	var nodes_of := {}
	for node: Node3D in geometry.get_children():
		nodes_of.get_or_add(node.get_meta(Common.PACKAGE_META), []).append(node)
	for key: String in bsp_of:
		nodes_of.get_or_add(key, [])
	for key: String in nodes_of:
		var occluder := _build_occluder(nodes_of[key], bsp_of.get(key))
		if occluder != null:
			occluder.name = "Occluder" if root.get_node_or_null("Occluder") == null else "Occluder_" + key.validate_node_name()
			occluder.set_meta(Common.PACKAGE_META, key)
			root.add_child(occluder)
	return root


## What the original marks for Runner Vision, as the node a level of our own
## would place by hand (scripts/level/runner_vision_target.gd). Its distances
## and delays are the level designer's, and so is the colour, which is the
## material's own LOI_Color rather than one red for everything.
func _runner_vision_target(placement: Dictionary, mesh: ArrayMesh) -> Node3D:
	var settings: Dictionary = placement["runner_vision"]
	var target := Node3D.new()
	target.set_script(RUNNER_VISION_SCRIPT)
	target.name = "RunnerVision"
	target.set("distance_m", float(settings["distance_m"]))
	target.set("flat_distance", bool(settings["flat_distance"]))
	target.set("proximity_delay", float(settings["proximity_delay"]))
	target.set("min_duration", float(settings["min_duration"]))
	if mesh.has_meta("loi_color"):
		target.set("paint", mesh.get_meta("loi_color"))
	return target


## One occluder of the level's large, still, solid surfaces and its BSP.
## Measured in Stormdrain: 15 ms a frame in the lift corridor down to 6 with the
## visibility ranges, the whole city behind the walls no longer drawn. Only
## placements at least OCCLUDER_MIN_EXTENT across: the same result as taking
## everything down to 8 m, at 520 thousand triangles instead of 1.3 million.
## Hangs each mover under the one it is hard-attached to. A lift's door then
## rides the car because it IS under it, rather than because a second sequence
## drives it to follow -- two sequences writing one node fight, and the door
## stays behind for as long as the shorter one runs (measured on the Escape's
## office lift: a metre of daylight for 0.7 s of a 5 s ride).
##
## Everything is built in world space under Movers, which sits at the origin,
## so a node's own transform IS its world transform here -- the local one is
## taken against that, not against a tree that does not exist yet.
static func _nest_movers(nodes: Dictionary, placements: Array) -> void:
	var tree := Common.mover_tree(placements)
	var world := {}
	for id: String in nodes:
		world[id] = (nodes[id] as Node3D).transform
	# Shallowest first, so a chain three deep (the Scraper has one) still ends
	# up nested rather than half-flattened.
	var order: Array = nodes.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		return Common.mover_path(a, tree).count("/") < Common.mover_path(b, tree).count("/"))
	var nested := 0
	for id: String in order:
		var base: String = str((tree.get(id, {}) as Dictionary).get("base", ""))
		if base == "" or not nodes.has(base):
			continue
		var child: Node3D = nodes[id]
		child.get_parent().remove_child(child)
		(nodes[base] as Node3D).add_child(child)
		child.transform = (world[base] as Transform3D).affine_inverse() * (world[id] as Transform3D)
		# CARRIED BY THE PARENT, so it must not also hold its own place in the
		# physics server: an AnimatableBody3D syncs to physics by default, and
		# a synced body ignores the node tree above it -- the car went up and
		# the door stayed, its local transform quietly counter-rotated to
		# whatever kept it where physics had it.
		(child as AnimatableBody3D).sync_to_physics = false
		nested += 1
	if nested > 0:
		print("[me_level] movers hung off what carries them: ", nested)


## Movers move and hidden, masked or translucent surfaces do not hide what is
## behind them: none of those.
## Godot's occluders are double-sided, the original's culling was not: a
## one-sided shell seen from behind (sp01b's office, inside the slanted
## building's outer facade) is not drawn yet hides the whole city past the
## window. Nearly every large mesh is open, so no filter here fixes that;
## culling is the player's setting instead (SettingsStore.occlusion_culling).
static func _build_occluder(nodes: Array, bsp: Node3D) -> OccluderInstance3D:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node: Node3D in nodes:
		var instance := node.get_node_or_null("Mesh") as MeshInstance3D
		if instance == null or not instance.visible or instance.mesh == null:
			continue
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var xform := node.transform * instance.transform
		if (xform.basis * instance.mesh.get_aabb().size).abs().length() < OCCLUDER_MIN_EXTENT:
			continue
		_add_occluding(instance, xform, vertices, indices)
	var bsp_mesh := (bsp.get_node_or_null("Mesh") if bsp != null else null) as MeshInstance3D
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
static func _environment(look: Dictionary, dials: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Environment"
	node.set_script(ENVIRONMENT_SCRIPT)
	if look.has("sun_direction"):
		node.set("sun_direction", Common.v3(look["sun_direction"]))
	var sun: Dictionary = look.get("sun", {})
	if sun.has("color"):
		node.set("sun_color", _color(sun["color"]))
	if sun.has("brightness"):
		node.set("sun_brightness", float(sun["brightness"]))
	if look.has("sky_color"):
		node.set("sky_color", _color(look["sky_color"]))
	var haze: Dictionary = look.get("haze", {})
	if haze.has("color"):
		node.set("haze_color", _color(haze["color"]))
	if haze.has("distance_m"):
		node.set("haze_distance_m", float(haze["distance_m"]))
	if haze.has("distance_curve"):
		node.set("haze_curve", float(haze["distance_curve"]))
	if haze.has("multiplier"):
		node.set("haze_multiplier", float(haze["multiplier"]))
	if haze.get("enabled", true) == false:
		node.set("haze_strength", 0.0)
	var post: Dictionary = look.get("post_process", {})
	for channel in ["r", "g", "b", "a"]:
		var points := PackedVector2Array()
		for p: Array in post.get("curve_" + channel, []):
			points.append(Vector2(p[0], p[1]))
		node.set("curve_" + channel, points)
	if post.has("midtones"):
		node.set("midtones", Common.v3(post["midtones"]))
	# The config's dials, by export name. A name the node does not have is a
	# typo that would otherwise do nothing, silently.
	for key: String in dials:
		if key == LAMP_DIAL:
			continue
		var value: Variant = dials[key]
		var current: Variant = node.get(key)
		if current == null or key in ["sun_direction", "curve_r", "curve_g", "curve_b", "curve_a"]:
			push_error("[me_level] look.%s is not a dial of me_environment.gd" % key)
			continue
		if current is Color:
			value = _color(value)
		elif current is Vector3:
			value = Common.v3(value)
		node.set(key, value)
	return node


static func _color(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


var _stretched_shapes := {}
## The mesh library that built the meshes, for placement material overrides.
## Null leaves every mesh on its own materials.
var library = null
## The level config's "look" block: me_environment.gd dials by export name,
## plus LAMP_DIAL for the lights' energy_scale. Read from the config file the
## build was asked for, not from the manifest's copy of it, so a dial can be
## turned without re-extracting.
var look_dials := {}
const LAMP_DIAL := "lamp_energy_scale"


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


## Every mesh the original simulates hangs, and nothing else: the extractor
## records the pinned vertices only for a SkeletalMesh that carries a PhysX
## cloth map.
static func _is_cloth(mesh: ArrayMesh) -> bool:
	return (mesh.get_meta("cloth", {}) as Dictionary).has("pinned")


## A free KActor as the original simulates it.
##
## One that clears BlockNonZeroExtent is left off layer 1, which is all the
## player's mask sees, so the player runs through it; its own mask sees layer
## 1, where the player also lives, so it is shoved aside. Measured under Jolt:
## the player walks the same distance with the box in the way, and the box
## goes with it.
static func _rigid_body(rigid: Dictionary) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = maxf(float(rigid["mass"]), 0.01)
	body.collision_layer = PROP_LAYER | (1 if rigid["blocks_player"] else 0)
	body.collision_mask = 1 | PROP_LAYER
	var material := PhysicsMaterial.new()
	material.friction = float(rigid["friction"])
	material.bounce = float(rigid["restitution"])
	body.physics_material_override = material
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = float(rigid["linear_damping"])
	body.sleeping = not rigid["awake"]
	return body


## A cloth's own copy of a library mesh, ONE SURFACE.
##
## The library gives a two-sided material a second, reversed surface, and a
## soft body simulates only its first: the reversed copy hung there rigid while
## the cloth moved through it, and it fired a warning a frame. Cloth is drawn
## from both sides by its material instead -- _cloth_draws_both_sides().
##
## Its vertices are put in the order the soft body numbers its points: each
## position's first appearance in the index buffer, then the copies. DO NOT
## skip this. Godot 4.7's Jolt checks apply_force()'s pin guard with the POINT's
## number against the pinned MESH vertices, so wherever the two numberings part
## a free vertex reads as pinned -- an error a tick, and no wind on it. On
## SP01a's paper strips half the free vertices were refused.
static func _cloth_mesh(source: ArrayMesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	var copies := PackedInt32Array()
	var first_at := {}
	var placed := {}
	for index in indices:
		if placed.has(index):
			continue
		placed[index] = true
		if first_at.has(vertices[index]):
			copies.append(index)
		else:
			first_at[vertices[index]] = index
			order.append(index)
	order.append_array(copies)
	for i in vertices.size():
		if not placed.has(i):
			order.append(i)
	var new_of := {}
	for i in order.size():
		new_of[order[i]] = i
	for kind in Mesh.ARRAY_MAX:
		if kind != Mesh.ARRAY_INDEX and arrays[kind] != null:
			arrays[kind] = _reordered(arrays[kind], order, vertices.size())
	for t in indices.size():
		indices[t] = new_of[indices[t]]
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, source.surface_get_material(0))
	out.surface_set_name(0, source.surface_get_name(0))
	for key: String in source.get_meta_list():
		out.set_meta(key, source.get_meta(key))
	# The pins in the new order, and every copy of a pinned position with them:
	# the copies are one simulated point, and it is pinned.
	var cloth: Dictionary = (source.get_meta("cloth") as Dictionary).duplicate()
	var pinned_at := {}
	for index: int in cloth["pinned"]:
		pinned_at[vertices[index]] = true
	var pinned := []
	for i in vertices.size():
		if pinned_at.has(vertices[i]):
			pinned.append(new_of[i])
	pinned.sort()
	cloth["pinned"] = pinned
	out.set_meta("cloth", cloth)
	# The slot table is per surface, and _apply_overrides() indexes surfaces by
	# it: left at the source's length it would address a surface that is gone.
	var slots: PackedInt32Array = source.get_meta("surface_slots", PackedInt32Array())
	out.set_meta("surface_slots", slots.slice(0, 1) if not slots.is_empty() else slots)
	return out


## A per-vertex array in `order`, however many values each vertex holds.
static func _reordered(values: Variant, order: PackedInt32Array, count: int) -> Variant:
	var stride: int = values.size() / count
	var out: Variant = values.duplicate()
	for i in order.size():
		for k in stride:
			out[i * stride + k] = values[order[i] * stride + k]
	return out


## The surfaces of a cloth mesh its soft body does not simulate, drawn rigid
## beside it, or null when there are none.
##
## A soft body simulates only its first surface, so a cloth with a second
## material lost it: PX_SK_WarningStripeCloth_01's second element is a tie of
## 13 vertices, 12 of them pinned, and it vanished. Drawn still, it stays where
## the original held it.
static func _cloth_rest(source: ArrayMesh) -> MeshInstance3D:
	var simulated := source.surface_get_name(0)
	var slots: PackedInt32Array = source.get_meta("surface_slots", PackedInt32Array())
	var out := ArrayMesh.new()
	var out_slots := PackedInt32Array()
	for surface in range(1, source.get_surface_count()):
		var surface_name := source.surface_get_name(surface)
		if surface_name == simulated + "_back":
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
		out.surface_set_material(out.get_surface_count() - 1, source.surface_get_material(surface))
		out.surface_set_name(out.get_surface_count() - 1, surface_name)
		if surface < slots.size():
			out_slots.append(slots[surface])
	if out.get_surface_count() == 0:
		return null
	out.set_meta("surface_slots", out_slots)
	var rest := MeshInstance3D.new()
	rest.name = "Rest"
	rest.mesh = out
	return rest


## A placement's stretch baked into a cloth's own one-surface mesh, which a
## soft body needs because it ignores its node's scale.
static func _bake_stretch(mesh: ArrayMesh, stretch: Basis) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var material := mesh.surface_get_material(0)
	var surface_name := mesh.surface_get_name(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] = stretch * vertices[i]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normal_basis := stretch.inverse().transposed()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in normals.size():
			normals[i] = (normal_basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	mesh.surface_set_name(0, surface_name)


## Pins a cloth where the original pinned it.
##
## [ME:CONFIRMED] the pinned vertices are the original's own, per vertex, off
## the SkeletalMesh (see the extractor's skeletal_mesh.py). DO NOT go back to
## working the pins out from the shape: "the top edge in world space" holds for
## a curtain and for nothing else -- PX_SK_PlasticSheet_* lie flat with no top
## edge at all, and PX_SK_EdgeCloth_01 is held at 22 points scattered across
## its height. Guessing made every kind of cloth a separate case to judge.
##
## Its own collision layer keeps it out of queries that must ignore it, the
## third-person camera probe above all. The mask still sees layer 1, which is
## all soft-body pairing needs: the player pushes it, and is never stopped by
## it -- a curtain is walked through.
func _hang_cloth(cloth: SoftBody3D, placement: Transform3D) -> void:
	cloth.collision_layer = CLOTH_LAYER
	cloth.collision_mask = 1
	var mesh: ArrayMesh = cloth.mesh
	var arrays := mesh.surface_get_arrays(0)
	var parameters: Dictionary = mesh.get_meta("cloth", {})
	# Only what the simulated surface's faces use. A soft body drops every
	# other vertex, and a pin on a dropped one is an engine error a tick: the
	# original pins a cloth's rigid parts too, which _cloth_rest() draws.
	var used := {}
	for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
		used[index] = true
	var pinned := PackedInt32Array()
	for index: int in parameters["pinned"]:
		if used.has(index):
			pinned.append(index)
	cloth.set("pinned_points", pinned)
	# [ME:CONFIRMED] the original's own numbers, off the SkeletalMesh:
	# ClothDensity is per unit area, so the mass is the density over the sheet
	# the placement actually hangs. Left at the engine's 1 kg a curtain of 4.3
	# square metres weighed less than a tea towel and flew like one.
	var density := float(parameters.get("density", 0.0))
	if density > 0.0:
		cloth.total_mass = maxf(density * _sheet_area(arrays, placement), CLOTH_MIN_MASS_KG)
	if parameters.get("damped", false):
		cloth.damping_coefficient = clampf(float(parameters.get("damping", 0.0)), 0.0, 1.0)


## A sheet has no inside: cloth is drawn from both sides.
##
## RUN THIS AFTER _apply_overrides(). These curtains carry a placement material
## of their own, so a two-sided copy made before the override is put back to
## one side by it, and the curtain disappears from behind.
##
## Not the reversed-surface trick the mesh library uses for a two-sided element:
## that adds a second SURFACE, and a soft body simulates only its first.
static func _cloth_draws_both_sides(cloth: SoftBody3D) -> void:
	var material: Material = cloth.get_surface_override_material(0)
	if material == null:
		material = (cloth.mesh as ArrayMesh).surface_get_material(0)
	if material is BaseMaterial3D:
		var both := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
		both.resource_path = ""
		both.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloth.set_surface_override_material(0, both)


## Area of the sheet as the placement hangs it, for a density to be a mass.
static func _sheet_area(arrays: Array, placement: Transform3D) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	for i in range(0, indices.size(), 3):
		var a := placement * vertices[indices[i]]
		var b := placement * vertices[indices[i + 1]]
		var c := placement * vertices[indices[i + 2]]
		area += 0.5 * (b - a).cross(c - a).length()
	return area


## The placement's own materials onto every surface that draws from the slot
## each one names. An element's slot is its MaterialIndex, which is NOT its
## position among the elements: S_RooftopStructure_06 lists slots 0, 3, 1, 2,
## and indexing by position put the side band's blue on the roof deck.
func _apply_overrides(instance: MeshInstance3D, placement: Dictionary) -> void:
	var overrides: Array = placement.get("materials", [])
	if overrides.is_empty() or library == null:
		return
	var slots: PackedInt32Array = instance.mesh.get_meta("surface_slots", PackedInt32Array())
	for surface in slots.size():
		var slot: int = slots[surface]
		if slot >= overrides.size() or not overrides[slot] is Dictionary:
			continue
		var material: Material = library.override_material(overrides[slot])
		if material != null:
			instance.set_surface_override_material(surface, material)


func _add_shape(node: Node3D, shape: Shape3D, name: String, offset := Vector3.ZERO) -> void:
	var collision := CollisionShape3D.new()
	collision.name = name
	collision.shape = shape
	collision.position = offset
	node.add_child(collision)


func _is_grip(mesh_name: String, placement: Dictionary, pipe_line: PackedVector3Array) -> bool:
	# A variant carries its package as a suffix (mesh@Package); the family is
	# the part before it.
	var family := mesh_name.split("@")[0]
	if GRIP_MESH_SOLID.has(family):
		return false
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
	#
	# One surface per material the original's BSP surfaces name. An interior is
	# mostly BSP, and one flat colour over all of it drew every office wall,
	# ceiling and air duct the same grey.
	var body := StaticBody3D.new()
	body.name = "BSP"
	var triangles := PackedVector3Array()
	var tools := {}
	var entries := {}
	var order: Array[String] = []
	for face: Dictionary in faces:
		var points: Array[Vector3] = []
		for raw: Array in face["vertices"]:
			points.append(Common.v3(raw))
		var uvs: Array[Vector2] = []
		for raw: Array in face.get("uvs", []):
			uvs.append(Vector2(raw[0], raw[1]))
		var normal := Common.v3(face["normal"]).normalized()
		var material_name: String = str(face.get("material", ""))
		# The original's mark for a face it never draws. It still blocks, so it
		# joins the collision and not the mesh.
		var tool: SurfaceTool = null
		if material_name != BSP_UNDRAWN_MATERIAL:
			if not tools.has(material_name):
				var made := SurfaceTool.new()
				made.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material_name] = made
				entries[material_name] = face
				order.append(material_name)
			tool = tools[material_name]
		for i in range(1, points.size() - 1):
			var wound := [0, i, i + 1]
			if (points[i] - points[0]).cross(points[i + 1] - points[0]).dot(normal) > 0.0:
				wound = [0, i + 1, i]
			for k: int in wound:
				triangles.append(points[k])
				if tool != null:
					tool.set_normal(normal)
					if k < uvs.size():
						tool.set_uv(uvs[k])
					tool.add_vertex(points[k])
	if triangles.is_empty():
		return body
	var mesh: ArrayMesh = null
	for material_name in order:
		mesh = (tools[material_name] as SurfaceTool).commit(mesh)
	if mesh != null:
		for i in order.size():
			var material: Material = null
			if library != null:
				material = library.override_material(entries[order[i]])
			if material == null:
				# DefaultMaterial and anything whose bake failed: the family
				# colour, as the whole BSP used to be drawn.
				var flat := StandardMaterial3D.new()
				flat.albedo_color = Common.MATERIAL_PALETTE[BSP_MATERIAL_FAMILY]
				flat.roughness = 0.95
				material = flat
			mesh.surface_set_material(i, material)
			mesh.surface_set_name(i, order[i])
		var instance := MeshInstance3D.new()
		instance.name = "Mesh"
		instance.mesh = mesh
		body.add_child(instance)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(triangles)
	_add_shape(body, shape, "Collision")
	return body


func _build_lights(lights: Array) -> Node3D:
	var parent := Node3D.new()
	parent.name = "Lights"
	parent.set_script(LIGHTS_SCRIPT)
	if look_dials.has(LAMP_DIAL):
		parent.energy_scale = float(look_dials[LAMP_DIAL])
	var scale: float = parent.energy_scale
	var names := Common.NameAllocator.new()
	for entry: Dictionary in lights:
		var light: Light3D
		match str(entry["class"]):
			"PointLight", "PointLightMovable", "TdAreaLight":
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
		if entry.get("character_only", false):
			# Lights the character only, as in the original, never the level.
			var camera := CameraConfig.new()
			light.light_cull_mask = camera.first_person_body_layers | camera.third_person_body_layers
			# And never the GI: SDFGI injects a light whatever its cull mask,
			# and in the far cascades a brightness-5 lamp at the tutorial's
			# door lit a whole block from 60 m, then went dark as the player
			# walked up and the fine cascades took over.
			light.light_bake_mode = Light3D.BAKE_DISABLED
		light.set_meta("me_brightness", float(entry["brightness"]))
		light.set_meta(Common.PACKAGE_META, Common.package_key(str(entry["package"])))
		light.set_meta(Common.ACTOR_META, Common.actor_id(str(entry["package"]), str(entry["name"])))
		light.light_energy = float(entry["brightness"]) * scale
		parent.add_child(light)
	return parent

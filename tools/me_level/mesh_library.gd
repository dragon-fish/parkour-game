@tool
extends RefCounted

# One ArrayMesh resource per original StaticMesh, shared by every level.
#
# Collision rides along as metadata on the mesh resource, so a placement needs
# one file: "simple_shapes" (convex hulls and boxes), "per_poly_shape" (the
# triangles of the surfaces that collide), "bounds" (local AABB). Which one a
# placement uses is the placement's own collision class, decided at extraction.

const Common := preload("res://tools/me_level/me_level_common.gd")

var _materials := {}


static func path_for(mesh_name: String) -> String:
	return Common.LIBRARY_DIR.path_join(mesh_name.validate_filename() + ".res")


## Builds every mesh in `meshes` whose source changed. Returns false on error.
func build(meshes: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Common.LIBRARY_DIR.path_join("materials")))
	var built := 0
	for mesh_name: String in meshes:
		var record: Dictionary = meshes[mesh_name]
		# Which package a mesh was read from differs between levels; the mesh does not.
		var content := record.duplicate()
		content.erase("source")
		var hash := JSON.stringify(content, "", true).sha256_text()
		var path := path_for(mesh_name)
		if ResourceLoader.exists(path):
			var existing: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if existing != null and existing.get_meta("source_hash", "") == hash:
				continue
		var mesh := _build_mesh(record)
		if mesh == null:
			return false
		mesh.set_meta("source_hash", hash)
		var error := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("[me_level] saving %s: %s" % [path, error_string(error)])
			return false
		built += 1
	print("[me_level] mesh library: %d built, %d up to date" % [built, meshes.size() - built])
	return true


func _build_mesh(record: Dictionary) -> ArrayMesh:
	var name: String = record["name"]
	var positions := _vectors(record["vertices"])
	var normals := PackedVector3Array() if record["normals"] == null else _vectors(record["normals"])
	if positions.size() != int(record["vertex_count"]):
		push_error("[me_level] %s: %d positions, expected %d" % [name, positions.size(), record["vertex_count"]])
		return null
	var mesh := ArrayMesh.new()
	var collision_faces := PackedVector3Array()
	for surface: Dictionary in record["surfaces"]:
		var indices := _indices(surface["indices"])
		if indices.is_empty():
			continue
		if surface["collide"]:
			for index in indices:
				collision_faces.append(positions[index])
		if surface["blend"] == "modulate":
			# A modulate surface darkens what is behind it through its texture.
			# Without the texture it is only a dark patch: collide, do not draw.
			continue
		var arrays := []
		if normals.is_empty():
			# The original cooked this mesh without normals: shade it flat.
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_smooth_group(-1)
			for index in indices:
				st.add_vertex(positions[index])
			st.generate_normals()
			arrays = st.commit_to_arrays()
		else:
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = positions
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material_name: String = surface["material"] if surface["material"] != null else ""
		mesh.surface_set_material(mesh.get_surface_count() - 1,
				_material(Common.material_family(material_name, name), surface["blend"], surface["unlit"]))
		mesh.surface_set_name(mesh.get_surface_count() - 1, material_name)
	var simple: Array[Shape3D] = []
	for shape: Dictionary in record["simple_shapes"]:
		var convex := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for v: Array in shape["vertices"]:
			points.append(Common.v3(v))
		convex.points = points
		simple.append(convex)
	mesh.set_meta("simple_shapes", simple)
	if not collision_faces.is_empty():
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(collision_faces)
		mesh.set_meta("per_poly_shape", concave)
	var bounds: Dictionary = record["bounds"]
	var extent := Common.v3(bounds["extent"])
	mesh.set_meta("bounds", AABB(Common.v3(bounds["origin"]) - extent, extent * 2.0))
	return mesh


## One shared material per (family, blend, unlit). The original's blend mode and
## lighting model decide how a surface reads without its texture:
##   additive     light shafts and glows: unshaded, added, faint
##   translucent  glass and water sheets: see-through
##   masked       gratings and fences cut out by texture: drawn solid for now
##   unlit        lamp faces and cards: unshaded
func _material(family: String, blend: String, unlit: bool) -> StandardMaterial3D:
	var key := family if blend in ["opaque", "masked"] else ("light" if blend == "additive" else family)
	key += "" if blend in ["opaque", "masked"] else "_" + blend
	key += "_unlit" if unlit and blend != "additive" else ""
	if _materials.has(key):
		return _materials[key]
	var path := Common.LIBRARY_DIR.path_join("materials").path_join(key + ".tres")
	var material: StandardMaterial3D
	if ResourceLoader.exists(path):
		material = load(path)
	else:
		# Created once; afterwards the file is the look, edit it there.
		material = StandardMaterial3D.new()
		var color: Color = Common.MATERIAL_PALETTE[family if blend != "additive" else "light"]
		material.albedo_color = color
		material.roughness = 0.7 if family in ["metal", "glass"] else 0.95
		if unlit or blend == "additive":
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		match blend:
			"additive":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				material.albedo_color = Color(color, 1.0) * Color(0.12, 0.12, 0.12, 1.0)
			"translucent":
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color = Color(color, 0.35)
		ResourceSaver.save(material, path)
		material = load(path)
	_materials[key] = material
	return material


static func _vectors(encoded: String) -> PackedVector3Array:
	var floats := Marshalls.base64_to_raw(encoded).to_float32_array()
	var out := PackedVector3Array()
	out.resize(floats.size() / 3)
	for i in out.size():
		out[i] = Vector3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
	return out


static func _indices(encoded: String) -> PackedInt32Array:
	var raw := Marshalls.base64_to_raw(encoded)
	var out := PackedInt32Array()
	out.resize(raw.size() / 2)
	for i in out.size():
		out[i] = raw.decode_u16(i * 2)
	return out

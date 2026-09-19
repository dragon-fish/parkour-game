@tool
extends RefCounted

# One ArrayMesh resource per original StaticMesh, shared by every level.
#
# Collision rides along as metadata on the mesh resource, so a placement needs
# one file: "simple_shapes" (convex hulls and boxes), "per_poly_shape" (the
# triangles of the surfaces that collide), "bounds" (local AABB). Which one a
# placement uses is the placement's own collision class, decided at extraction.

const Common := preload("res://tools/me_level/me_level_common.gd")

## Multiplies every baked texture. The original's diffuse maps are near white
## and were lit by baked light; under a live sun they clip. A dial.
const TEXTURE_ALBEDO := Color(0.85, 0.85, 0.85)
## Roughness where a surface mirrors the sky (a facade's windows, a storefront):
## the original's cube map is a sharp reflection. A dial.
const MIRROR_ROUGHNESS := 0.05
## Roughness of a material the original gave no SpecularPower. The bakes that
## have one carry their own (materials.py: sqrt(2 / (n + 2))).
const DEFAULT_ROUGHNESS := 0.9
## The original's SpecularColor (0..several) onto Godot's specular (0..1,
## 0.5 = the default dielectric). A dial.
const SPECULAR_SCALE := 0.5
## How strongly a surface's sheen (the cube map share over all of it) becomes
## a clearcoat. A dial.
const SHEEN_SCALE := 1.0
## Part of every mesh's source hash. Bump when what a library file contains or
## references changes shape, so no mesh keeps pointing at a file that is gone.
const LIBRARY_FORMAT := 5

var _materials := {}
var _bakes := {}


static func path_for(mesh_name: String) -> String:
	return Common.LIBRARY_DIR.path_join(mesh_name.validate_filename() + ".res")


## Builds every mesh in `meshes` whose source changed. Returns false on error.
func build(meshes: Dictionary, bakes: Dictionary) -> bool:
	_bakes = bakes
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Common.LIBRARY_DIR.path_join("materials")))
	var built := 0
	for mesh_name: String in meshes:
		var record: Dictionary = meshes[mesh_name]
		# Which package a mesh was read from differs between levels; the mesh does not.
		var content := record.duplicate()
		content.erase("source")
		# Which UV set a surface uses comes from its material's bake.
		content["uv_sets"] = record["surfaces"].map(func(s): return _uv_set(s))
		content["library_format"] = LIBRARY_FORMAT
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
	# The original's element index of every surface, in surface order: a
	# placement's material overrides are per element, and a two-sided
	# element becomes two surfaces while a modulate one becomes none.
	var elements := PackedInt32Array()
	for element in record["surfaces"].size():
		var surface: Dictionary = record["surfaces"][element]
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
		var uvs := _uvs(record, _uv_set(surface), positions.size())
		var material_name: String = surface["material"] if surface["material"] != null else ""
		var material: Material
		if _bakes.has(material_name) and surface["blend"] != "additive":
			material = _textured_material(material_name, surface["blend"], surface["unlit"])
		else:
			material = _material(Common.material_family(material_name, name), surface["blend"], surface["unlit"])
		_add_surface(mesh, positions, normals, uvs, indices, material, material_name)
		elements.append(element)
		if surface.get("two_sided", false) and surface["blend"] != "additive":
			# DO NOT draw two-sided surfaces with CULL_DISABLED. A placement with a
			# mirroring transform (negative scale) gets FRONT_FACING inverted,
			# so the lit side renders black and the side facing into the wall
			# renders lit. A second, reversed surface is lit correctly either way.
			var back_indices := indices.duplicate()
			for t in range(0, back_indices.size(), 3):
				back_indices[t + 1] = indices[t + 2]
				back_indices[t + 2] = indices[t + 1]
			var back_normals := PackedVector3Array()
			back_normals.resize(normals.size())
			for i in normals.size():
				back_normals[i] = -normals[i]
			_add_surface(mesh, positions, back_normals, uvs, back_indices, material, material_name + "_back")
			elements.append(element)
	var simple: Array[Shape3D] = []
	for shape: Dictionary in record["simple_shapes"]:
		var convex := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for v: Array in shape["vertices"]:
			points.append(Common.v3(v))
		convex.points = points
		simple.append(convex)
	mesh.set_meta("surface_elements", elements)
	mesh.set_meta("simple_shapes", simple)
	if not collision_faces.is_empty():
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(collision_faces)
		mesh.set_meta("per_poly_shape", concave)
	var bounds: Dictionary = record["bounds"]
	var extent := Common.v3(bounds["extent"])
	mesh.set_meta("bounds", AABB(Common.v3(bounds["origin"]) - extent, extent * 2.0))
	return mesh


func _add_surface(mesh: ArrayMesh, positions: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array, material: Material, surface_name: String) -> void:
	var arrays := []
	if normals.is_empty():
		# The original cooked this mesh without normals: shade it flat.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		for index in indices:
			if not uvs.is_empty():
				st.set_uv(uvs[index])
			st.add_vertex(positions[index])
		st.generate_normals()
		arrays = st.commit_to_arrays()
	else:
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		if not uvs.is_empty():
			arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	mesh.surface_set_name(mesh.get_surface_count() - 1, surface_name)


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


## The material a placement's override names, or null when it cannot be
## drawn textured (no bake, or additive): the mesh's own material stays.
func override_material(entry: Dictionary) -> Material:
	var name: String = entry.get("material", "")
	if not _bakes.has(name) or entry.get("blend", "opaque") == "additive":
		return null
	return _textured_material(name, entry.get("blend", "opaque"), entry.get("unlit", false))


func _uv_set(surface: Dictionary) -> int:
	var bake: Variant = _bakes.get(surface["material"] if surface["material"] != null else "")
	return int(bake["uv_set"]) if bake is Dictionary else 0


static func _uvs(record: Dictionary, uv_set: int, count: int) -> PackedVector2Array:
	var sets: Array = record.get("uvs", [])
	if sets.is_empty():
		return PackedVector2Array()
	var raw := Marshalls.base64_to_raw(sets[mini(uv_set, sets.size() - 1)]).to_float32_array()
	var out := PackedVector2Array()
	if raw.size() != count * 2:
		return out
	out.resize(count)
	for i in count:
		out[i] = Vector2(raw[i * 2], raw[i * 2 + 1])
	return out


## One material per original material and blend mode, carrying its baked
## image. Rebuilt when the bake changes.
func _textured_material(material_name: String, blend: String, unlit: bool) -> StandardMaterial3D:
	var key := "%s_%s%s" % [material_name.validate_filename(), blend, "_unlit" if unlit else ""]
	if _materials.has(key):
		return _materials[key]
	var bake: Dictionary = _bakes[material_name]
	var hash := JSON.stringify([bake, blend, unlit, TEXTURE_ALBEDO, LIBRARY_FORMAT]).sha256_text()
	var dir := Common.LIBRARY_DIR.path_join("materials").path_join("textured")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join(key + ".res")
	if ResourceLoader.exists(path):
		var existing: StandardMaterial3D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			_materials[key] = load(path)
			return _materials[key]
	var image := Image.create_from_data(int(bake["width"]), int(bake["height"]), false,
			Image.FORMAT_RGBA8, Marshalls.base64_to_raw(bake["rgba"]))
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.albedo_color = TEXTURE_ALBEDO
	material.uv1_scale = Vector3(bake["tiling"][0], bake["tiling"][1], 1.0)
	var roughness: float = float(bake.get("roughness", DEFAULT_ROUGHNESS))
	material.roughness = roughness
	if bake.has("specular"):
		material.metallic_specular = clampf(float(bake["specular"]) * SPECULAR_SCALE, 0.0, 1.0)
	if bake.has("metallic"):
		# Mirror where the original put the sky into the colour through a cube
		# map, and sharp there: metallic and roughness from one mask.
		var mask := Image.create_from_data(int(bake["width"]), int(bake["height"]), false,
				Image.FORMAT_L8, Marshalls.base64_to_raw(bake["metallic"]))
		var rough := Image.create(mask.get_width(), mask.get_height(), false, Image.FORMAT_L8)
		for y in mask.get_height():
			for x in mask.get_width():
				var m := mask.get_pixel(x, y).r
				rough.set_pixel(x, y, Color.from_hsv(0.0, 0.0, lerpf(roughness, MIRROR_ROUGHNESS, m)))
		mask.generate_mipmaps()
		rough.generate_mipmaps()
		material.metallic = 1.0
		material.metallic_texture = ImageTexture.create_from_image(mask)
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness = 1.0
		material.roughness_texture = ImageTexture.create_from_image(rough)
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if float(bake.get("sheen", 0.0)) > 0.01:
		material.clearcoat_enabled = true
		material.clearcoat = clampf(float(bake["sheen"]) * SHEEN_SCALE, 0.0, 1.0)
		material.clearcoat_roughness = roughness
	if unlit:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match blend:
		"masked":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.4
		"translucent":
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.set_meta("source_hash", hash)
	ResourceSaver.save(material, path, ResourceSaver.FLAG_COMPRESS)
	_materials[key] = load(path)
	return _materials[key]


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

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
const SHEEN_SCALE := 0.5
## Part of every mesh's source hash. Bump when what a library file contains or
## references changes shape, so no mesh keeps pointing at a file that is gone.
const LIBRARY_FORMAT := 10
## What a lightmapped surface draws with, by the original's blend mode. A blend
## that is not here (additive, modulate) is not lit by its lightmap.
const LIGHTMAP_SHADERS := {
	"opaque": preload("res://tools/me_level/me_lightmap.gdshader"),
	"masked": preload("res://tools/me_level/me_lightmap_masked.gdshader"),
	"translucent": preload("res://tools/me_level/me_lightmap_translucent.gdshader"),
}

## How strongly the baked normal maps read. The original's are genuinely
## subtle -- its tangent channels sit within a couple of percent of flat, which
## is the art rather than a loss -- so 1.0 is faithful and anything above it is
## a deliberate exaggeration. Useful above all for JUDGING one: at 1.0 a brick
## wall's relief is too slight to tell which way it faces. A dial.
var normal_scale := 1.0

## How much of a material's baker_tint reaches its albedo. The original's
## facades take their colour from the lightmap, not the diffuse; this is how
## far that colour is put back. 0 leaves every bake as it was evaluated. A dial.
var baker_tint_strength := 1.0

var _materials := {}
var _bakes := {}
var _bake_hashes := {}
var _textures := {}
var _lightmapped := {}


static func path_for(mesh_name: String) -> String:
	return Common.LIBRARY_DIR.path_join(mesh_name.validate_filename() + ".res")


## Builds every mesh in `meshes` whose source changed. Returns false on error.
func build(meshes: Dictionary, bakes: Dictionary) -> bool:
	_bakes = bakes
	_bake_hashes = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Common.LIBRARY_DIR.path_join("materials")))
	var built := 0
	for mesh_name: String in meshes:
		var record: Dictionary = meshes[mesh_name]
		# Which package a mesh was read from differs between levels; the mesh does not.
		var content := record.duplicate()
		content.erase("source")
		# Which UV set a surface uses comes from its material's bake.
		content["uv_sets"] = record["surfaces"].map(func(s): return _uv_set(record, s))
		# And what its materials look like: an unchanged mesh is skipped
		# whole, so without this a re-baked material never reached its file
		# (the Mall's bridge stayed black after its bake was fixed).
		content["bakes"] = record["surfaces"].map(func(s): return _bake_hash(s))
		content["library_format"] = LIBRARY_FORMAT
		# The look dials belong in the MESH's hash, not only in the material's.
		# A mesh that is up to date is skipped whole, and its materials are built
		# from inside that build -- so a dial left out here is a dial that does
		# nothing until something else happens to invalidate the mesh.
		content["normal_scale"] = normal_scale
		content["baker_tint_strength"] = baker_tint_strength
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
	# The colour this mesh turns under Runner Vision, carried on the resource
	# the way its collision is. [ME:CONFIRMED] every tagged material has its own
	# LOI_Color and they differ -- a lift button is (0.7, 0, 0) where a pipe is
	# (1.5, 0, 0) -- so the builder reads it here rather than repainting
	# everything one red.
	for surface: Dictionary in record["surfaces"]:
		var bake: Variant = _bakes.get(surface["material"] if surface["material"] != null else "")
		if bake is Dictionary and (bake as Dictionary).has("loi_color"):
			var rgb: Array = bake["loi_color"]
			mesh.set_meta("loi_color", Color(rgb[0], rgb[1], rgb[2]))
			break
	# The set the original's lightmap is sampled in, as UV2 on every surface,
	# and the tangents its specular is worked out in. Skinned scenery has
	# neither.
	var uv2 := PackedVector2Array()
	if record.has("lightmap_uv_set"):
		uv2 = _uvs(record, int(record["lightmap_uv_set"]), positions.size())
	var tangents := PackedFloat32Array()
	if record.get("tangents") != null:
		tangents = Marshalls.base64_to_raw(record["tangents"]).to_float32_array()
		if tangents.size() != positions.size() * 4:
			push_error("[me_level] %s: %d tangent values for %d vertices" % [name, tangents.size(), positions.size()])
			return null
	var collision_faces := PackedVector3Array()
	# Faces of surfaces whose material the original marks
	# bEnableUncontrolledSlide: a separate shape, so the placement can carry
	# them on a body of their own in the uncontrolled_slide group. One mesh
	# is both the chute and the wall beside it (S_Stdp_Stde_01).
	var slide_faces := PackedVector3Array()
	# The material slot every surface draws from, in surface order: what a
	# placement's Materials array indexes. NOT the element's position -- an
	# element carries its own MaterialIndex and the two orders differ. A
	# two-sided element becomes two surfaces while a modulate one becomes none,
	# so this cannot be recovered from the surface index either.
	var slots := PackedInt32Array()
	# What each surface draws, in surface order, for the level to give a
	# lightmapped placement its lightmapped materials: {material, blend, unlit,
	# nondirectional}.
	var drawn: Array[Dictionary] = []
	# For a surface built flat (no normals in the original), the original
	# vertex each of its vertices came from: a vertex lightmap is per original
	# vertex. Empty for every other surface.
	var sources: Array[PackedInt32Array] = []
	for element in record["surfaces"].size():
		var surface: Dictionary = record["surfaces"][element]
		var indices := _indices(surface["indices"])
		if indices.is_empty():
			continue
		if surface["collide"]:
			var faces := slide_faces if surface.get("uncontrolled_slide", false) else collision_faces
			for index in indices:
				faces.append(positions[index])
		if surface["blend"] == "modulate":
			# A modulate surface darkens what is behind it through its texture.
			# Without the texture it is only a dark patch: collide, do not draw.
			continue
		if surface["blend"] == "additive":
			# Light cones and glows drawn by their gradient texture. Without it
			# they were flat translucent panes, dozens of them in the pillar
			# hall, all glare: collide, do not draw.
			continue
		var uvs := _uvs(record, _uv_set(record, surface), positions.size())
		var material_name: String = surface["material"] if surface["material"] != null else ""
		var material: Material
		if _bakes.has(material_name) and surface["blend"] != "additive":
			material = _textured_material(material_name, surface["blend"], surface["unlit"])
		else:
			material = _material(Common.material_family(material_name, name), surface["blend"], surface["unlit"])
		var described := {material = material_name, blend = surface["blend"], unlit = surface["unlit"],
				nondirectional = surface.get("nondirectional", false)}
		_add_surface(mesh, positions, normals, uvs, uv2, tangents, indices, material, material_name)
		slots.append(surface["slot"])
		drawn.append(described)
		sources.append(indices if normals.is_empty() else PackedInt32Array())
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
			_add_surface(mesh, positions, back_normals, uvs, uv2, tangents, back_indices, material, material_name + "_back")
			slots.append(surface["slot"])
			drawn.append(described)
			sources.append(back_indices if normals.is_empty() else PackedInt32Array())
	var simple: Array[Shape3D] = []
	for shape: Dictionary in record["simple_shapes"]:
		var convex := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for v: Array in shape["vertices"]:
			points.append(Common.v3(v))
		convex.points = points
		simple.append(convex)
	mesh.set_meta("surface_slots", slots)
	mesh.set_meta("surface_materials", drawn)
	mesh.set_meta("flat_sources", sources)
	mesh.set_meta("simple_shapes", simple)
	# Whether a pawn's box takes the hulls rather than the triangles: with it
	# set and no hulls, the mesh blocks nothing (see the extractor's
	# collision_class).
	mesh.set_meta("use_simple_box_collision", record.get("use_simple_box_collision", true) != false)
	if not collision_faces.is_empty():
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(collision_faces)
		mesh.set_meta("per_poly_shape", concave)
	if not slide_faces.is_empty():
		var slide := ConcavePolygonShape3D.new()
		slide.set_faces(slide_faces)
		mesh.set_meta("slide_shape", slide)
	var bounds: Dictionary = record["bounds"]
	var extent := Common.v3(bounds["extent"])
	mesh.set_meta("bounds", AABB(Common.v3(bounds["origin"]) - extent, extent * 2.0))
	# What the original's PhysX cloth was given, for the placements the level
	# hangs rather than draws. Empty on everything else.
	var cloth: Dictionary = record.get("cloth", {})
	if not cloth.is_empty():
		mesh.set_meta("cloth", cloth)
	return mesh


func _add_surface(mesh: ArrayMesh, positions: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, uv2: PackedVector2Array, tangents: PackedFloat32Array,
		indices: PackedInt32Array, material: Material, surface_name: String) -> void:
	var arrays := []
	if normals.is_empty():
		# The original cooked this mesh without normals: shade it flat. One
		# vertex per corner, in index order (the mesh's flat_sources).
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		for index in indices:
			if not uvs.is_empty():
				st.set_uv(uvs[index])
			if not uv2.is_empty():
				st.set_uv2(uv2[index])
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
		if not uv2.is_empty():
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
		if not tangents.is_empty():
			arrays[Mesh.ARRAY_TANGENT] = tangents
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


func _bake_hash(surface: Dictionary) -> String:
	var name: String = surface["material"] if surface["material"] != null else ""
	if not _bakes.has(name):
		return ""
	if not _bake_hashes.has(name):
		_bake_hashes[name] = JSON.stringify(_bakes[name], "", true).sha256_text()
	return _bake_hashes[name]


## How far across a channel's coordinates spread before it counts as one the
## mesh actually carries. A channel left at zero is not a coordinate set.
const MIN_UV_SPAN := 0.05

## Which of a mesh's coordinate sets a surface is drawn in: the one its
## material samples, when the mesh has it and it holds a layout.
##
## A material names its set by index and is shared by meshes that do not all
## carry it. The truck's M_Outside samples set 2; its rear doors carry three
## sets whose third is all zeros, the forklift only two. Falling back to the
## LAST set a mesh has draws it in the lightmap's atlas UVs -- stretched and
## offset, which is how the doors and the forklift looked. Set 0 is where the
## cooked meshes keep the picture.
func _uv_set(record: Dictionary, surface: Dictionary) -> int:
	var bake: Variant = _bakes.get(surface["material"] if surface["material"] != null else "")
	var wanted: int = int(bake["uv_set"]) if bake is Dictionary else 0
	# Where a placement overrides this slot, the override is what draws the
	# surface, so its set is the one that matters. The element's own material
	# can be a placeholder that samples something else entirely.
	if surface.has("override_uv_set"):
		wanted = int(surface["override_uv_set"])
	var sets: Array = record.get("uvs", [])
	if wanted < sets.size() and _uv_span(sets[wanted]) >= MIN_UV_SPAN:
		return wanted
	return 0


static func _uv_span(encoded: String) -> float:
	var raw := Marshalls.base64_to_raw(encoded).to_float32_array()
	if raw.is_empty():
		return 0.0
	var low := Vector2(raw[0], raw[1])
	var high := low
	for i in range(0, raw.size(), 2):
		low = low.min(Vector2(raw[i], raw[i + 1]))
		high = high.max(Vector2(raw[i], raw[i + 1]))
	return maxf(high.x - low.x, high.y - low.y)


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
	var hash := JSON.stringify([bake, blend, unlit, TEXTURE_ALBEDO, baker_tint_strength,
			normal_scale, LIBRARY_FORMAT]).sha256_text()
	var dir := Common.LIBRARY_DIR.path_join("materials").path_join("textured")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join(key + ".res")
	if ResourceLoader.exists(path):
		var existing: StandardMaterial3D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			_materials[key] = load(path)
			return _materials[key]
	var textures := _bake_textures(material_name)
	if not textures.has("albedo"):
		return _material("default", blend, unlit)
	var material := StandardMaterial3D.new()
	material.albedo_texture = textures["albedo"]
	material.albedo_color = TEXTURE_ALBEDO
	if bake.has("baker_tint"):
		# The colour the original's lightmap carried and the diffuse does not
		# (materials.py, baker_tint). Off at strength 0, the bake as it is.
		var tint: Array = bake["baker_tint"]
		material.albedo_color *= Color(1.0, 1.0, 1.0).lerp(
				Color(tint[0], tint[1], tint[2]), clampf(baker_tint_strength, 0.0, 1.0))
	material.uv1_scale = Vector3(bake["tiling"][0], bake["tiling"][1], 1.0)
	if textures.has("normal"):
		material.normal_enabled = true
		material.normal_texture = textures["normal"]
		material.normal_scale = normal_scale
	var roughness: float = float(bake.get("roughness", DEFAULT_ROUGHNESS))
	material.roughness = roughness
	if bake.has("specular"):
		material.metallic_specular = clampf(float(bake["specular"]) * SPECULAR_SCALE, 0.0, 1.0)
	if bake.has("metallic_png"):
		# Mirror where the original put the sky into the colour through a cube
		# map, and sharp there: metallic and roughness from one mask.
		var mask := Image.new()
		mask.load_png_from_buffer(Marshalls.base64_to_raw(bake["metallic_png"]))
		mask.convert(Image.FORMAT_L8)
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


## The images a material's bake carries, each a texture file of its own in
## the library: the plain material and every lightmapped one draw the same
## file. {albedo, normal, emissive}, whichever the bake has.
func _bake_textures(material_name: String) -> Dictionary:
	if _textures.has(material_name):
		return _textures[material_name]
	var bake: Dictionary = _bakes[material_name]
	var hash := JSON.stringify([bake, LIBRARY_FORMAT]).sha256_text()
	var out := {}
	for kind: Array in [["albedo", "png", Image.COMPRESS_SOURCE_SRGB],
			["normal", "normal_png", Image.COMPRESS_SOURCE_NORMAL],
			["emissive", "emissive_png", Image.COMPRESS_SOURCE_SRGB]]:
		if bake.has(kind[1]):
			var texture := _texture_file(material_name, kind[0], bake[kind[1]], kind[2], hash)
			if texture != null:
				out[kind[0]] = texture
	_textures[material_name] = out
	return out


func _texture_file(material_name: String, kind: String, png: String, source: Image.CompressSource,
		hash: String) -> Texture2D:
	var dir := Common.LIBRARY_DIR.path_join("materials").path_join("textures")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join("%s_%s.res" % [material_name.validate_filename(), kind])
	if ResourceLoader.exists(path):
		var existing: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			return load(path)
	var image := Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(png)) != OK:
		push_error("[me_level] material %s: unreadable %s bake" % [material_name, kind])
		return null
	image.convert(Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	# Block-compressed in VRAM (BC7, one byte a pixel against four): the
	# bakes are 256 px now and a chapter carries hundreds. The mips are what
	# let a far wall sample a small level of it; no streaming in Godot 4.7,
	# so the whole chain is resident and this is where the memory is saved.
	image.compress(Image.COMPRESS_BPTC, source)
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("source_hash", hash)
	ResourceSaver.save(texture, path, ResourceSaver.FLAG_COMPRESS)
	return load(path)


## The material a surface lit by its lightmap draws with, or null for one the
## lightmap does not light: an unlit surface shows its own colour, and an
## additive or modulate one is not drawn. `atlas` is a texture lightmap's
## three coefficient textures, or empty for a vertex lightmap, whose samples
## ride on the placement's own copy of the mesh.
##
## No TEXTURE_ALBEDO and no baker_tint: both stand in for what the lightmap
## carries itself -- the brightness the bake gave the surface and the colour
## Beast was told it has.
func lightmap_material(entry: Dictionary, atlas: Array) -> ShaderMaterial:
	var blend: String = entry.get("blend", "opaque")
	if entry.get("unlit", false) or not LIGHTMAP_SHADERS.has(blend):
		return null
	var material_name: String = entry["material"] if entry.get("material") != null else ""
	var key := "%s|%s|%s|%s" % [material_name, blend, entry.get("nondirectional", false),
			",".join(atlas.map(func(t: Texture2D) -> String: return t.resource_path))]
	if _lightmapped.has(key):
		return _lightmapped[key]
	var material := ShaderMaterial.new()
	material.shader = LIGHTMAP_SHADERS[blend]
	if _bakes.has(material_name):
		var bake: Dictionary = _bakes[material_name]
		var textures := _bake_textures(material_name)
		if textures.has("albedo"):
			material.set_shader_parameter("albedo_texture", textures["albedo"])
			material.set_shader_parameter("use_albedo_texture", true)
		if textures.has("normal"):
			material.set_shader_parameter("normal_texture", textures["normal"])
			material.set_shader_parameter("use_normal_texture", true)
			material.set_shader_parameter("normal_scale", normal_scale)
		if textures.has("emissive"):
			material.set_shader_parameter("emissive_texture", textures["emissive"])
			material.set_shader_parameter("use_emissive_texture", true)
		material.set_shader_parameter("uv1_scale", Vector2(bake["tiling"][0], bake["tiling"][1]))
		if bake.has("specular"):
			material.set_shader_parameter("specular", maxf(float(bake["specular"]), 0.0))
		if bake.has("specular_power"):
			material.set_shader_parameter("specular_power", float(bake["specular_power"]))
	else:
		# No bake (DefaultMaterial, or one whose graph did not evaluate): the
		# family colour, lit by the bake like any other.
		var color: Color = Common.MATERIAL_PALETTE[Common.material_family(material_name, "")].srgb_to_linear()
		material.set_shader_parameter("albedo_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("nondirectional", entry.get("nondirectional", false))
	if atlas.is_empty():
		material.set_shader_parameter("vertex_lightmap", true)
	else:
		for k in atlas.size():
			material.set_shader_parameter("lightmap_%d" % k, atlas[k])
	_lightmapped[key] = material
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

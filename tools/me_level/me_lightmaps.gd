@tool
extends RefCounted

# The original's baked lighting onto an extracted level's static geometry: each
# lightmapped placement draws its surfaces with the mesh library's lightmapped
# materials (me_lightmap.gdshaderinc) and carries where it lies in its atlas,
# and each coefficient's scale, as instance shader parameters. A vertex
# lightmap's samples ride on the placement's own copy of the mesh.
#
# Everything is in the generated geometry scene: the materials as its
# sub-resources, the atlases as texture files beside it. Nothing is assembled
# when the level runs.

const Common := preload("res://tools/me_level/me_level_common.gd")

## Where the extractor wrote the atlases (DDS) and where their textures go.
var source_dir := ""
var target_dir := ""
## The mesh library that knows the materials.
var library = null
var counts := {texture = 0, vertex = 0, unlit_surfaces = 0}

var _atlases := {}


func _init(extract_dir: String, level_dir: String, mesh_library) -> void:
	source_dir = extract_dir
	target_dir = level_dir
	library = mesh_library
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))


## A coefficient texture of the chapter's, as the extractor wrote it: the
## original's own DXT1 blocks and mips, never recompressed.
func atlas(key: String) -> Texture2D:
	if _atlases.has(key):
		return _atlases[key]
	var source := source_dir.path_join(key + ".dds")
	var hash := FileAccess.get_md5(source)
	if hash.is_empty():
		push_error("[me_level] lightmap %s was not extracted" % source)
		return null
	var path := target_dir.path_join(key.validate_filename() + ".res")
	if ResourceLoader.exists(path):
		var existing: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			_atlases[key] = load(path)
			return _atlases[key]
	var image := Image.new()
	if image.load_dds_from_buffer(FileAccess.get_file_as_bytes(source)) != OK:
		push_error("[me_level] lightmap %s does not load" % source)
		return null
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("source_hash", hash)
	if ResourceSaver.save(texture, path) != OK:
		push_error("[me_level] saving %s" % path)
		return null
	_atlases[key] = load(path)
	return _atlases[key]


## The placement's lightmap onto its drawn mesh. Runs AFTER the placement's
## own material overrides: an override the lightmap does not light (an unlit
## sign) stays as it is.
func apply(instance: MeshInstance3D, lightmap: Dictionary, overrides: Array) -> void:
	var mesh: ArrayMesh = instance.mesh
	var drawn: Array = mesh.get_meta("surface_materials", [])
	var slots: PackedInt32Array = mesh.get_meta("surface_slots", PackedInt32Array())
	var textures := textures_of(lightmap)
	if lightmap["kind"] == "texture" and textures.is_empty():
		return
	if lightmap["kind"] == "vertex":
		instance.mesh = with_samples(mesh, Marshalls.base64_to_raw(lightmap["samples"]))
		counts.vertex += 1
	else:
		counts.texture += 1
	for surface in drawn.size():
		var entry: Dictionary = drawn[surface]
		var slot: int = slots[surface] if surface < slots.size() else -1
		if slot >= 0 and slot < overrides.size() and overrides[slot] is Dictionary \
				and library.override_material(overrides[slot]) != null:
			entry = overrides[slot]
		var material: Material = library.lightmap_material(entry, textures)
		if material == null:
			counts.unlit_surfaces += 1
			continue
		instance.set_surface_override_material(surface, material)
	set_parameters(instance, lightmap)


## Where the placement lies in its atlas and each coefficient's scale.
static func set_parameters(instance: GeometryInstance3D, lightmap: Dictionary) -> void:
	if lightmap["kind"] == "texture":
		var s: Array = lightmap["uv_scale"]
		var b: Array = lightmap["uv_bias"]
		instance.set_instance_shader_parameter(&"lightmap_uv_scale_bias", Vector4(s[0], s[1], b[0], b[1]))
	for k in 3:
		instance.set_instance_shader_parameter(StringName("lightmap_scale_%d" % k), Common.v3(lightmap["scales"][k]))


## A texture lightmap's three coefficient textures; empty for a vertex
## lightmap, or when one of them did not load.
func textures_of(lightmap: Dictionary) -> Array:
	var out := []
	if lightmap["kind"] != "texture":
		return out
	for key: String in lightmap["textures"]:
		var texture := atlas(key)
		if texture == null:
			return []
		out.append(texture)
	return out


## A copy of a library mesh carrying a vertex lightmap's three samples per
## vertex in CUSTOM0..2. One per placement: the samples are the placement's.
static func with_samples(source: ArrayMesh, samples: PackedByteArray) -> ArrayMesh:
	var flat: Array = source.get_meta("flat_sources", [])
	var copy := ArrayMesh.new()
	var format := (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var origin: PackedInt32Array = flat[surface] if surface < flat.size() else PackedInt32Array()
		# Three locals, not an Array of them: a packed array taken out of an
		# Array and written is a copy, and the Array's stays empty.
		var c0 := PackedByteArray()
		var c1 := PackedByteArray()
		var c2 := PackedByteArray()
		c0.resize(count * 4)
		c1.resize(count * 4)
		c2.resize(count * 4)
		for i in count:
			var at := (origin[i] if not origin.is_empty() else i) * 9
			var o := i * 4
			c0[o] = samples[at]
			c0[o + 1] = samples[at + 1]
			c0[o + 2] = samples[at + 2]
			c0[o + 3] = 255
			c1[o] = samples[at + 3]
			c1[o + 1] = samples[at + 4]
			c1[o + 2] = samples[at + 5]
			c1[o + 3] = 255
			c2[o] = samples[at + 6]
			c2[o + 1] = samples[at + 7]
			c2[o + 2] = samples[at + 8]
			c2[o + 3] = 255
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		arrays[Mesh.ARRAY_CUSTOM2] = c2
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
		copy.surface_set_material(surface, source.surface_get_material(surface))
		copy.surface_set_name(surface, source.surface_get_name(surface))
	# What drawing the copy needs; the collision stays on the library's mesh.
	for key in ["surface_slots", "surface_materials"]:
		if source.has_meta(key):
			copy.set_meta(key, source.get_meta(key))
	return copy

@tool
extends RefCounted

# The original's baked lighting onto an extracted level's static geometry: each
# lightmapped placement draws its surfaces with the mesh library's lightmapped
# materials (me_lightmap.gdshaderinc) and carries where it lies in its atlas,
# and each coefficient's scale, as instance shader parameters.
#
# A vertex lightmap's samples are the chapter's one samples texture, three
# texels a vertex, every placement's run of them one after another; the
# placement carries where its run starts. The placement keeps drawing the
# library's mesh, so placements of one mesh still draw instanced -- a copy of
# the mesh per placement cost the tutorial's overview 1900 draw calls.
#
# Everything is in the generated geometry scene: the materials as its
# sub-resources, the atlases and the samples as texture files beside it.
# Nothing is assembled when the level runs.

const Common := preload("res://tools/me_level/me_level_common.gd")

## Texels a row of the samples texture holds.
const SAMPLES_WIDTH := 4096
## Texels a vertex takes there: one per coefficient.
const TEXELS_PER_VERTEX := 3

## Where the extractor wrote the atlases (DDS) and where their textures go.
var source_dir := ""
var target_dir := ""
## The mesh library that knows the materials.
var library = null
var counts := {texture = 0, vertex = 0, unlit_surfaces = 0}

var _atlases := {}
var _samples: Texture2D = null
var _sample_offsets := {}


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


## The chapter's vertex lightmaps as one samples texture, saved before any
## geometry is built so every scene can name the file. Call once with ALL the
## chapter's placements: a split chapter's sections share it.
func prepare_vertex_samples(placements: Array) -> bool:
	var raw := PackedByteArray()
	_sample_offsets.clear()
	for p: Dictionary in placements:
		var lightmap: Dictionary = p.get("lightmap", {})
		if lightmap.get("kind", "") != "vertex":
			continue
		_sample_offsets[Common.actor_id(str(p["package"]), str(p["name"]))] = raw.size() / 9
		raw.append_array(Marshalls.base64_to_raw(lightmap["samples"]))
	if raw.is_empty():
		_samples = null
		return true
	var image := samples_image(raw)
	var hash := _hash(raw)
	var path := target_dir.path_join("vertex_samples.res")
	if ResourceLoader.exists(path):
		var existing: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			_samples = load(path)
			return true
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("source_hash", hash)
	if ResourceSaver.save(texture, path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("[me_level] saving %s" % path)
		return false
	_samples = load(path)
	return true


static func _hash(raw: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return context.finish().hex_encode()


## Samples of three RGB colours a vertex as an RGBA8 image, one texel each,
## row after row of SAMPLES_WIDTH.
static func samples_image(raw: PackedByteArray) -> Image:
	var texels := raw.size() / 3
	var rows := maxi(1, ceili(float(texels) / SAMPLES_WIDTH))
	var data := PackedByteArray()
	data.resize(SAMPLES_WIDTH * rows * 4)
	for t in texels:
		data[t * 4] = raw[t * 3]
		data[t * 4 + 1] = raw[t * 3 + 1]
		data[t * 4 + 2] = raw[t * 3 + 2]
		data[t * 4 + 3] = 255
	return Image.create_from_data(SAMPLES_WIDTH, rows, false, Image.FORMAT_RGBA8, data)


## The placement's lightmap onto its drawn mesh. Runs AFTER the placement's
## own material overrides: an override the lightmap does not light (an unlit
## sign) stays as it is. Whether any surface now draws from the bake.
func apply(instance: MeshInstance3D, placement: Dictionary) -> bool:
	var lightmap: Dictionary = placement["lightmap"]
	var overrides: Array = placement.get("materials", [])
	var mesh: ArrayMesh = instance.mesh
	var drawn: Array = mesh.get_meta("surface_materials", [])
	var slots: PackedInt32Array = mesh.get_meta("surface_slots", PackedInt32Array())
	var textures := textures_of(lightmap)
	if textures.is_empty():
		return false
	counts[lightmap["kind"]] += 1
	var lit := false
	for surface in drawn.size():
		var entry: Dictionary = drawn[surface]
		var slot: int = slots[surface] if surface < slots.size() else -1
		if slot >= 0 and slot < overrides.size() and overrides[slot] is Dictionary \
				and library.override_material(overrides[slot]) != null:
			entry = overrides[slot]
		var material: Material = library.lightmap_material(entry, textures, lightmap["kind"] == "vertex")
		if material == null:
			counts.unlit_surfaces += 1
			continue
		instance.set_surface_override_material(surface, material)
		lit = true
	set_parameters(instance, lightmap)
	if lightmap["kind"] == "vertex":
		instance.set_instance_shader_parameter(&"lightmap_vertex_offset",
				int(_sample_offsets[Common.actor_id(str(placement["package"]), str(placement["name"]))]))
	return lit


## Where the placement lies in its atlas and each coefficient's scale.
static func set_parameters(instance: GeometryInstance3D, lightmap: Dictionary) -> void:
	if lightmap["kind"] == "texture":
		var s: Array = lightmap["uv_scale"]
		var b: Array = lightmap["uv_bias"]
		instance.set_instance_shader_parameter(&"lightmap_uv_scale_bias", Vector4(s[0], s[1], b[0], b[1]))
	for k in 3:
		instance.set_instance_shader_parameter(StringName("lightmap_scale_%d" % k), Common.v3(lightmap["scales"][k]))


## What a lightmap samples: a texture lightmap's three coefficient textures,
## or the chapter's samples texture for a vertex one. Empty when one of them
## did not load.
func textures_of(lightmap: Dictionary) -> Array:
	if lightmap["kind"] == "vertex":
		return [_samples] if _samples != null else []
	var out := []
	for key: String in lightmap["textures"]:
		var texture := atlas(key)
		if texture == null:
			return []
		out.append(texture)
	return out

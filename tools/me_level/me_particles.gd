@tool
extends RefCounted

# The original's placed particle emitters, built from the extract's
# particles.json (docs/mirrors-edge-deep-research/tools/level_extract/
# particles.py): a node per Emitter actor where the actor stands, and under it
# one GPUParticles3D per emitter and LOD of its template. Holds no original
# data; the materials and textures it makes go into the mesh library.
#
# GPU, NOT CPU, PARTICLES: CPUParticles3D has no process shader, and the
# original's starting velocity is a box that ParticleProcessMaterial cannot
# express either (me_particle_process.gdshader says why).
#
# LODS ARE THE ORIGINAL'S. A template switches LOD by the camera's distance
# ([ME:CONFIRMED] VentSmoke_01_Big: LODDistances 0, 150, 750, 1250 ... uu) and
# its far LODs are not thinned copies of the near one -- they spawn fewer,
# larger particles: 75-100 uu up close, 225-250 past 12.5 m. Each LOD is its
# own node over its own visibility range, so what the player sees from across
# a roof is what the original drew there.
#
# PHYSX VENTS ARE BUILT TOO. The extract is the PhysX-enhanced level
# (particles.py, PHYSX_ENHANCED), and a PX_* vent is most of a roof's smoke
# there. Its LOD is an ordinary sprite emitter whose particles a PhysX fluid
# moves once spawned: here that is the fluid's acceleration (its own plus the
# scene's gravity), its damping and its motion limit, world space.
# [ME:INFERRED] what the fluid also does -- collide with the roof, push
# neighbours apart -- is left out; at a vent's spacing and speed neither shows.

const Common := preload("res://tools/me_level/me_level_common.gd")
const PROCESS_SHADER := preload("res://tools/me_level/me_particle_process.gdshader")
const SPRITE_SHADER := preload("res://tools/me_level/me_particle_sprite.gdshader")

## Templates that are built, by name prefix. The other systems are extracted
## and counted but not built until each family has been judged against the
## original: one that happens to use only the modules below could still read
## nothing like itself (a flock of birds is a sprite emitter too).
const BUILT_FAMILIES: Array[String] = ["PS_FX_LevelFX_Smoke_VentSmoke_", "PX_Smoke_VentSmoke_"]
## The modules a LOD may use. Any other enabled module and the LOD is not built.
const MODULES: Array[String] = ["Lifetime", "Size", "Velocity", "Rotation", "SizeMultiplyLife",
		"ColorOverLife", "AccelerationOverLifetime", "SubUV", "Location"]
## Bumped when the mapping changes, so every saved material is rebuilt.
const FORMAT := 2
const LIBRARY := Common.LIBRARY_DIR + "/particles"
## The original's frame rate, at which a fluid's per-step motion limit becomes
## a speed. [ME:CONFIRMED Engine/Config/BaseEngine.ini] MaxSmoothedFrameRate 62;
## [ME:CONFIRMED Engine.u WorldInfo] the fluid compartment is not fixed-step and
## takes one sub step, so it steps once a frame. VentSmoke's 1 uu a step is
## 0.62 m/s: DO NOT drop the limit as a detail, it is what keeps the plume a
## low billow over the unit instead of a column three metres high.
const ORIGINAL_FRAME_RATE := 62.0
## Points a curve is rebuilt from, and the width of the texture it bakes to.
const CURVE_TEXTURE_WIDTH := 64

var systems := {}
var textures := {}
## Where the materials, textures and the quad are saved. A test points it elsewhere.
var library_dir := LIBRARY
## The level's exposure (me_environment.gd), which every sprite undoes: see
## exposure_compensation in me_particle_sprite.gdshader. 1.0 for a level
## with no look of its own.
var exposure := 1.0
## What was built and what was not, and why, for the build log.
var counts := {}
var _built := {}
var _textures := {}
var _quad: QuadMesh = null


func _init(data: Dictionary = {}) -> void:
	systems = data.get("systems", {})
	textures = data.get("textures", {})


## The level's emitters under one node, or null when none is built.
func build(emitters: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Particles"
	var names := Common.NameAllocator.new()
	for entry: Dictionary in emitters:
		var template: String = entry["template"]
		if not is_built_family(template):
			_count("not built: %s" % template.get_slice("@", 0))
			continue
		if entry.get("hidden", false):
			_count("hidden")
			continue
		var system: Dictionary = systems.get(template, {})
		if system.is_empty():
			push_error("[me_level] emitter %s names template %s, which the extract lacks" % [entry["name"], template])
			continue
		var holder := Node3D.new()
		holder.name = names.take(template.get_slice("@", 0).trim_prefix("PS_FX_"))
		holder.transform = Common.transform_of(entry)
		holder.set_meta(Common.PACKAGE_META, Common.package_key(str(entry["package"])))
		holder.set_meta(Common.ACTOR_META, Common.actor_id(str(entry["package"]), str(entry["name"])))
		holder.set_meta(&"me_template", template)
		var distances: Array = system.get("lod_distances_m", [0.0])
		for e in system["emitters"].size():
			var emitter: Dictionary = system["emitters"][e]
			var lods: Array = emitter["lods"]
			for lod: Dictionary in lods:
				var params := describe(lod, float(system.get("warmup", 0.0)))
				if params.has("unsupported"):
					_count("lod left out: %s" % params["unsupported"])
					continue
				var node := _particles(params, _materials_for(template, e, lod, params))
				node.name = "%s_LOD%d" % [str(emitter.get("name", "Emitter%d" % e)).validate_node_name(), int(lod["level"])]
				var level := int(lod["level"])
				node.visibility_range_begin = float(distances[level]) if level < distances.size() else 0.0
				# Up to where the next LOD takes over; the last one never ends.
				var last := mini(lods.size(), distances.size()) - 1
				node.visibility_range_end = float(distances[level + 1]) if level < last else 0.0
				node.emitting = bool(entry.get("auto_activate", true))
				holder.add_child(node)
		if holder.get_child_count() == 0:
			holder.free()
			continue
		_count("built: %s" % template.get_slice("@", 0))
		root.add_child(holder)
	if root.get_child_count() == 0:
		root.free()
		return null
	return root


static func is_built_family(template: String) -> bool:
	for prefix in BUILT_FAMILIES:
		if template.begins_with(prefix):
			return true
	return false


func _count(what: String) -> void:
	counts[what] = counts.get(what, 0) + 1


# ---------------------------------------------------------------- mapping

## One LOD of an emitter as the flat parameters its node and materials are
## made from, or {unsupported: why}. Everything the original's data says and
## this cannot draw is a reason, never a silent default.
static func describe(lod: Dictionary, warmup: float) -> Dictionary:
	if not lod.get("enabled", true):
		return {unsupported = "disabled"}
	var fluid: Variant = null
	if lod.has("type_data"):
		var type_data: Dictionary = lod["type_data"]
		if str(type_data["class"]) != "TypeDataPhysX" or not type_data.get("fluid") is Dictionary:
			return {unsupported = "type data %s" % type_data["class"]}
		fluid = type_data["fluid"]
	var required: Dictionary = lod.get("required", {}).get("props", {})
	var spawn: Dictionary = lod.get("spawn", {}).get("props", {})
	var material: Variant = lod.get("material")
	if not material is Dictionary or not material.get("supported", false):
		return {unsupported = "material"}
	if material.get("blend", "") != "translucent" or not material.get("unlit", false):
		return {unsupported = "material blend %s" % material.get("blend", "")}
	var alignment: Variant = required.get("ScreenAlignment")
	if alignment != null and str(alignment) != "PSA_Square":
		return {unsupported = "screen alignment %s" % alignment}
	if int(required.get("EmitterLoops", 0)) != 0:
		return {unsupported = "emitter loops"}
	if not (spawn.get("BurstList", []) as Array).is_empty():
		return {unsupported = "bursts"}
	# [ME:INFERRED] the Spawn module's Rate is the rate. Required's SpawnRate is
	# the engine's older field: Engine.u keeps it without CPF_Edit (flags
	# 0x480000, Spawn.Rate 0x480001), and holds one value copied to every LOD,
	# while Spawn.Rate changes per LOD and is 0 on every vent's last.
	var rate := _constant(spawn.get("Rate")) * _constant(spawn.get("RateScale"), 1.0)
	if is_nan(rate):
		return {unsupported = "spawn rate is not a constant"}
	if rate <= 0.0:
		return {unsupported = "spawns nothing"}
	var params := {
		rate = rate, warmup = warmup, life = [1.0, 1.0],
		local = bool(required.get("bUseLocalSpace", false)),
		location = [Vector3.ZERO, Vector3.ZERO], velocity = [Vector3.ZERO, Vector3.ZERO],
		size = [1.0, 1.0], rotation = [0.0, 0.0],
		size_curve = {scale = 1.0}, color = {scale = Vector3.ONE}, alpha = {scale = 1.0},
		accel = {scale = Vector3.ZERO}, sub_image = {scale = 0.0},
		world_accel = Vector3.ZERO, damping = 0.0, max_speed = 0.0,
		clamp_alpha = true,
		sub_images = Vector2(maxi(int(required.get("SubImages_Horizontal", 1)), 1),
				maxi(int(required.get("SubImages_Vertical", 1)), 1)),
		blend_sub_images = false,
	}
	if fluid != null:
		# [ME:INFERRED] PhysX simulates in its own scene, in the world:
		# bUseLocalSpace does not carry a fluid's particles with the emitter.
		params.local = false
		params.world_accel = Common.v3(fluid.get("acceleration", [0.0, 0.0, 0.0]))
		params.damping = float(fluid.get("damping", 0.0))
		params.max_speed = float(fluid.get("max_motion", 0.0)) * ORIGINAL_FRAME_RATE
	var interpolation := str(required.get("InterpolationMethod", "PSUVIM_None"))
	for module: Dictionary in lod.get("modules", []):
		if not module.get("enabled", true):
			continue
		if str(module["class"]) not in MODULES:
			return {unsupported = "module %s" % module["class"]}
		var props: Dictionary = module["props"]
		match str(module["class"]):
			"Lifetime":
				params.life = _range(props.get("Lifetime"))
			"Size":
				var size := _vector_range(props.get("StartSize"))
				if size.is_empty():
					return {unsupported = "size is not a constant or a range"}
				params.size = [size[0].x, size[1].x]
			"Velocity":
				if bool(props.get("bInWorldSpace", false)):
					return {unsupported = "velocity in world space"}
				var radial := _range(props.get("StartVelocityRadial"))
				if not is_zero_approx(radial[0]) or not is_zero_approx(radial[1]):
					return {unsupported = "radial velocity"}
				params.velocity = _vector_range(props.get("StartVelocity"))
				if params.velocity.is_empty():
					return {unsupported = "velocity is not a constant or a range"}
			"Location":
				params.location = _vector_range(props.get("StartLocation"))
				if params.location.is_empty():
					return {unsupported = "location is not a constant or a range"}
			"Rotation":
				# Turns in the original: 1.0 is a whole revolution.
				var turns := _range(props.get("StartRotation"))
				params.rotation = [turns[0] * TAU, turns[1] * TAU]
			"SizeMultiplyLife":
				# A square sprite takes X alone.
				if bool(props.get("MultiplyX", true)):
					params.size_curve = _channel(props.get("LifeMultiplier"), 0)
			"ColorOverLife":
				params.color = _vector_curve(props.get("ColorOverLife"))
				params.alpha = _channel(props.get("AlphaOverLife"), 0)
				params.clamp_alpha = bool(props.get("bClampAlpha", true))
			"AccelerationOverLifetime":
				if bool(props.get("bAlwaysInWorldSpace", false)) and params.local:
					return {unsupported = "world-space acceleration on a local emitter"}
				params.accel = _vector_curve(props.get("AccelOverLife"))
			"SubUV":
				# PSUVIM_None: the module does nothing and the sheet's first image stands.
				if interpolation not in ["PSUVIM_None", "PSUVIM_Linear", "PSUVIM_Linear_Blend"]:
					return {unsupported = "sub image interpolation %s" % interpolation}
				if interpolation != "PSUVIM_None":
					params.blend_sub_images = interpolation == "PSUVIM_Linear_Blend"
					params.sub_image = _channel(props.get("SubImageIndex"), 0)
			_:
				return {unsupported = "module %s" % module["class"]}
		for key in ["life", "size", "rotation"]:
			if params[key] is Array and is_nan(float(params[key][0])):
				return {unsupported = "%s is not a constant or a range" % key}
	params.amount = maxi(ceili(rate * float(params.life[1])), 1)
	params.material = material
	return params


## A constant distribution's value, NAN for any other kind. `fallback` when
## there is no distribution at all.
static func _constant(dist: Variant, fallback := 0.0) -> float:
	if not dist is Dictionary:
		return fallback
	if dist["kind"] == "constant":
		return float(dist["value"][0])
	return NAN


## [min, max] of a constant or uniform float distribution, NANs otherwise.
static func _range(dist: Variant) -> Array:
	if not dist is Dictionary:
		return [0.0, 0.0]
	match str(dist["kind"]):
		"constant":
			return [float(dist["value"][0]), float(dist["value"][0])]
		"uniform":
			return [float(dist["min"][0]), float(dist["max"][0])]
	return [NAN, NAN]


## [min, max] of a constant or uniform vector distribution, [] otherwise.
static func _vector_range(dist: Variant) -> Array:
	if not dist is Dictionary:
		return [Vector3.ZERO, Vector3.ZERO]
	match str(dist["kind"]):
		"constant":
			return [Common.v3(dist["value"]), Common.v3(dist["value"])]
		"uniform":
			return [Common.v3(dist["min"]), Common.v3(dist["max"])]
	return []


## {scale} for a constant, {scale = 1, samples} for a curve: one channel of a
## float or vector distribution.
static func _channel(dist: Variant, channel: int) -> Dictionary:
	if not dist is Dictionary:
		return {scale = 1.0}
	match str(dist["kind"]):
		"constant":
			return {scale = float(dist["value"][channel])}
		"curve":
			return {scale = 1.0, samples = (dist["samples"] as Array).map(func(s): return float(s[channel]))}
	return {scale = 1.0}


static func _vector_curve(dist: Variant) -> Dictionary:
	if not dist is Dictionary:
		return {scale = Vector3.ONE}
	match str(dist["kind"]):
		"constant":
			return {scale = Common.v3(dist["value"])}
		"curve":
			return {scale = Vector3.ONE, samples = (dist["samples"] as Array).map(func(s): return Common.v3(s))}
	return {scale = Vector3.ONE}


# ---------------------------------------------------------------- nodes

func _particles(params: Dictionary, materials: Array) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.amount = int(params.amount)
	node.lifetime = maxf(float(params.life[1]), 0.01)
	# A Godot system's state repeats every lifetime -- each particle slot is
	# re-emitted once a cycle -- so the original's WarmupTime only has to reach
	# one: fifteen seconds of a one-second plume is fifteen identical cycles.
	node.preprocess = minf(float(params.warmup), node.lifetime)
	node.local_coords = bool(params.local)
	node.process_material = materials[0]
	node.material_override = materials[1]
	node.draw_pass_1 = _quad_mesh()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_aabb = visibility_box(params)
	return node


## A box round the emitter that holds every particle, centred on the
## emitter: the visibility range is measured to the box's centre, and the
## original measures its LOD distance to the emitter itself.
static func visibility_box(params: Dictionary) -> AABB:
	var life := float(params.life[1])
	var speed := maxf((params.velocity[0] as Vector3).abs().length(), (params.velocity[1] as Vector3).abs().length())
	var accel := 0.0
	var scale: Vector3 = params.accel.scale
	for sample: Vector3 in params.accel.get("samples", [Vector3.ONE]):
		accel = maxf(accel, (sample * scale).length())
	accel += (params.world_accel as Vector3).length()
	var size := maxf(absf(float(params.size[0])), absf(float(params.size[1])))
	var grow := float(params.size_curve.scale)
	for sample in params.size_curve.get("samples", [1.0]):
		grow = maxf(grow, absf(float(sample) * float(params.size_curve.scale)))
	var offset := maxf((params.location[0] as Vector3).abs().length(), (params.location[1] as Vector3).abs().length())
	var reach := offset + speed * life + 0.5 * accel * life * life + 0.5 * size * grow
	return AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)


func _quad_mesh() -> QuadMesh:
	if _quad == null:
		var path := library_dir.path_join("sprite_quad.res")
		if ResourceLoader.exists(path):
			_quad = load(path)
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(library_dir))
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			ResourceSaver.save(quad, path)
			_quad = load(path)
	return _quad


# ---------------------------------------------------------------- materials

## [process material, sprite material] of one LOD, saved in the library and
## rebuilt only when what they are made from changed. The sprite material is
## one per exposure as well: every chapter is exposed for its own sun.
func _materials_for(template: String, emitter: int, lod: Dictionary, params: Dictionary) -> Array:
	var key := ("%s_%d_%d" % [template, emitter, int(lod["level"])]).validate_filename().replace("@", "_")
	var compensation := snappedf(1.0 / maxf(exposure, 0.0001), 0.001)
	var sprite_key := "%s_x%s" % [key, str(compensation).replace(".", "_")]
	if _built.has(sprite_key):
		return _built[sprite_key]
	var hash := JSON.stringify([lod, params.warmup, FORMAT], "", true).sha256_text()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(library_dir))
	var process: Resource = _saved(library_dir.path_join(key + "_process.res"), hash,
			func(): return process_material(params))
	var sprite: Resource = _saved(library_dir.path_join(sprite_key + "_sprite.res"), hash,
			func(): return sprite_material(params.material, params, _texture(_sheet_name(params.material)), compensation))
	_built[sprite_key] = [process, sprite]
	return _built[sprite_key]


## The resource at `path` when it was made from `hash`, else `make`'s, saved there.
func _saved(path: String, hash: String, make: Callable) -> Resource:
	if ResourceLoader.exists(path):
		var existing: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			return load(path)
	var made: Resource = make.call()
	made.set_meta("source_hash", hash)
	ResourceSaver.save(made, path, ResourceSaver.FLAG_COMPRESS)
	return load(path)

static func process_material(params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PROCESS_SHADER
	var life: Array = params.life
	material.set_shader_parameter("lifetime_min_ratio", clampf(float(life[0]) / maxf(float(life[1]), 0.0001), 0.0, 1.0))
	material.set_shader_parameter("location_min", params.location[0])
	material.set_shader_parameter("location_max", params.location[1])
	material.set_shader_parameter("velocity_min", params.velocity[0])
	material.set_shader_parameter("velocity_max", params.velocity[1])
	material.set_shader_parameter("size_min", float(params.size[0]))
	material.set_shader_parameter("size_max", float(params.size[1]))
	material.set_shader_parameter("rotation_min", float(params.rotation[0]))
	material.set_shader_parameter("rotation_max", float(params.rotation[1]))
	material.set_shader_parameter("clamp_alpha", bool(params.clamp_alpha))
	material.set_shader_parameter("color_scale", params.color.scale)
	material.set_shader_parameter("alpha_scale", float(params.alpha.scale))
	material.set_shader_parameter("accel_scale", params.accel.scale)
	material.set_shader_parameter("world_accel", params.world_accel)
	material.set_shader_parameter("damping", float(params.damping))
	material.set_shader_parameter("max_speed", float(params.max_speed))
	material.set_shader_parameter("sub_image_scale", float(params.sub_image.scale))
	for channel in [["size_curve", params.size_curve], ["alpha_curve", params.alpha],
			["sub_image_curve", params.sub_image]]:
		if (channel[1] as Dictionary).has("samples"):
			material.set_shader_parameter(channel[0], curve_texture(channel[1].samples))
	for channel in [["color_curve", params.color], ["accel_curve", params.accel]]:
		if (channel[1] as Dictionary).has("samples"):
			material.set_shader_parameter(channel[0], curve_xyz_texture(channel[1].samples))
	return material


## The material's graph (particles.py's reading of it) as the sprite shader's
## uniforms. describe() has already refused a graph this cannot draw.
static func sprite_material(material: Dictionary, params: Dictionary, sheet: Texture2D,
		compensation := 1.0) -> ShaderMaterial:
	var out := ShaderMaterial.new()
	out.shader = SPRITE_SHADER
	out.set_shader_parameter("exposure_compensation", compensation)
	out.set_shader_parameter("sheet", sheet)
	out.set_shader_parameter("sub_images", params.sub_images)
	out.set_shader_parameter("blend_sub_images", params.blend_sub_images)
	var emissive := _factors(material.get("emissive", {}))
	out.set_shader_parameter("emissive_textured", emissive.textured)
	out.set_shader_parameter("emissive_mask", emissive.mask)
	out.set_shader_parameter("emissive_rgb", emissive.rgb)
	out.set_shader_parameter("emissive_particle_color", emissive.particle)
	out.set_shader_parameter("emissive_scale", emissive.scale)
	var opacity := _factors(material.get("opacity", {}))
	out.set_shader_parameter("opacity_textured", opacity.textured)
	out.set_shader_parameter("opacity_mask", opacity.mask)
	out.set_shader_parameter("opacity_particle_alpha", opacity.particle)
	out.set_shader_parameter("opacity_scale", opacity.scale)
	var limits: Array = material.get("opacity", {}).get("clamp", [0.0, 1.0])
	out.set_shader_parameter("opacity_clamp", Vector2(float(limits[0]), float(limits[1])))
	out.set_shader_parameter("depth_fade_m", depth_fade_m(material.get("opacity", {}).get("depth_fade", {})))
	return out


## How far behind a sprite the scene has to be before the sprite is fully
## opaque, in metres. [ME:CONFIRMED Engine/Shaders/MaterialTemplate.usf
## DepthBiasedAlpha] saturate((scene depth - sprite depth) / ((1 - Bias) *
## BiasScale)) in uu: the smoke's 0.5 and 400 fade it in over 2 m.
static func depth_fade_m(fade: Dictionary) -> float:
	if fade.is_empty():
		return 0.0
	return maxf((1.0 - float(fade.get("bias", 0.0))) * float(fade.get("bias_scale", 1.0)), 0.0) / 100.0


## A product of factors as textured, mask, rgb, particle and scale: whether a
## texture is in it at all, the one channel it takes (or the texture's RGB),
## whether the particle's colour is in it, and every constant multiplied
## together. DO NOT stand a missing texture in with a mask: the shader samples
## the sheet the OTHER term reads, and M_PX_VentSmoke_01's brightness (the
## particle's colour alone) came out as the mean of its opacity texture.
static func _factors(term: Dictionary) -> Dictionary:
	var out := {textured = false, mask = Vector4.ZERO, rgb = false, particle = false, scale = 1.0}
	for factor: Dictionary in term.get("factors", []):
		match str(factor["kind"]):
			"particle_color":
				out.particle = true
			"constant":
				out.scale *= float(factor["value"])
			"texture":
				out.textured = true
				var channels := str(factor["channels"])
				if channels.length() == 1:
					var mask := Vector4.ZERO
					mask["RGBA".find(channels)] = 1.0
					out.mask = mask
				else:
					out.rgb = true
	return out


static func _sheet_name(material: Dictionary) -> String:
	for term in [material.get("emissive", {}), material.get("opacity", {})]:
		for factor: Dictionary in term.get("factors", []):
			if factor["kind"] == "texture":
				return str(factor["texture"])
	return ""


func _texture(name: String) -> Texture2D:
	if name.is_empty() or not textures.has(name):
		return null
	if _textures.has(name):
		return _textures[name]
	var bake: Dictionary = textures[name]
	var hash := JSON.stringify([bake, FORMAT]).sha256_text()
	var dir := library_dir.path_join("textures")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join(name.validate_filename() + ".res")
	if ResourceLoader.exists(path):
		var existing: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if existing != null and existing.get_meta("source_hash", "") == hash:
			_textures[name] = load(path)
			return _textures[name]
	var image := Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(bake["png"])) != OK:
		push_error("[me_level] particle texture %s: unreadable" % name)
		return null
	image.convert(Image.FORMAT_RGBA8)
	# The sprite shader samples as sRGB: a linear texture is encoded so that
	# what it reads back is what the original stored.
	if not bake.get("srgb", true):
		image.linear_to_srgb()
	image.generate_mipmaps()
	image.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("source_hash", hash)
	ResourceSaver.save(texture, path, ResourceSaver.FLAG_COMPRESS)
	_textures[name] = load(path)
	return _textures[name]


# ---------------------------------------------------------------- curves

## A curve through evenly spaced samples over [0, 1], baked to a texture the
## process shader reads by a particle's age. DO NOT add the points before the
## value range is set: a Curve clamps every point into [min_value, max_value],
## 0 to 1 by default, and an acceleration of -128 becomes 0.
static func curve_of(samples: Array) -> Curve:
	var curve := Curve.new()
	var low := 0.0
	var high := 1.0
	for s in samples:
		low = minf(low, float(s))
		high = maxf(high, float(s))
	curve.min_value = low
	curve.max_value = high
	for i in samples.size():
		var t := float(i) / float(maxi(samples.size() - 1, 1))
		curve.add_point(Vector2(t, float(samples[i])), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


static func curve_texture(samples: Array) -> CurveTexture:
	var texture := CurveTexture.new()
	texture.width = CURVE_TEXTURE_WIDTH
	texture.curve = curve_of(samples)
	return texture


static func curve_xyz_texture(samples: Array) -> CurveXYZTexture:
	var texture := CurveXYZTexture.new()
	texture.width = CURVE_TEXTURE_WIDTH
	texture.curve_x = curve_of(samples.map(func(v: Vector3): return v.x))
	texture.curve_y = curve_of(samples.map(func(v: Vector3): return v.y))
	texture.curve_z = curve_of(samples.map(func(v: Vector3): return v.z))
	return texture

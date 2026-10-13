extends GutTest

# How an extracted emitter LOD becomes a GPUParticles3D and its two materials
# (tools/me_level/me_particles.gd). The data is shaped as particles.py writes
# it: distributions decoded, spatial values already in Godot metres and axes.
# No original data: the numbers are VentSmoke_01_Big's LOD 0 as it reads.

const MeParticles := preload("res://tools/me_level/me_particles.gd")
const LIBRARY := "user://test_me_particles"


static func _uniform(low: Array, high: Array, cls := "DistributionFloatUniform") -> Dictionary:
	return {"class": cls, "kind": "uniform", "min": low, "max": high}


static func _constant(value: Array, cls := "DistributionFloatConstant") -> Dictionary:
	return {"class": cls, "kind": "constant", "value": value}


static func _curve(samples: Array, cls := "DistributionFloatConstantCurve") -> Dictionary:
	return {"class": cls, "kind": "curve", "points": [], "samples": samples}


static func _module(cls: String, props: Dictionary, enabled := true) -> Dictionary:
	return {"class": cls, "enabled": enabled, "props": props}


static func _material() -> Dictionary:
	return {
		"name": "M_Smoke", "blend": "translucent", "unlit": true, "two_sided": false, "supported": true,
		"emissive": {"factors": [{"kind": "particle_color", "channels": "RGB"},
				{"kind": "texture", "texture": "T_Sheet", "channels": "G", "sub_uv": true}]},
		"opacity": {"factors": [{"kind": "texture", "texture": "T_Sheet", "channels": "A", "sub_uv": true},
				{"kind": "particle_color", "channels": "A"}],
				"depth_fade": {"bias": 0.5, "bias_scale": 400.0}, "clamp": [0.0, 15.0]},
	}


static func _lod(level := 0, rate := 5.0) -> Dictionary:
	return {
		"level": level, "enabled": true, "material": _material(),
		"required": _module("Required", {"SpawnRate": _constant([2.0]), "SubImages_Horizontal": 4,
				"SubImages_Vertical": 4, "InterpolationMethod": "PSUVIM_Linear_Blend", "EmitterDuration": 1.0}),
		"spawn": _module("Spawn", {"Rate": _constant([rate]), "RateScale": _constant([1.0])}),
		"modules": [
			_module("Lifetime", {"Lifetime": _uniform([0.75], [1.0])}),
			_module("Size", {"StartSize": _uniform([0.75, 0.75, 0.75], [1.0, 1.0, 1.0], "DistributionVectorUniform")}),
			_module("Velocity", {"StartVelocity": _uniform([-0.1, 0.15, -0.02], [-0.05, 0.25, 0.02], "DistributionVectorUniform"),
					"StartVelocityRadial": _uniform([0.0], [0.0])}),
			_module("SizeMultiplyLife", {"LifeMultiplier": _curve([[0.15, 0.15, 0.15], [2.0, 2.0, 2.0]],
					"DistributionVectorConstantCurve"), "MultiplyX": true}),
			_module("Rotation", {"StartRotation": _uniform([-0.2], [0.2])}),
			_module("ColorOverLife", {"ColorOverLife": _constant([1.357, 1.357, 1.357], "DistributionVectorConstant"),
					"AlphaOverLife": _curve([[0.0], [0.6], [0.0]]), "bClampAlpha": true}),
			_module("AccelerationOverLifetime", {"AccelOverLife": _curve([[-0.2, 0.75, 0.0], [-1.29, 0.75, 0.0]],
					"DistributionVectorConstantCurve")}),
			_module("SubUV", {"SubImageIndex": _curve([[8.1], [13.1]])}),
			_module("Location", {"StartLocation": _uniform([-2.0, 0.0, -2.0], [-2.0, 0.0, -2.0], "DistributionVectorUniform")}, false),
		],
	}


func test_the_spawn_modules_rate_is_the_rate_and_amount_covers_the_longest_life() -> void:
	var params := MeParticles.describe(_lod(), 15.0)
	assert_false(params.has("unsupported"), "the smoke LOD was refused: %s" % params.get("unsupported"))
	# Required's SpawnRate (2) is the engine's older field and is not read.
	assert_eq(params.rate, 5.0)
	assert_eq(params.amount, 5, "5 a second for at most 1 s is 5 alive at once")
	assert_eq(params.life, [0.75, 1.0])


func test_the_starting_velocity_stays_a_box() -> void:
	var params := MeParticles.describe(_lod(), 0.0)
	assert_eq(params.velocity[0], Vector3(-0.1, 0.15, -0.02))
	assert_eq(params.velocity[1], Vector3(-0.05, 0.25, 0.02))
	var material := MeParticles.process_material(params)
	assert_eq(material.get_shader_parameter("velocity_min"), Vector3(-0.1, 0.15, -0.02))
	assert_eq(material.get_shader_parameter("velocity_max"), Vector3(-0.05, 0.25, 0.02))
	assert_almost_eq(float(material.get_shader_parameter("lifetime_min_ratio")), 0.75, 1e-6)


func test_rotation_is_in_turns_and_a_square_sprite_takes_size_x() -> void:
	var params := MeParticles.describe(_lod(), 0.0)
	assert_almost_eq(float(params.rotation[0]), -0.2 * TAU, 1e-6)
	assert_almost_eq(float(params.rotation[1]), 0.2 * TAU, 1e-6)
	assert_eq(params.size, [0.75, 1.0])
	assert_eq(params.size_curve.samples, [0.15, 2.0])


func test_a_disabled_module_is_not_read() -> void:
	var params := MeParticles.describe(_lod(), 0.0)
	assert_eq(params.location, [Vector3.ZERO, Vector3.ZERO], "the disabled Location module moved the spawn point")


func test_constants_go_to_scales_and_curves_to_textures() -> void:
	var params := MeParticles.describe(_lod(), 0.0)
	var material := MeParticles.process_material(params)
	assert_eq(material.get_shader_parameter("color_scale"), Vector3(1.357, 1.357, 1.357), "HDR colour was lost")
	assert_null(material.get_shader_parameter("color_curve"), "a constant colour made a curve")
	assert_true(material.get_shader_parameter("alpha_curve") is CurveTexture)
	assert_true(material.get_shader_parameter("accel_curve") is CurveXYZTexture)
	assert_eq(material.get_shader_parameter("accel_scale"), Vector3.ONE)
	assert_eq(material.get_shader_parameter("sub_image_scale"), 1.0)


func test_a_curve_keeps_values_outside_zero_to_one() -> void:
	# A Curve clamps every point into its value range; an acceleration of
	# -1.29 m/s^2 must survive it.
	var curve := MeParticles.curve_of([-1.29, 0.75, 13.1])
	assert_almost_eq(curve.sample(0.0), -1.29, 1e-4)
	assert_almost_eq(curve.sample(1.0), 13.1, 1e-4)
	assert_almost_eq(curve.sample(0.5), 0.75, 1e-4)


func test_the_material_graph_maps_onto_the_sprite_shader() -> void:
	var params := MeParticles.describe(_lod(), 0.0)
	var sprite := MeParticles.sprite_material(params.material, params, null)
	assert_eq(sprite.get_shader_parameter("emissive_mask"), Vector4(0.0, 1.0, 0.0, 0.0), "brightness is the sheet's G")
	assert_eq(sprite.get_shader_parameter("opacity_mask"), Vector4(0.0, 0.0, 0.0, 1.0), "opacity is the sheet's A")
	assert_true(sprite.get_shader_parameter("emissive_particle_color"))
	assert_true(sprite.get_shader_parameter("opacity_particle_alpha"))
	assert_eq(sprite.get_shader_parameter("sub_images"), Vector2(4.0, 4.0))
	assert_true(sprite.get_shader_parameter("blend_sub_images"), "PSUVIM_Linear_Blend blends two sub images")
	assert_almost_eq(float(sprite.get_shader_parameter("depth_fade_m")), 2.0, 1e-6)


func test_what_cannot_be_drawn_is_refused_with_a_reason() -> void:
	var lod := _lod()
	lod["modules"].append(_module("Orbit", {}))
	assert_eq(MeParticles.describe(lod, 0.0).get("unsupported"), "module Orbit")
	assert_eq(MeParticles.describe(_lod(7, 0.0), 0.0).get("unsupported"), "spawns nothing")
	var mesh := _lod()
	mesh["type_data"] = _module("TypeDataMesh", {})
	assert_true(str(MeParticles.describe(mesh, 0.0).get("unsupported")).begins_with("type data"))
	var lit := _lod()
	lit["material"] = _material()
	lit["material"]["supported"] = false
	assert_eq(MeParticles.describe(lit, 0.0).get("unsupported"), "material")


func test_each_lod_is_drawn_over_its_own_distance_band() -> void:
	var builder := MeParticles.new({"systems": {"PS_FX_LevelFX_Smoke_VentSmoke_01_Big": {
		"warmup": 15.0, "lod_distances_m": [0.0, 1.5, 7.5, 12.5],
		"emitters": [{"name": "SmokeMain_Dup", "class": "ParticleSpriteEmitter",
				"lods": [_lod(0), _lod(1), _lod(2, 3.0), _lod(3, 0.0)]}]}}, "textures": {}})
	builder.library_dir = LIBRARY
	var root := builder.build([
		{"name": "Emitter_5", "package": "Edge_Pt1.me1", "template": "PS_FX_LevelFX_Smoke_VentSmoke_01_Big",
				"position": [1.0, 2.0, 3.0], "basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "auto_activate": true},
		{"name": "Emitter_9", "package": "Edge_Pt1.me1", "template": "PS_FX_LevelFX_Sparks_SmallSparksDirected_01",
				"position": [0.0, 0.0, 0.0], "basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "auto_activate": true},
	])
	assert_not_null(root)
	autofree(root)
	assert_eq(root.get_child_count(), 1, "a family outside BUILT_FAMILIES was built")
	var holder: Node3D = root.get_child(0)
	assert_eq(holder.position, Vector3(1.0, 2.0, 3.0))
	assert_eq(holder.get_meta(&"me_package"), "edge_pt1", "PackagePresence cannot find the emitter")
	# LOD 3 spawns nothing and is not built: past 12.5 m the emitter draws
	# nothing, as the original's does.
	var nodes := holder.get_children()
	assert_eq(nodes.size(), 3)
	var bands := nodes.map(func(n: GPUParticles3D): return [n.visibility_range_begin, n.visibility_range_end])
	assert_eq(bands, [[0.0, 1.5], [1.5, 7.5], [7.5, 12.5]])
	var near: GPUParticles3D = nodes[0]
	assert_eq(near.amount, 5)
	assert_eq(near.lifetime, 1.0)
	assert_eq(near.preprocess, 1.0, "fifteen seconds of warmup is one lifetime of a repeating system")
	assert_false(near.local_coords)
	assert_true(near.visibility_aabb.has_point(Vector3.ZERO) and near.visibility_aabb.get_center().is_zero_approx(),
			"the LOD band is measured to the box's centre, so the box must be centred on the emitter")
	assert_eq(builder.counts.get("not built: PS_FX_LevelFX_Sparks_SmallSparksDirected_01"), 1)


func test_a_sprite_undoes_the_levels_exposure() -> void:
	# The tutorial is exposed at 0.85 / 2.5 for its sun; an unlit sprite never
	# sees that sun and is drawn at its own brightness.
	var builder := MeParticles.new({"systems": {"PS_FX_LevelFX_Smoke_VentSmoke_01_Big": {
		"warmup": 0.0, "lod_distances_m": [0.0],
		"emitters": [{"name": "SmokeMain_Dup", "class": "ParticleSpriteEmitter", "lods": [_lod(0)]}]}}, "textures": {}})
	builder.library_dir = LIBRARY
	builder.exposure = 0.34
	var root := builder.build([{"name": "Emitter_5", "package": "Tutorial_Art.me1",
			"template": "PS_FX_LevelFX_Smoke_VentSmoke_01_Big", "position": [0.0, 0.0, 0.0],
			"basis": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "auto_activate": true}])
	autofree(root)
	var sprite := (root.get_child(0).get_child(0) as GPUParticles3D).material_override as ShaderMaterial
	assert_almost_eq(float(sprite.get_shader_parameter("exposure_compensation")), 1.0 / 0.34, 0.001)

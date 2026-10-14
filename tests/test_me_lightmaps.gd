extends GutTest

# The original's baked lighting on an extracted level's static geometry
# (tools/me_level/me_lightmaps.gd, mesh_library.gd's lightmap_material()).
#
# The structural half needs no original data. The last two tests read the
# tutorial's generated geometry when this machine has it, and pass otherwise:
# they are about the FILE -- that what draws the level is in it, and that
# nothing in it is something only a running game would have made.

const MeLightmaps := preload("res://tools/me_level/me_lightmaps.gd")
const MeLibrary := preload("res://tools/me_level/mesh_library.gd")
const TUTORIAL_GEOMETRY := "res://scenes/local_debug_levels/mirrors_edge/sp00_tutorial_geometry.scn"


## Three vertices, three coefficients each, R G B: vertex v coefficient k is
## (10v + k, 100 + k, 200 + v).
func _samples() -> PackedByteArray:
	var out := PackedByteArray()
	for v in 3:
		for k in 3:
			out.append_array(PackedByteArray([10 * v + k, 100 + k, 200 + v]))
	return out


func test_vertex_samples_are_three_texels_a_vertex_in_order() -> void:
	var image := MeLightmaps.samples_image(_samples())
	assert_eq(image.get_width(), MeLightmaps.SAMPLES_WIDTH)
	for v in 3:
		for k in 3:
			var texel := image.get_pixel(v * MeLightmaps.TEXELS_PER_VERTEX + k, 0)
			assert_eq(roundi(texel.r * 255.0), 10 * v + k, "vertex %d coefficient %d red" % [v, k])
			assert_eq(roundi(texel.b * 255.0), 200 + v, "vertex %d coefficient %d blue" % [v, k])


func test_each_placement_starts_its_own_run_of_samples() -> void:
	var lightmaps := MeLightmaps.new("user://none", "user://test_me_lightmaps", MeLibrary.new())
	var samples := Marshalls.raw_to_base64(_samples())
	assert_true(lightmaps.prepare_vertex_samples([
		{package = "A.me1", name = "One", lightmap = {kind = "vertex", samples = samples}},
		{package = "A.me1", name = "Lit", lightmap = {kind = "texture"}},
		{package = "A.me1", name = "Two", lightmap = {kind = "vertex", samples = samples}}]))
	assert_eq(lightmaps._sample_offsets["a.One"], 0)
	assert_eq(lightmaps._sample_offsets["a.Two"], 3, "the second run starts after the first's three vertices")


func test_a_flat_surface_records_which_original_vertex_each_corner_is() -> void:
	var library := MeLibrary.new()
	var vertices := PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]).to_byte_array()
	var record := {name = "Flat", vertex_count = 3, vertices = Marshalls.raw_to_base64(vertices), normals = null,
			uvs = [], bounds = {origin = [0, 0, 0], extent = [1, 1, 1]}, simple_shapes = [],
			surfaces = [{material = null, blend = "opaque", unlit = false, collide = false, slot = 0,
					indices = Marshalls.raw_to_base64(PackedByteArray([2, 0, 0, 0, 1, 0]))}]}
	var mesh: ArrayMesh = library._build_mesh(record)
	var custom: PackedFloat32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	assert_eq([custom[0], custom[1], custom[2]], [3.0, 1.0, 2.0], "the corners are vertices 2, 0, 1, each plus one")


func test_a_lit_surface_gets_the_lightmap_shader_and_an_unlit_one_keeps_its_own() -> void:
	var library := MeLibrary.new()
	var atlas: Array = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	var lit: ShaderMaterial = library.lightmap_material({material = "M_None", blend = "masked"}, atlas)
	assert_not_null(lit)
	assert_eq(lit.shader, MeLibrary.LIGHTMAP_SHADERS["masked"])
	assert_eq(lit.get_shader_parameter("lightmap_2"), atlas[2])
	assert_ne(lit.get_shader_parameter("vertex_lightmap"), true, "a texture lightmap read as a vertex one")
	var vertex: ShaderMaterial = library.lightmap_material({material = "M_None", blend = "opaque"}, [atlas[0]], true)
	assert_true(vertex.get_shader_parameter("vertex_lightmap"))
	assert_eq(vertex.get_shader_parameter("vertex_samples"), atlas[0])
	assert_null(library.lightmap_material({material = "M_Sign", blend = "opaque", unlit = true}, atlas),
			"an unlit surface shows its own colour, not the bake")
	assert_null(library.lightmap_material({material = "M_Shaft", blend = "additive"}, atlas),
			"an additive surface is not drawn at all")


func test_where_a_placement_lies_in_its_atlas_is_on_its_instance() -> void:
	var instance := MeshInstance3D.new()
	MeLightmaps.set_parameters(instance, {kind = "texture", uv_scale = [0.25, 0.5], uv_bias = [0.125, 0.75],
			scales = [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]]})
	assert_eq(instance.get_instance_shader_parameter(&"lightmap_uv_scale_bias"), Vector4(0.25, 0.5, 0.125, 0.75))
	assert_eq(instance.get_instance_shader_parameter(&"lightmap_scale_2"), Vector3(7.0, 8.0, 9.0))
	instance.free()


func _lightmapped(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		for surface in instance.get_surface_override_material_count():
			var material := instance.get_surface_override_material(surface)
			if material == null and instance.mesh != null and surface < instance.mesh.get_surface_count():
				material = instance.mesh.surface_get_material(surface)
			if material is ShaderMaterial and (material as ShaderMaterial).shader in MeLibrary.LIGHTMAP_SHADERS.values():
				out.append(instance)
				break
	return out


func test_the_tutorials_static_geometry_draws_with_its_lightmaps_from_the_file() -> void:
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	var lit := _lightmapped(root)
	# The tutorial bakes some 2400 placements and part of its BSP.
	assert_gt(lit.size(), 2000, "the lightmapped materials are not in the scene file")
	var unplaced := 0
	for instance in lit:
		if instance.get_instance_shader_parameter(&"lightmap_scale_0") == null:
			unplaced += 1
	assert_eq(unplaced, 0, "lightmapped instances with no coefficient scale of their own")
	assert_eq(root.get_script(), load("res://tools/me_level/me_lightmapped.gd"),
			"the geometry root lost the script that sets the lightmap parameters again")
	root.free()


func test_every_texture_a_lightmapped_material_draws_is_a_file() -> void:
	# A texture made while building and left inside the material only exists
	# in that build's memory once the scene is exported from somewhere else.
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	var seen := {}
	var bad: Array[String] = []
	for instance in _lightmapped(root):
		for surface in (instance as MeshInstance3D).get_surface_override_material_count():
			var material := (instance as MeshInstance3D).get_surface_override_material(surface) as ShaderMaterial
			if material == null or seen.has(material):
				continue
			seen[material] = true
			for name in ["albedo_texture", "normal_texture", "emissive_texture", "lightmap_0", "lightmap_1", "lightmap_2"]:
				var texture: Variant = material.get_shader_parameter(name)
				if texture is Texture2D and not FileAccess.file_exists((texture as Texture2D).resource_path):
					bad.append("%s.%s" % [instance.name, name])
	assert_eq(bad, [] as Array[String], "textures with no file behind them")
	root.free()


const ShadowLight := preload("res://tools/me_level/me_shadow_light.gd")
const Common := preload("res://tools/me_level/me_level_common.gd")


## [ME:CONFIRMED DLE 0xff4517] the shadow light takes the shadow environment's
## dominant lobe; what is left of its ambient decides how dark the shadow is.
func test_a_lone_sun_casts_a_black_shadow_from_where_it_shines() -> void:
	var light := ShadowLight.new()
	var to_sun := Vector3(0.3, 0.8, -0.5).normalized()
	light.sun_directions = PackedVector3Array([to_sun])
	light.sun_intensities = PackedVector3Array([Vector3(2.5, 2.4, 2.2)])
	light.ambient_shadow_color = Vector3.ZERO
	var shadow: Dictionary = ShadowLight.representative_shadow(light.shadow_environment([true]))
	assert_almost_eq((shadow.direction as Vector3).dot(to_sun), 1.0, 1e-4, "the shadow falls away from the sun")
	assert_almost_eq((shadow.modulation as Vector3).length(), 0.0, 1e-4, "a lone sun leaves no ambient")
	shadow = ShadowLight.representative_shadow(light.shadow_environment([false]))
	assert_true(shadow.is_empty(), "nothing in the environment, no shadow")
	light.free()


## [ME:DERIVED] the formula on the tutorial's own lights (DirectionalLight_0,
## SkyLight_0, AmbientShadowColor), checked against a separate evaluation of
## the original's code: the sun's shadow and the one cast out of the sun.
func test_the_tutorials_lights_give_the_originals_shadow_colours() -> void:
	var light := ShadowLight.new()
	light.sun_directions = PackedVector3Array([Vector3(0.33513, 0.79861, -0.4999).normalized()])
	light.sun_intensities = PackedVector3Array([Vector3(1.95, 1.78571, 1.48063)])
	light.sky_upper = Vector3(0.1136, 0.13772, 0.21035)
	light.sky_lower = Vector3(0.12785, 0.08966, 0.04253)
	var lit: Dictionary = ShadowLight.representative_shadow(light.shadow_environment([true]))
	assert_almost_eq((lit.modulation as Vector3).x, 0.188, 0.002)
	assert_almost_eq((lit.modulation as Vector3).z, 0.213, 0.002)
	var shade: Dictionary = ShadowLight.representative_shadow(light.shadow_environment([false]))
	assert_almost_eq((shade.modulation as Vector3).x, 0.686, 0.002)
	assert_almost_eq((shade.modulation as Vector3).z, 0.600, 0.002)
	assert_almost_eq((shade.direction as Vector3).y, 1.0, 1e-4, "out of the sun the shadow falls straight down")
	light.free()


## The baked world is reached by the shadow light alone, and only a
## character casts into it: the bake holds the rest of the shadows.
func test_the_tutorials_baked_world_takes_only_the_shadow_light() -> void:
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	var lit := _lightmapped(root)
	var off_layer := lit.filter(func(i: GeometryInstance3D) -> bool: return i.layers != Common.BAKED_LAYER)
	assert_eq(off_layer.size(), 0, "lightmapped instances off the baked layer")
	var shadow_lights := root.find_children("ShadowLight", "DirectionalLight3D", true, false)
	assert_eq(shadow_lights.size(), 1)
	if shadow_lights.size() == 1:
		var light := shadow_lights[0] as DirectionalLight3D
		assert_lt(light.light_energy, 0.0, "the shader knows the shadow light by its negative energy")
		assert_eq(light.light_cull_mask, Common.BAKED_LAYER)
		assert_eq(light.shadow_caster_mask, Common.CHARACTER_SHADOW_LAYER)
	for node in root.find_children("*", "Light3D", true, false):
		if node.name != "ShadowLight":
			assert_eq((node as Light3D).light_cull_mask & Common.BAKED_LAYER, 0, "%s lights the bake" % node.name)
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		assert_eq((node as GeometryInstance3D).layers & Common.CHARACTER_SHADOW_LAYER, 0,
				"%s casts the character's shadow" % node.name)
	root.free()


## Runner Vision on a baked surface is painted by the lightmap shader itself.
## An overlay there is lit by nothing but the negative shadow light, and its
## instance uniforms take the lightmap's slots (me_lightmap.gdshaderinc).
func test_the_tutorials_runner_vision_paints_its_baked_surfaces_in_their_lightmap() -> void:
	var source := FileAccess.get_file_as_string("res://tools/me_level/me_lightmap.gdshaderinc")
	assert_true(source.contains("instance uniform float strength") and source.contains("instance uniform vec3 paint"),
			"the lightmap shader does not take the paint RunnerVisionTarget writes")
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	var lit := _lightmapped(root)
	var checked := 0
	var bad: Array[String] = []
	for node in root.find_children("*", "Node3D", true, false):
		if not node is RunnerVisionTarget:
			continue
		var target := node as RunnerVisionTarget
		target._collect()
		var placed := {}
		for mesh in target._painted:
			placed[mesh] = mesh.get_instance_shader_parameter(&"lightmap_uv_scale_bias")
		target._apply(1.0)
		for mesh in target._painted:
			if not lit.has(mesh):
				continue
			checked += 1
			if not target.paint_in_material or mesh.material_overlay != null:
				bad.append("%s: overlay" % mesh.get_parent().name)
			elif mesh.get_instance_shader_parameter(&"lightmap_uv_scale_bias") != placed[mesh]:
				bad.append("%s: lost its place in the atlas" % mesh.get_parent().name)
	# The tutorial tags 94 objects, most of them baked.
	assert_gt(checked, 50, "too few baked Runner Vision surfaces to say anything")
	assert_eq(bad, [] as Array[String], "baked Runner Vision surfaces painted by an overlay")
	root.free()


## [ME:CONFIRMED 0xff11e0] The sun trace is a shadow-casting trace: what the
## pawn collides with does not stop it, what casts a shadow does.
func test_the_sun_trace_reads_what_casts_shadows_not_what_collides() -> void:
	var light := ShadowLight.new()
	light.sun_directions = PackedVector3Array([Vector3.UP])
	light.sun_traced = [true] as Array[bool]
	add_child_autofree(light)
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.5, 4.0)
	shape.shape = box
	roof.add_child(shape)
	roof.collision_layer = 1
	add_child_autofree(roof)
	roof.global_position = Vector3(0.0, 5.0, 0.0)
	await wait_physics_frames(2)
	assert_eq(light._sun_visibility(Vector3.ZERO), [true], "movement collision kept the sun out")
	roof.collision_layer = Common.SUN_OCCLUDER_LAYER
	await wait_physics_frames(2)
	assert_eq(light._sun_visibility(Vector3.ZERO), [false], "a shadow caster let the sun through")


## Out of the sun, the shadow is cast from the ambient term's own direction:
## against a wall, toward the wall rather than down.
func test_out_of_the_sun_the_shadow_follows_the_ambient_source() -> void:
	var light := ShadowLight.new()
	light.sun_directions = PackedVector3Array([Vector3(0.3, 0.8, -0.5).normalized()])
	light.sun_intensities = PackedVector3Array([Vector3(1.95, 1.79, 1.48)])
	var out_of_wall := (Vector3.BACK + Vector3.UP * 0.1).normalized()
	var shade: Dictionary = ShadowLight.representative_shadow(light.shadow_environment([false], out_of_wall))
	assert_almost_eq((shade.direction as Vector3).dot(out_of_wall), 1.0, 1e-4)
	light.free()


## Every drawn shadow caster with colliding triangles keeps the sun off the
## player, whatever it collides with; designer collision with no picture and
## the level's volumes do not.
func test_the_tutorials_sun_occluders_are_its_shadow_casters() -> void:
	if not ResourceLoader.exists(TUTORIAL_GEOMETRY):
		pass_test("no tutorial geometry on this machine")
		return
	var root: Node = (load(TUTORIAL_GEOMETRY) as PackedScene).instantiate()
	var missing: Array[String] = []
	var checked := 0
	for node in root.find_children("Mesh", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var placement := mesh_instance.get_parent()
		if not placement.has_meta("me_collision") or placement is RigidBody3D or mesh_instance is SoftBody3D:
			continue
		if not mesh_instance.visible or not (mesh_instance.mesh as ArrayMesh).has_meta("per_poly_shape"):
			continue
		checked += 1
		if not _occludes(placement):
			missing.append(String(placement.name))
	assert_gt(checked, 0, "test setup: no shadow casters found")
	assert_eq(missing, [] as Array[String], "shadow casters the sun goes through")
	for node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body.collision_layer & Common.SUN_OCCLUDER_LAYER == 0 or body.name.begins_with("BSP"):
			continue
		var placement: Node = body.get_parent() if body.name == "SunOccluder" else body
		var picture := placement.get_node_or_null("Mesh") as MeshInstance3D
		assert_true(picture != null and picture.visible, "%s keeps the sun out with nothing drawn" % placement.name)
	root.free()


func _occludes(placement: Node) -> bool:
	if placement is CollisionObject3D and (placement as CollisionObject3D).collision_layer & Common.SUN_OCCLUDER_LAYER:
		return true
	var occluder := placement.get_node_or_null("SunOccluder") as CollisionObject3D
	return occluder != null and occluder.collision_layer & Common.SUN_OCCLUDER_LAYER != 0

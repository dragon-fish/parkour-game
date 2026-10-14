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

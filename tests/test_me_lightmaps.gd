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


func _triangle(flat := false) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("surface_slots", PackedInt32Array([0]))
	mesh.set_meta("surface_materials", [{material = "M_Test", blend = "opaque", unlit = false}])
	# A flat surface's vertices are the original's in index order.
	mesh.set_meta("flat_sources", [PackedInt32Array([2, 0, 1]) if flat else PackedInt32Array()])
	return mesh


## Three vertices, three coefficients each, R G B: vertex v coefficient k is
## (10v + k, 100 + k, 200 + v).
func _samples() -> PackedByteArray:
	var out := PackedByteArray()
	for v in 3:
		for k in 3:
			out.append_array(PackedByteArray([10 * v + k, 100 + k, 200 + v]))
	return out


func test_a_vertex_lightmap_rides_on_the_mesh_one_coefficient_a_channel() -> void:
	var copy := MeLightmaps.with_samples(_triangle(), _samples())
	var arrays := copy.surface_get_arrays(0)
	for k in 3:
		var channel: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0 + k]
		assert_eq(channel.size(), 12, "CUSTOM%d holds four bytes a vertex" % k)
		for v in 3:
			assert_eq(channel[v * 4], 10 * v + k, "vertex %d coefficient %d red" % [v, k])
			assert_eq(channel[v * 4 + 2], 200 + v, "vertex %d coefficient %d blue" % [v, k])
	assert_eq(copy.get_meta("surface_slots"), PackedInt32Array([0]), "the copy lost what overrides index by")


func test_a_flat_surface_takes_each_vertex_from_the_original_it_came_from() -> void:
	var copy := MeLightmaps.with_samples(_triangle(true), _samples())
	var red: PackedByteArray = copy.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	assert_eq([red[0], red[4], red[8]], [20, 0, 10], "flat vertices read the wrong original vertex")


func test_a_lit_surface_gets_the_lightmap_shader_and_an_unlit_one_keeps_its_own() -> void:
	var library := MeLibrary.new()
	var atlas: Array = [ImageTexture.new(), ImageTexture.new(), ImageTexture.new()]
	var lit: ShaderMaterial = library.lightmap_material({material = "M_None", blend = "masked"}, atlas)
	assert_not_null(lit)
	assert_eq(lit.shader, MeLibrary.LIGHTMAP_SHADERS["masked"])
	assert_eq(lit.get_shader_parameter("lightmap_2"), atlas[2])
	assert_ne(lit.get_shader_parameter("vertex_lightmap"), true, "a texture lightmap read as a vertex one")
	var vertex: ShaderMaterial = library.lightmap_material({material = "M_None", blend = "opaque"}, [])
	assert_true(vertex.get_shader_parameter("vertex_lightmap"))
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

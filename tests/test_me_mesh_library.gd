extends GutTest

# What the extracted levels' mesh library draws of a surface
# (tools/me_level/mesh_library.gd). The last test reads the library when this
# machine has the tutorial's, and passes otherwise.

const MeLibrary := preload("res://tools/me_level/mesh_library.gd")
const LIGHT_BLOCK_MESH := "PX_SlideUnder_01"


func _triangle_record(surfaces: Array) -> Dictionary:
	var vertices := PackedFloat32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]).to_byte_array()
	var normals := PackedFloat32Array([0, 0, 1, 0, 0, 1, 0, 0, 1]).to_byte_array()
	return {name = "Tri", vertex_count = 3, vertices = Marshalls.raw_to_base64(vertices),
			normals = Marshalls.raw_to_base64(normals), uvs = [],
			bounds = {origin = [0, 0, 0], extent = [1, 1, 1]}, simple_shapes = [], surfaces = surfaces}


func _surface(slot: int, extra := {}) -> Dictionary:
	var surface := {material = null, blend = "translucent", unlit = true, collide = true, slot = slot,
			indices = Marshalls.raw_to_base64(PackedByteArray([0, 0, 1, 0, 2, 0]))}
	surface.merge(extra, true)
	return surface


func test_a_surface_that_covers_nothing_collides_and_is_not_drawn() -> void:
	var library := MeLibrary.new()
	var mesh: ArrayMesh = library._build_mesh(_triangle_record([
			_surface(0, {invisible = true}), _surface(1)]))
	assert_eq(mesh.get_surface_count(), 1, "only the surface that covers something is drawn")
	assert_eq(mesh.get_meta("surface_slots"), PackedInt32Array([1]),
			"the drawn surface keeps its own slot, not the hidden one's")
	var faces: PackedVector3Array = (mesh.get_meta("per_poly_shape") as ConcavePolygonShape3D).get_faces()
	assert_eq(faces.size(), 6, "the hidden surface's triangle still collides")


func test_the_tutorials_light_block_boxes_draw_nothing() -> void:
	var path := MeLibrary.path_for(LIGHT_BLOCK_MESH)
	if not ResourceLoader.exists(path):
		pass_test("no tutorial mesh library on this machine")
		return
	var mesh: ArrayMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(mesh.get_surface_count(), 0,
			"%s's BlankBsp has a constant 0 opacity and draws nothing in the original" % LIGHT_BLOCK_MESH)

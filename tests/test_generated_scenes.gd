class_name TestGeneratedScenes
extends TestCase

# GENERATOR-DRIFT GUARD.
#
# scenes/main.tscn and scenes/player/player.tscn are both GENERATED -- by
# ArenaBuilder (tools/arena_builder.gd, saved by tools/build_main_scene.gd) and
# PlayerBuilder (tools/player_builder.gd, saved by tools/build_player_scene.gd)
# respectively. Nothing stops a change to a builder, or to a config value a
# builder reads, from landing WITHOUT the corresponding regeneration. When that
# happens the committed scene silently stops being what the code says it is,
# and every playtest from then on runs geometry nobody chose. It has already
# happened once in this project: main.tscn sat at a 0.7 m corridor half-width
# while its generator said 0.45.
#
# WHY IN MEMORY, NOT VIA THE GENERATOR SCRIPTS.
# The obvious guard -- re-run the generator and diff the file -- is
# SELF-DEFEATING: re-running it WRITES the tracked .tscn, so the drift is
# repaired as a side effect of measuring it and the test passes forever after
# announcing nothing. This compares the builder's in-memory tree against the
# tree ResourceLoader hands back from the committed file instead. Nothing is
# written anywhere, tracked or otherwise, so the guard cannot launder the very
# problem it exists to report.
#
# WHAT IS COMPARED. A canonical signature per node, in tree order: its path,
# its class, its transform, and the handful of resource properties the two
# builders actually vary (box/capsule sizes, ray geometry, albedo colour).
# Structure and names are compared exactly; numbers with a tolerance, since
# these have been through a float -> text -> float round trip in the .tscn.
# The drift this exists to catch is metres wide, not 1e-6 wide.

const TOLERANCE := 0.0005

func test_the_committed_arena_matches_what_its_generator_produces() -> void:
	var fresh: Node = ArenaBuilder.new().build()
	var committed: Node = load("res://scenes/main.tscn").instantiate()
	_compare(fresh, committed, "scenes/main.tscn", "tools/build_main_scene.gd")
	fresh.free()
	committed.free()

func test_the_committed_player_matches_what_its_generator_produces() -> void:
	var fresh: Node = PlayerBuilder.new().build()
	var committed: Node = load("res://scenes/player/player.tscn").instantiate()
	_compare(fresh, committed, "scenes/player/player.tscn", "tools/build_player_scene.gd")
	fresh.free()
	committed.free()

## Walks both trees in the same order and compares signatures pairwise. Reports
## the FIRST divergence with both sides spelled out, plus the command to run --
## a bare "the scene is stale" tells whoever hits this nothing about what moved.
func _compare(fresh: Node, committed: Node, scene_path: String, generator: String) -> void:
	var a: PackedStringArray = _signatures(fresh, fresh)
	var b: PackedStringArray = _signatures(committed, committed)
	var fix := "%s is stale -- re-run:  .engine\\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://%s" \
		% [scene_path, generator]

	if a.size() != b.size():
		check(false, "%s  (generator produces %d nodes, the committed scene has %d)" \
			% [fix, a.size(), b.size()])
		return

	var limit: int = a.size()
	for i in limit:
		if a[i] != b[i]:
			check(false, "%s\n    generator: %s\n    committed: %s" % [fix, a[i], b[i]])
			return
	check(true, "%s matches %s" % [scene_path, generator])

func _signatures(node: Node, root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(_signature(node, root))
	for child in node.get_children():
		out.append_array(_signatures(child, root))
	return out

func _signature(node: Node, root: Node) -> String:
	var parts := PackedStringArray()
	parts.append(String(root.get_path_to(node)))
	parts.append(node.get_class())
	if node is Node3D:
		var t: Transform3D = (node as Node3D).transform
		parts.append("origin=%s" % _v(t.origin))
		parts.append("basis=%s|%s|%s" % [_v(t.basis.x), _v(t.basis.y), _v(t.basis.z)])
	if node is MeshInstance3D:
		parts.append(_mesh((node as MeshInstance3D).mesh))
		parts.append(_material((node as MeshInstance3D).get_active_material(0)))
	if node is CollisionShape3D:
		parts.append(_shape((node as CollisionShape3D).shape))
	if node is ShapeCast3D:
		parts.append(_shape((node as ShapeCast3D).shape))
		parts.append("target=%s" % _v((node as ShapeCast3D).target_position))
	if node is RayCast3D:
		var ray := node as RayCast3D
		parts.append("target=%s" % _v(ray.target_position))
		parts.append("enabled=%s hit_from_inside=%s" % [ray.enabled, ray.hit_from_inside])
	return "  ".join(parts)

func _mesh(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		return "BoxMesh%s" % _v((mesh as BoxMesh).size)
	if mesh == null:
		return "mesh=none"
	return "mesh=%s" % mesh.get_class()

func _shape(shape: Shape3D) -> String:
	if shape is BoxShape3D:
		return "BoxShape%s" % _v((shape as BoxShape3D).size)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return "CapsuleShape(h=%s r=%s)" % [_f(capsule.height), _f(capsule.radius)]
	if shape == null:
		return "shape=none"
	return "shape=%s" % shape.get_class()

func _material(material: Material) -> String:
	if material is StandardMaterial3D:
		var c: Color = (material as StandardMaterial3D).albedo_color
		return "albedo(%s,%s,%s,%s)" % [_f(c.r), _f(c.g), _f(c.b), _f(c.a)]
	if material == null:
		return "material=none"
	return "material=%s" % material.get_class()

## Rounds to TOLERANCE's own granularity before printing, so the comparison is
## a plain string equality that still behaves like an approximate one. Also
## normalises -0.0 to 0.0, which the .tscn round trip can introduce on its own.
func _f(value: float) -> String:
	var quantised: float = roundf(value / TOLERANCE) * TOLERANCE
	if quantised == 0.0:
		quantised = 0.0
	return "%.4f" % quantised

func _v(value: Vector3) -> String:
	return "(%s,%s,%s)" % [_f(value.x), _f(value.y), _f(value.z)]

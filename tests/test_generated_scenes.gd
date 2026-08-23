extends ParkourTest

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
# its class, its attached script, its transform, and the handful of resource
# properties the two builders actually vary (box/capsule sizes, ray and cast
# geometry, their enabled flags, albedo colour). Structure, names and script
# paths are compared exactly; numbers with a tolerance, since these have been
# through a float -> text -> float round trip in the .tscn. The drift this
# exists to catch is metres wide, not 1e-6 wide.
#
# The set is SCOPED, not exhaustive -- it covers what these two builders
# actually set. A builder that starts setting some other property (a light's
# energy, a camera's fov, a physics layer mask) needs a line here too, or that
# property drifts unwatched.

const TOLERANCE := 0.0005

func test_the_committed_arena_matches_what_its_generator_produces() -> void:
	var fresh: Node = ArenaBuilder.new().build()
	var committed: Node = load("res://scenes/main.tscn").instantiate()
	_compare_against_generator(fresh, committed, "scenes/main.tscn", "tools/build_main_scene.gd")
	fresh.free()
	committed.free()

func test_the_committed_player_matches_what_its_generator_produces() -> void:
	var fresh: Node = PlayerBuilder.new().build()
	var committed: Node = load("res://scenes/player/player.tscn").instantiate()
	_compare_against_generator(fresh, committed, "scenes/player/player.tscn", "tools/build_player_scene.gd")
	fresh.free()
	committed.free()

## Walks both trees in the same order and compares signatures pairwise. Reports
## the FIRST divergence with both sides spelled out, plus the command to run --
## a bare "the scene is stale" tells whoever hits this nothing about what moved.
## Renamed off `_compare`: GutTest declares a member by that name, and the
## collision is a parse error rather than an override.
func _compare_against_generator(fresh: Node, committed: Node, scene_path: String, generator: String) -> void:
	var a: PackedStringArray = _signatures(fresh, fresh)
	var b: PackedStringArray = _signatures(committed, committed)
	var fix := "%s is stale -- re-run:  .engine\\Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://%s" \
		% [scene_path, generator]

	if a.size() != b.size():
		assert_true(false, "%s  (generator produces %d nodes, the committed scene has %d)" \
			% [fix, a.size(), b.size()])
		return

	var limit: int = a.size()
	for i in limit:
		if a[i] != b[i]:
			assert_true(false, "%s\n    generator: %s\n    committed: %s" % [fix, a[i], b[i]])
			return
	assert_true(true, "%s matches %s" % [scene_path, generator])

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
	# get_class() reports the NATIVE class and never the attached GDScript, so
	# without this a builder that stopped calling set_script() -- or attached
	# the wrong one -- would be invisible here. PlayerBuilder sets scripts on
	# four nodes (CameraRig, BodyRoot, Probes, Player itself) and ArenaBuilder
	# on three more; every one of them is the difference between a live node
	# and an inert one. Compared by resource_path rather than by object
	# identity: the two trees load their own GDScript instances.
	var script: Variant = node.get_script()
	parts.append("script=%s" % (script.resource_path if script != null else "none"))
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
		var cast := node as ShapeCast3D
		parts.append(_shape(cast.shape))
		parts.append("target=%s" % _v(cast.target_position))
		# `enabled` matters here for the same reason it does on RayCast3D below:
		# StandClearance is the probe Player.has_headroom() reads, and a
		# disabled one reports no collisions at all -- i.e. "there is always
		# room to stand up", silently, inside a ceiling.
		parts.append("enabled=%s" % cast.enabled)
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

# --- the calibration course is opt-in ------------------------------------------

func test_the_template_does_not_carry_the_calibration_course() -> void:
	# ✅ THE OWNER: "能不能别让 calibration_course 出现在每一个场景里."
	#
	# scripts/level/arena.gd is the script on templates/base_level.tscn as well
	# as on main.tscn, so a course loaded unconditionally turned up in every
	# whitebox built from that template -- 60 m of graded obstacles nobody asked
	# for, in scenes that exist to isolate one piece of geometry.
	var template := load("res://templates/base_level.tscn") as PackedScene
	assert_not_null(template, "the level template is missing")
	var level := template.instantiate()
	assert_false(bool(level.get("load_calibration_course")),
		"a level built from the template still loads the calibration course")
	level.free()

func test_the_generated_arena_does_carry_it() -> void:
	# The pair: a bench of graded obstacles belongs SOMEWHERE, and the arena is
	# where. Without this, the test above passes on a build that has quietly
	# deleted the course from everywhere at once.
	var main := load("res://scenes/main.tscn") as PackedScene
	assert_not_null(main, "scenes/main.tscn is missing")
	var arena := main.instantiate()
	assert_true(bool(arena.get("load_calibration_course")),
		"the arena stopped loading the calibration course")
	arena.free()

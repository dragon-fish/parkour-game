extends SceneTree

# Structural checks for a built Mirror's Edge level. Counts and invariants
# only; how the level looks or plays is judged by a person.
#
#   <engine> --headless --path . --script res://tools/me_level/verify_level.gd -- <config.json>

const Common := preload("res://tools/me_level/me_level_common.gd")
const MeLibrary := preload("res://tools/me_level/mesh_library.gd")

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var config: Dictionary = Common.read_json(args[0])
	var manifest: Dictionary = Common.read_json(
			Common.project_path(Common.EXTRACT_DIR).path_join(config["id"]).path_join("manifest.json"))
	var paths := Common.output_paths(config)

	for mesh_name in _unique(manifest["placements"].map(func(p): return p["mesh"])):
		check(ResourceLoader.exists(MeLibrary.path_for(mesh_name)), "library lacks " + mesh_name)

	var shell: Node = (load(paths.shell) as PackedScene).instantiate()
	root.add_child(shell)
	var geometry: Node = null
	for child in shell.get_children():
		if child.scene_file_path == paths.geometry:
			geometry = child
	check(geometry != null, "shell does not instance " + paths.geometry)
	if geometry == null:
		_finish(shell)
		return

	var placed: Array = geometry.get_node("Geometry").get_children()
	check(placed.size() == manifest["placements"].size(),
			"%d placement nodes, manifest has %d" % [placed.size(), manifest["placements"].size()])
	for node: Node in placed:
		var shapes := node.find_children("*", "CollisionShape3D", false, false)
		var collision: String = node.get_meta("me_collision", "")
		if collision == "none":
			check(shapes.is_empty() and not node is CollisionObject3D, "non-colliding placement collides: " + node.name)
		else:
			check(node is StaticBody3D and not shapes.is_empty(), "%s placement lacks collision: %s" % [collision, node.name])

	_check_count(shell, "InterestLines", manifest, ["zipline", "swing", "balance", "ladder", "ledgewalk"])
	_check_count(shell, "AirWalls", manifest, ["blocking"])
	_check_count(shell, "DeathVolumes", manifest, ["kill"])
	_check_count(shell, "BarbedWire", manifest, ["barbedwire"])
	if shell.has_node("BarbedWire"):
		for wire in shell.get_node("BarbedWire").get_children():
			var hazard := wire.get_node_or_null("Hazard")
			check(hazard is ModifierVolume and not hazard.apply.is_empty()
					and not hazard.find_children("*", "CollisionShape3D", false, false).is_empty(),
					"barbed wire does not hurt: " + wire.name)

	# Saved names only: scripts add runtime children (a line's rope, the HUD)
	# that Godot names itself and that are never written to a file.
	for path in [paths.shell, paths.geometry]:
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_count():
			check(not str(state.get_node_name(i)).contains("@"),
					"illegal node name in %s: %s" % [path, state.get_node_path(i)])

	for i in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = shell.get_world_3d().direct_space_state
	var starts: Array[Node3D] = [shell.get_node("SpawnPoint")]
	if shell.has_node("Checkpoints"):
		for checkpoint in shell.get_node("Checkpoints").get_children():
			starts.append(checkpoint)
	for start in starts:
		var from := start.global_position + Vector3.UP * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0))
		check(not hit.is_empty(), "no floor under " + str(shell.get_path_to(start)))
	_finish(shell)


func _check_count(shell: Node, group: String, manifest: Dictionary, kinds: Array) -> void:
	var expected: int = manifest["annotations"].filter(func(a): return a["kind"] in kinds).size()
	var actual := shell.get_node(group).get_child_count() if shell.has_node(group) else 0
	check(actual == expected, "%s has %d nodes, manifest has %d" % [group, actual, expected])


func _finish(shell: Node) -> void:
	shell.free()
	print("Level structural checks: %d failures" % failures)
	quit(0 if failures == 0 else 1)


static func _unique(values: Array) -> Array:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen.keys()

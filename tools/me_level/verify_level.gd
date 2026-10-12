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
	# The same test the builder makes: a chapter whose Kismet is exported and
	# RUN, rather than walked for single facts.
	var scripted: bool = manifest.get("streaming") is Dictionary

	for mesh_name in _unique(manifest["placements"].map(func(p): return p["mesh"])):
		check(ResourceLoader.exists(MeLibrary.path_for(mesh_name)), "library lacks " + mesh_name)

	var shell: Node = (load(paths.shell) as PackedScene).instantiate()
	# Taken out before the level enters the tree: everything below looks at the
	# WHOLE chapter, and left in it would hide all but the first stretch.
	var streaming := shell.find_child("Streaming", true, false)
	if streaming != null:
		streaming.get_parent().remove_child(streaming)
	root.add_child(shell)
	var geometry: Node = null
	for child in shell.get_children():
		if child.scene_file_path == paths.geometry:
			geometry = child
	check(geometry != null, "shell does not instance " + paths.geometry)
	if geometry == null:
		_finish(shell)
		return

	var parts: Array[Node] = [shell]
	var geometries: Array[Node] = [geometry]
	var scene_paths: Array = [paths.shell, paths.geometry]
	if config.get("split_sections", false):
		var loader := shell.get_node_or_null("Sections")
		check(loader != null, "split chapter lacks Sections")
		if loader == null:
			_finish(shell)
			return
		check(loader.get_child_count() == config["sections"].size(), "section count differs from config")
		for entry: Dictionary in config["sections"]:
			var section := loader.get_node_or_null(NodePath(entry["name"]))
			check(section != null, "missing section " + str(entry["name"]))
			if section == null:
				continue
			var section_geometry := section.get_node_or_null("Geometry")
			check(section_geometry != null, "section lacks geometry: " + str(section.name))
			if section_geometry == null:
				continue
			parts.append(section)
			geometries.append(section_geometry)
			scene_paths.append(section.scene_file_path)
			scene_paths.append(section_geometry.scene_file_path)

	var placed: Array = []
	# Movers are placements too, grouped apart: always bodies, collision or not.
	var movers := 0
	for part_geometry in geometries:
		placed.append_array(part_geometry.get_node("Geometry").get_children())
		if part_geometry.has_node("Movers"):
			movers += part_geometry.get_node("Movers").get_child_count()
	check(placed.size() + movers == manifest["placements"].size(),
			"%d placement nodes and %d movers, manifest has %d"
			% [placed.size(), movers, manifest["placements"].size()])
	for node: Node in placed:
		var shapes := node.find_children("*", "CollisionShape3D", false, false)
		var collision: String = node.get_meta("me_collision", "")
		if collision == "none":
			check(shapes.is_empty() and not node is CollisionObject3D, "non-colliding placement collides: " + node.name)
		else:
			check(node is StaticBody3D and not shapes.is_empty(), "%s placement lacks collision: %s" % [collision, node.name])

	_check_count(parts, "InterestLines", manifest, ["zipline", "swing", "balance", "ladder", "ledgewalk"])
	_check_count(parts, "AirWalls", manifest, ["blocking"])
	_check_deaths(parts, manifest)
	_check_count(parts, "Headlights", manifest, ["flare"])
	_check_riders_ride(parts, manifest)
	_check_count(parts, "BarbedWire", manifest, ["barbedwire"])
	_check_count(parts, "PainVolumes", manifest, ["pain"])
	_check_count(parts, "Glass", manifest, ["glass"])
	_check_fall_heights(geometries, manifest, scripted)
	# A scripted chapter ends by REACHING SeqAct_TdLevelCompleted, so it has no
	# LevelEnds group at all -- what must exist is the node itself.
	if scripted:
		check(_kismet_has(streaming, "SeqAct_TdLevelCompleted"),
				"a scripted chapter with no SeqAct_TdLevelCompleted can never be finished")
		for part in parts:
			check(not part.has_node("LevelEnds") or part.get_node("LevelEnds").get_child_count() == 0,
					"scripted chapter still builds a touch that ends it: " + part.name)
	else:
		_check_count(parts, "LevelEnds", manifest, ["level_end"])
	# A script that fails to compile under the builder (no autoloads there) is
	# saved as NO script: the node is inert and every count above still holds.
	for part in parts:
		for group in ["Glass", "LevelEnds"]:
			if part.has_node(group):
				for node in part.get_node(group).get_children():
					check(node.get_script() != null, "%s/%s/%s has no script" % [part.name, group, node.name])
	for part in parts:
		if part.has_node("InterestLines"):
			for line in part.get_node("InterestLines").get_children():
				check(line.curve != null and line.curve.get_baked_length() > 0.001,
						"zero-length interaction line: %s/%s" % [part.name, line.name])
		if part.has_node("BarbedWire"):
			for wire in part.get_node("BarbedWire").get_children():
				var hazard := wire.get_node_or_null("Hazard")
				check(hazard is ModifierVolume and not hazard.apply.is_empty()
						and not hazard.find_children("*", "CollisionShape3D", false, false).is_empty(),
						"barbed wire does not hurt: " + wire.name)
		if part.has_node("Matinees"):
			for sequence in part.get_node("Matinees").get_children():
				for track: Dictionary in sequence.tracks:
					for target: NodePath in track["targets"]:
						check(sequence.get_node_or_null(target) != null,
								"missing mover target: %s -> %s" % [sequence.name, target])

	# Saved names only: scripts add runtime children (a line's rope, the HUD)
	# that Godot names itself and that are never written to a file.
	for path in scene_paths:
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_count():
			check(not str(state.get_node_name(i)).contains("@"),
					"illegal node name in %s: %s" % [path, state.get_node_path(i)])

	for i in 3:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = shell.get_world_3d().direct_space_state
	# A checkpoint stands in the shell of the section whose floor it is on.
	var starts: Array[Node3D] = [shell.get_node("SpawnPoint")]
	for part in parts:
		if part.has_node("Checkpoints"):
			for checkpoint in part.get_node("Checkpoints").get_children():
				starts.append(checkpoint)
	# Some the original drops the player from on purpose: Edge's "Cops" falls
	# into the police's arms.
	var floating: Array = config.get("floating_checkpoints", [])
	for start in starts:
		if String(start.name) in floating:
			continue
		var from := start.global_position + Vector3.UP * 0.5
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0))
		check(not hit.is_empty(), "no floor under " + str(shell.get_path_to(start)))
		if streaming != null and not hit.is_empty():
			_check_floor_is_loaded(streaming, start, from, space)
	if streaming != null:
		_check_streaming(streaming, parts, geometries)
		streaming.free()
	_check_spawn_has_a_way_out(shell, space, scripted)
	_finish(shell)


## A restore loads the checkpoint's snapshot and sets the body down: the floor
## it is set on has to be in that snapshot.
func _check_floor_is_loaded(streaming: Node, start: Node, from: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	var label: String = start.get("display_name") if start.get("display_name") else String(start.name)
	var snapshots: Dictionary = streaming.get("snapshots")
	if not snapshots.has(label):
		return
	var loaded: PackedStringArray = snapshots[label]
	var managed: PackedStringArray = streaming.get("managed")
	# The whole chapter is in the tree here, so the first thing under the point
	# may belong to a stretch that is never loaded with it: look past those.
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
	var skipped: Array[String] = []
	for attempt in 16:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var node := hit["collider"] as Node
		while node != null and not node.has_meta(Common.PACKAGE_META):
			node = node.get_parent()
		var key: String = node.get_meta(Common.PACKAGE_META) if node != null else ""
		if key == "" or not managed.has(key) or loaded.has(key):
			return
		skipped.append(key)
		query.exclude = query.exclude + [hit["rid"]]
	check(false, "checkpoint %s: nothing its snapshot loads is under it (only %s)" % [label, skipped])


## What cannot fail a build but says where to look when a stretch is wrong.
## NOTES, not checks: the original's data decides these, and some of it is
## simply so (a package the chapter streams and this project never builds).
func _check_streaming(streaming: Node, parts: Array[Node], geometries: Array[Node]) -> void:
	var built := {}
	var todo: Array[Node] = []
	todo.append_array(parts)
	todo.append_array(geometries)
	while not todo.is_empty():
		var node: Node = todo.pop_back()
		if node.has_meta(Common.PACKAGE_META):
			built[node.get_meta(Common.PACKAGE_META)] = true
			continue
		todo.append_array(node.get_children())
	var unbuilt: Array = []
	for key: String in streaming.get("managed"):
		if not built.has(key):
			unbuilt.append(key)
	if not unbuilt.is_empty():
		print("[verify] note: streamed but nothing of them is built: ", unbuilt)


## The original starts several chapters in a box it leaves by cutscene -- a
## truck cab, a lift, a room with no door. In a SCRIPTED chapter that is where
## the chapter is meant to begin: the cutscene carries the body out, so being
## walled in is a note, not a failure. Elsewhere there is nothing to carry it
## and the chapter must name a playable start (config initial_spawn).
const SPAWN_CLEARANCE_M := 4.0

## Whether the chapter's graph holds a node of this class at all. Read off the
## runner's own resource, so it is the graph the level will actually run.
func _kismet_has(streaming: Node, cls: String) -> bool:
	var runner: Node = streaming.get_node_or_null("Kismet") if streaming != null else null
	if runner == null:
		return false
	var graph: Resource = runner.get("graph")
	if graph == null:
		return false
	var nodes: Dictionary = graph.get("nodes")
	for id: String in nodes:
		if str((nodes[id] as Dictionary).get("cls", "")) == cls:
			return true
	return false


func _check_spawn_has_a_way_out(shell: Node, space: PhysicsDirectSpaceState3D, scripted: bool) -> void:
	var spawn := shell.get_node_or_null("SpawnPoint") as Node3D
	if spawn == null:
		return
	var from := spawn.global_position + Vector3.UP * 0.5
	var farthest := 0.0
	for i in 16:
		var angle := TAU * i / 16.0
		var to := from + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_CLEARANCE_M
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		farthest = maxf(farthest, from.distance_to(hit["position"]) if hit else SPAWN_CLEARANCE_M)
	if farthest >= SPAWN_CLEARANCE_M:
		return
	if scripted:
		print("[verify] note: the spawn is walled in within %.1f m -- the chapter's own cutscene has to carry the body out" % SPAWN_CLEARANCE_M)
	else:
		check(false, "spawn is walled in on every side within %.1f m: name the chapter's playable start in initial_spawn" % SPAWN_CLEARANCE_M)


## Lethal volumes are the level's own kill volumes PLUS every volume riding a
## mover whose touch reaches the original's player-fail: a train has no lethal
## collision of its own, only a box that travels with it.
func _check_deaths(parts: Array[Node], manifest: Dictionary) -> void:
	var expected := 0
	for a: Dictionary in manifest["annotations"]:
		var effects: Variant = a.get("effects")
		if a["kind"] == "kill" or (effects is Dictionary and effects.get("kill", false)):
			expected += 1
	var actual := 0
	for part in parts:
		if part.has_node("DeathVolumes"):
			actual += part.get_node("DeathVolumes").get_child_count()
	check(actual == expected, "DeathVolumes has %d nodes, manifest has %d" % [actual, expected])


## THE GATE THIS WHOLE FEATURE EXISTS BEHIND. A volume the original bolted to a
## moving actor is lethal, or heard, only where that actor is. Built but never
## handed to the Matinee that drives it, it becomes a kill box standing still
## on an empty track -- which is not a missing feature but a new hazard in a
## place the original has none, and it looks entirely correct in the editor.
func _check_riders_ride(parts: Array[Node], manifest: Dictionary) -> void:
	var ridden := {}
	for a: Dictionary in manifest["annotations"]:
		if a.get("base") != null:
			ridden[str(a["name"])] = true
	if ridden.is_empty():
		return
	var carried := {}
	for part in parts:
		if not part.has_node("Matinees"):
			continue
		for matinee in part.get_node("Matinees").get_children():
			for track: Dictionary in matinee.get("tracks"):
				for path: NodePath in track["targets"]:
					var target := matinee.get_node_or_null(path)
					if target != null:
						carried[target.get_instance_id()] = true
	for part in parts:
		for group in ["DeathVolumes", "EffectVolumes", "Headlights"]:
			if not part.has_node(group):
				continue
			for node in part.get_node(group).get_children():
				if not ridden.has(str(node.name)):
					continue
				check(carried.has(node.get_instance_id()),
						"%s/%s/%s rides a mover but no Matinee moves it" % [part.name, group, node.name])


## How far outside its shapes a fall-height volume's Center may sit: rounding.
const FALL_HEIGHT_SLACK_M := 0.05

## Every TdFallHeightVolume the level should have is built once, from its own
## actor, with the touch's height the original's Center.Z + FallHeightOffset,
## and with its shapes standing where that Center is: the cooked Center is
## the original's, the shapes are the brush as placed here, so the two
## agreeing is the placement checked against the original.
func _check_fall_heights(geometries: Array[Node], manifest: Dictionary, scripted: bool) -> void:
	var expected := {}
	for a: Dictionary in manifest["annotations"]:
		if a["kind"] == "fallheight" and (scripted or not a.get("starts_off", false)):
			expected[Common.actor_id(str(a["package"]), str(a["name"]))] = a
	var built := 0
	var seen := {}
	for part_geometry in geometries:
		var group := part_geometry.get_node_or_null("FallHeightVolumes")
		if group == null:
			continue
		for volume: Node in group.get_children():
			built += 1
			var actor := String(volume.get_meta(Common.ACTOR_META, ""))
			var a: Dictionary = expected.get(actor, {})
			check(not a.is_empty(), "fall-height volume from no expected actor: %s (%s)" % [volume.name, actor])
			check(not seen.has(actor), "fall-height volume built twice: " + actor)
			seen[actor] = true
			check(volume is FallHeightVolume, "fall-height volume has no script: " + volume.name)
			if a.is_empty() or not volume is FallHeightVolume:
				continue
			var fh := volume as FallHeightVolume
			check(is_equal_approx(fh.fall_height_y(), float(a["center"][1]) + float(a["fall_height_offset"])),
					"%s touches at %.3f, the original at Center.Z + FallHeightOffset = %.3f"
					% [actor, fh.fall_height_y(), float(a["center"][1]) + float(a["fall_height_offset"])])
			var bounds := AABB()
			var first := true
			for shape_node in fh.find_children("*", "CollisionShape3D", false, false):
				for p: Vector3 in ((shape_node as CollisionShape3D).shape as ConvexPolygonShape3D).points:
					var world: Vector3 = fh.global_transform * ((shape_node as CollisionShape3D).transform * p)
					bounds = AABB(world, Vector3.ZERO) if first else bounds.expand(world)
					first = false
			var center := Common.v3(a["center"])
			check(not first and bounds.grow(FALL_HEIGHT_SLACK_M).has_point(center),
					"%s: the original's Center %s is outside its shapes %s" % [actor, center, bounds])
	check(built == expected.size(), "FallHeightVolumes has %d nodes, manifest has %d" % [built, expected.size()])
	print("[verify] fall-height volumes: %d" % built)


func _check_count(parts: Array[Node], group: String, manifest: Dictionary, kinds: Array) -> void:
	var expected: int = manifest["annotations"].filter(func(a): return a["kind"] in kinds).size()
	var actual := 0
	for part in parts:
		if part.has_node(group):
			actual += part.get_node(group).get_child_count()
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

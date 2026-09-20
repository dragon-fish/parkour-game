@tool
extends RefCounted

# The editable shell of an extracted level: inherits base_level, instances the
# geometry scene, and holds everything a person tunes by hand -- spawn,
# checkpoints, interaction lines, wire hazards, air walls, lethal volumes.
#
# Built ONLY when the shell does not exist or --rebuild-interactions is given.
# After that the shell is the owner's file; rebuilding geometry never touches it.

const Common := preload("res://tools/me_level/me_level_common.gd")
const GeometryBuilder := preload("res://tools/me_level/geometry_builder.gd")
const MeLibrary := preload("res://tools/me_level/mesh_library.gd")
const BASE_LEVEL := "res://templates/base_level.tscn"
const INTEREST_LINE_SCRIPT := preload("res://scripts/level/interest_line.gd")
const CHECKPOINT_SCRIPT := preload("res://scripts/level/checkpoint.gd")
const BARBED_WIRE_SCRIPT := preload("res://scripts/level/barbed_wire.gd")
const MODIFIER_VOLUME_SCRIPT := preload("res://scripts/level/modifier_volume.gd")
const DEATH_VOLUME_SCRIPT := preload("res://scripts/level/death_volume.gd")
const EFFECT_VOLUME_SCRIPT := preload("res://scripts/level/effect_volume.gd")
const HEADLIGHT_SCRIPT := preload("res://scripts/level/headlight.gd")
const MATINEE_SCRIPT := preload("res://scripts/level/matinee.gd")
const USE_ZONE_SCRIPT := preload("res://scripts/level/use_zone.gd")
const LIFT_SCRIPT := preload("res://scripts/level/lift.gd")
const TELEPORT_SCRIPT := preload("res://scripts/level/teleport_volume.gd")
const GLASS_SCRIPT := preload("res://scripts/level/breakable_glass.gd")
const LEVEL_END_SCRIPT := preload("res://scripts/level/level_end.gd")
const PRESENCE_SCRIPT := preload("res://scripts/level/package_presence.gd")
const KISMET_RUNNER_SCRIPT := preload("res://scripts/level/kismet/kismet_runner.gd")
const KISMET_GRAPH_SCRIPT := preload("res://scripts/level/kismet/kismet_graph.gd")
## How far out from a pane its Reach sees a body coming: a tick at a sprint
## and then some. A dial.
const GLASS_REACH_M := 0.6
## [ME:CONFIRMED] no jump or crouch in a moving lift car, and the speed is
## pinned to the base velocity: [ME:CONFIRMED 02 §2.3] 400 uu/s, 4.0 m/s,
## 14.4 km/h. Absolute, not a share of the current cap. Lift turns the
## volume on only while the car moves.
const LIFT_SPEED_M_S := 4.0

const LINE_KINDS := {zipline = 0, swing = 1, balance = 2, ladder = 3, ledgewalk = 4}

## [ME:CONFIRMED 13 §13.3] Wire costs 35 whatever the difficulty.
const WIRE_DAMAGE := 35.0
## The volume renews its STAGGER while the body stays inside; the status must
## outlive at least two renewals (see ModifierVolume.refresh_interval).
const WIRE_REFRESH_S := 0.05
const WIRE_STAGGER_S := 0.1
## The electric fence's knock-down tint. PROJECT-DEFINED: a translucent blue
## for a shock, where the hard landing's own is red.
const ELECTRIC_TINT := Color(0.35, 0.65, 1.0, 0.5)
## Chapter checkpoints come without a trigger shape (Kismet decides when they
## fire in the original). A starting size for a person to adjust.
const CHAPTER_CHECKPOINT_BOX_M := 4.0
const INTERIOR_SDFGI_ENERGY := 4.0


## Nodes of base_level the shell overrides. They are built as plain nodes of
## the same name and turned into overrides by compose().
const OVERRIDDEN := ["SpawnPoint", "Sun", "WorldEnvironment"]


## The shell's own nodes under a stand-in root. Pack it, then pass the text
## through compose(): Godot cannot pack an inherited scene from a script
## without the editor, so the inheritance is written into the text.
func build(manifest: Dictionary, geometry_path: String) -> Node:
	var config: Dictionary = manifest["config"]
	var root := Node3D.new()
	root.name = "Arena"
	var geometry: Node = (load(geometry_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	geometry.name = "Geometry_" + str(config["id"]).validate_node_name()
	root.add_child(geometry)
	geometry.owner = root

	var annotations: Array = manifest["annotations"]
	# Whatever rides a mover, gathered as it is built and handed to _matinees()
	# so the sequence carries it. Volumes first, matinees after: a Matinee
	# addresses its riders by path, so they have to exist and be named.
	var borne := {}
	var sequences := {}
	_own(root, _air_walls(annotations))
	_own(root, _interest_lines(annotations, manifest["placements"]))
	_own(root, _barbed_wire(annotations))
	_own(root, _death_volumes(annotations, borne))
	_own(root, _effect_volumes(annotations, config, borne))
	_own(root, _headlights(annotations, borne))
	_own(root, _pain_volumes(annotations))
	_own(root, _glass(manifest, NodePath("../../" + String(geometry.name) + "/Movers")))
	_own(root, _level_ends(annotations))
	_own(root, _matinees(manifest, NodePath("../../" + String(geometry.name) + "/Movers"), {}, borne, sequences))
	_own(root, _checkpoints(manifest, NodePath("../../" + String(geometry.name) + "/Movers"), sequences))
	_own(root, _teleports(manifest))
	_place_spawn(root, manifest)
	if config.get("interior", false):
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.visible = false
		_own(root, sun)
		var base: Node = (load(BASE_LEVEL) as PackedScene).instantiate()
		var environment: Environment = (base.get_node("WorldEnvironment") as WorldEnvironment).environment.duplicate()
		base.free()
		environment.sdfgi_enabled = true
		environment.sdfgi_energy = INTERIOR_SDFGI_ENERGY
		var world := WorldEnvironment.new()
		world.name = "WorldEnvironment"
		world.environment = environment
		_own(root, world)
	return root


## One section of a split chapter: its geometry plus the interactions standing
## in it. A plain Node3D, not an Arena -- sections are opened to be edited and
## played only through the chapter scene's SectionLoader.
func build_section(manifest: Dictionary, geometry_path: String, section_name: String) -> Node:
	var root := Node3D.new()
	root.name = section_name.validate_node_name()
	var geometry: Node = (load(geometry_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	geometry.name = "Geometry"
	root.add_child(geometry)
	geometry.owner = root
	var annotations: Array = manifest["annotations"]
	var borne := {}
	var sequences := {}
	_own(root, _air_walls(annotations))
	_own(root, _interest_lines(annotations, manifest.get("all_placements", manifest["placements"])))
	_own(root, _barbed_wire(annotations))
	_own(root, _death_volumes(annotations, borne))
	_own(root, _effect_volumes(annotations, manifest["config"], borne))
	_own(root, _headlights(annotations, borne))
	_own(root, _pain_volumes(annotations))
	_own(root, _glass(manifest, NodePath("../../Geometry/Movers")))
	_own(root, _level_ends(annotations))
	# A chapter that runs the original's Kismet (KismetRunner) has no use for
	# the hand-written Lift: the lift's own sequence is built like any other
	# and the graph plays it, doors, button, streaming and all.
	var scripted: bool = manifest.get("streaming") is Dictionary
	_own(root, _matinees(manifest, NodePath("../../Geometry/Movers"), {} if scripted else _lift_actors(manifest), borne, sequences))
	if not scripted:
		_own(root, _lifts(manifest, NodePath("../../Geometry/Movers")))
	_own(root, _checkpoints(manifest, NodePath("../../Geometry/Movers"), sequences))
	return root


## The config's hand-described lifts whose car stands in this manifest.
func _lifts(manifest: Dictionary, movers: NodePath) -> Node3D:
	var group := _group("Lifts")
	var present := {}
	var cars := {}
	for p: Dictionary in manifest["placements"]:
		if p.get("mover", false):
			var key := "%s.%s" % [p["package"], p["name"]]
			present[key] = NodePath(String(movers) + "/" + Common.mover_name(p["package"], p["name"]))
			cars[key] = p
	var names := Common.NameAllocator.new()
	for lift: Dictionary in manifest["config"].get("lifts", []):
		if not present.has(lift["car"]):
			continue
		var node := Node3D.new()
		node.set_script(LIFT_SCRIPT)
		node.name = names.take("Lift_" + Common.mover_name("", lift["car"]))
		node.set("car", present[lift["car"]])
		# The car's own doors are the ones hard-attached to it: naming them by
		# hand swapped a car pair with a landing pair that sits in the same
		# place at the bottom stop.
		var car_doors: Array[NodePath] = []
		for p: Dictionary in manifest["placements"]:
			if p.get("mover", false) and p.get("base") == lift["car"]:
				car_doors.append(present["%s.%s" % [p["package"], p["name"]]])
		node.set("car_doors", car_doors)
		var stop_doors: Array[Array] = []
		for doors: Array in lift["stop_doors"]:
			var paths: Array[NodePath] = []
			for actor: String in doors:
				paths.append(present[actor])
			stop_doors.append(paths)
		node.set("stop_doors", stop_doors)
		node.set("travel", Common.v3(lift["travel"]))
		node.set("travel_time", float(lift["travel_time"]))
		node.set("door_open_offset", Common.v3(lift["door_open_offset"]))
		node.set("door_time", float(lift["door_time"]))
		# Both volumes fill the car's bounds; the Lift carries them along.
		var box: Dictionary = cars[lift["car"]]["aabb"]
		var lo := Common.v3(box["min"])
		var hi := Common.v3(box["max"])
		var shape := BoxShape3D.new()
		shape.size = hi - lo
		var zone := Area3D.new()
		zone.set_script(USE_ZONE_SCRIPT)
		zone.name = "UseZone"
		zone.set("require_whole_body", true)
		zone.position = (lo + hi) * 0.5
		var zone_shape := CollisionShape3D.new()
		zone_shape.name = "CollisionShape3D"
		zone_shape.shape = shape
		zone.add_child(zone_shape)
		node.add_child(zone)
		var rules := Area3D.new()
		rules.set_script(MODIFIER_VOLUME_SCRIPT)
		rules.name = "CarRules"
		rules.position = zone.position
		var rules_shape := CollisionShape3D.new()
		rules_shape.name = "CollisionShape3D"
		rules_shape.shape = shape
		rules.add_child(rules_shape)
		var specs: Array[StatusSpec] = []
		for effect in [Status.Effect.BLOCK_JUMP, Status.Effect.BLOCK_CROUCH, Status.Effect.SPEED_LIMIT]:
			var spec := StatusSpec.new()
			spec.effect = effect
			spec.seconds = WIRE_STAGGER_S
			if effect == Status.Effect.SPEED_LIMIT:
				spec.amount = LIFT_SPEED_M_S
			specs.append(spec)
		rules.set("apply", specs)
		rules.set("refresh_interval", WIRE_REFRESH_S)
		node.add_child(rules)
		if lift.has("call"):
			var button := _matinee_trigger(_trigger_named(manifest, lift["call"]), true)
			if button == null:
				push_error("[me_level] lift call button %s has no shape" % lift["call"])
			else:
				button.name = "CallZone"
				node.add_child(button)
				node.set("call_zone", NodePath("CallZone"))
		group.add_child(node)
	return group


## A matinee trigger by "package.name", wherever a sequence starts from it.
func _trigger_named(manifest: Dictionary, id: String) -> Dictionary:
	for m: Dictionary in manifest.get("matinees", []):
		for start: Dictionary in m["starts"]:
			if start.has("trigger") and "%s.%s" % [m["package"], start["trigger"]["name"]] == id:
				return start["trigger"]
	push_error("[me_level] no matinee starts from %s" % id)
	return {"name": id}


## Every actor a configured Lift of this manifest drives: car, car doors and
## landing doors. The Lift owns them; a matinee moving one too fights it.
static func _lift_actors(manifest: Dictionary) -> Dictionary:
	var out := {}
	var present := {}
	for p: Dictionary in manifest["placements"]:
		if p.get("mover", false):
			present["%s.%s" % [p["package"], p["name"]]] = p
	for lift: Dictionary in manifest["config"].get("lifts", []):
		if not present.has(lift["car"]):
			continue
		out[lift["car"]] = true
		for doors: Array in lift["stop_doors"]:
			for actor: String in doors:
				out[actor] = true
		for id: String in present:
			if present[id].get("base") == lift["car"]:
				out[id] = true
	return out


## The movement sequences whose movers stand in this manifest, with their
## touch and use triggers and their "Completed" chains. `movers` is the Movers
## group as seen from a Matinee node. Groups moving an actor in `lifted` are
## left out: the Lift that owns it would be fought.
func _matinees(manifest: Dictionary, movers: NodePath, lifted: Dictionary,
		borne: Dictionary = {}, sequences: Dictionary = {}) -> Node3D:
	var group := _group("Matinees")
	var present := {}
	var riders := {}
	for p: Dictionary in manifest["placements"]:
		if p.get("mover", false):
			var id := "%s.%s" % [p["package"], p["name"]]
			present[id] = Common.mover_name(p["package"], p["name"])
			if p.get("base") != null:
				if not riders.has(p["base"]):
					riders[p["base"]] = []
				riders[p["base"]].append(id)
	var names := Common.NameAllocator.new()
	var by_source := {}
	for m: Dictionary in manifest.get("matinees", []):
		var tracks: Array[Dictionary] = []
		for g: Dictionary in m["groups"]:
			if g["actors"].any(func(actor: String) -> bool: return lifted.has(actor)):
				continue
			var targets: Array[NodePath] = []
			# Per target: null to move the target itself, or the transform of
			# the actor it is hard-attached to, which is what the keys move.
			var pivots: Array = []
			for actor: String in g["actors"]:
				if present.has(actor):
					targets.append(NodePath(String(movers) + "/" + present[actor]))
					pivots.append(null)
				var frame: Dictionary = m["frames"].get(actor, {})
				for rider: String in riders.get(actor, []):
					if frame.is_empty():
						continue
					targets.append(NodePath(String(movers) + "/" + present[rider]))
					pivots.append(Common.transform_of(frame))
				# The volumes and lamps standing in this shell that ride the
				# same actor. They pivot about it exactly as a hard-attached
				# mesh does -- a kill box is no different from a carriage.
				for path: NodePath in borne.get(actor, [] as Array[NodePath]):
					if frame.is_empty():
						continue
					targets.append(path)
					pivots.append(Common.transform_of(frame))
			if targets.is_empty():
				continue
			var track := {targets = targets, pivots = pivots, local = bool(g["keys"].get("local", false)),
					absolute = bool(g["keys"].get("absolute", false))}
			_matinee_channel(track, "pos_", g["keys"]["position"])
			_matinee_channel(track, "rot_", g["keys"]["euler"])
			_matinee_channel(track, "scl_", g["keys"].get("scale", []))
			tracks.append(track)
		if tracks.is_empty():
			continue
		var node := Node3D.new()
		node.set_script(MATINEE_SCRIPT)
		node.name = names.take(str(m["name"]).get_file().replace("#", "_"))
		node.set("tracks", tracks)
		node.set("length", float(m["length"]))
		node.set("play_rate", float(m.get("play_rate", 1.0)))
		if m.get("autostart", false):
			node.set("autostart", true)
		if m.has("start_position"):
			node.set("start_position", float(m["start_position"]))
		var rolling: Dictionary = m.get("sound") if m.get("sound") is Dictionary else {}
		if not rolling.is_empty():
			var streams := _streams_for([rolling], manifest["config"])
			if not streams.is_empty():
				node.set("sound", {stream = streams[0],
					fade_in = float(rolling.get("fade_in", 0.0)),
					fade_out = float(rolling.get("fade_out", 0.0))})
		# One trigger node per originator: a lever reached through a Switch
		# both plays and reverses, which is a toggle.
		var triggers := {}
		for start: Dictionary in m["starts"]:
			if start["on"] == "after":
				continue
			var key := "%s:%s" % [start["on"], start["trigger"]["name"]]
			if not triggers.has(key):
				triggers[key] = {start = start, actions = {}}
			triggers[key]["actions"][int(start["input"])] = true
		var trigger_names := Common.NameAllocator.new()
		for key: String in triggers:
			var entry: Dictionary = triggers[key]
			var start: Dictionary = entry["start"]
			var area := _matinee_trigger(start["trigger"], start["on"] == "use")
			if area == null:
				continue
			area.name = trigger_names.take(area.name)
			var actions: Dictionary = entry["actions"]
			area.set_meta("action", "toggle" if actions.size() > 1 else ("reverse" if actions.has(1) else "play"))
			area.set_meta("delay", float(start["delay"]))
			node.add_child(area)
		node.set_meta(Common.MATINEE_META, str(m["name"]))
		node.set_meta(Common.PACKAGE_META, Common.package_key(str(m["package"])))
		group.add_child(node)
		by_source[m["name"]] = node
		# By the ACTOR it drives, for whoever has to name a sequence later: a
		# sequence has no name of its own worth carrying, and reproducing this
		# node's name elsewhere is how the two would drift apart.
		for g: Dictionary in m["groups"]:
			for actor: String in g["actors"]:
				sequences[actor] = String(node.name)
	# "Completed" chains: the earlier sequence starts the later one.
	for m: Dictionary in manifest.get("matinees", []):
		if not by_source.has(m["name"]):
			continue
		var later: Node = by_source[m["name"]]
		for start: Dictionary in m["starts"]:
			if start["on"] != "after" or not by_source.has(start["source"]):
				continue
			var earlier: Node = by_source[start["source"]]
			var followers: Array[Dictionary] = earlier.get("followers")
			var follower := {path = NodePath("../" + String(later.name)),
				action = "reverse" if int(start["input"]) == 1 else "play", delay = float(start["delay"])}
			# A gap the original draws fresh every time. Carried as the range,
			# not as its middle: the point of it is that it varies.
			if start.has("delay_min") and float(start["delay_max"]) > float(start["delay_min"]):
				follower["delay_min"] = float(start["delay_min"])
				follower["delay_max"] = float(start["delay_max"])
			if not followers.has(follower):
				followers.append(follower)
			earlier.set("followers", followers)
	return group


const MATINEE_MODES := {constant = 0, linear = 1, curve = 2}


static func _matinee_channel(track: Dictionary, prefix: String, keys: Array) -> void:
	var times := PackedFloat32Array()
	var values := PackedVector3Array()
	var arrive := PackedVector3Array()
	var leave := PackedVector3Array()
	var modes := PackedByteArray()
	for key: Dictionary in keys:
		times.append(float(key["time"]))
		values.append(Common.v3(key["value"]))
		arrive.append(Common.v3(key["arrive"]))
		leave.append(Common.v3(key["leave"]))
		modes.append(MATINEE_MODES[key["mode"]])
	track[prefix + "times"] = times
	track[prefix + "values"] = values
	track[prefix + "arrive"] = arrive
	track[prefix + "leave"] = leave
	track[prefix + "modes"] = modes


func _matinee_trigger(t: Dictionary, use: bool) -> Area3D:
	var area := Area3D.new()
	area.collision_mask = Arena.PLAYER_LAYER
	if use:
		area.set_script(USE_ZONE_SCRIPT)
	area.name = str(t["name"]).validate_node_name()
	if t.has("hull"):
		# Position only: the volume's rotation and (non-uniform) scale are
		# baked into the hull points, which physics requires.
		area.position = Common.v3(t["position"])
		if _hull_shapes(area, t, area.transform) == 0:
			area.free()
			return null
		return area
	if t.has("radius") and t.has("position"):
		area.position = Common.v3(t["position"])
		var cylinder := CylinderShape3D.new()
		cylinder.radius = float(t["radius"])
		# UE's CollisionHeight is the HALF height.
		cylinder.height = 2.0 * float(t["height"])
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = cylinder
		area.add_child(collision)
		return area
	area.free()
	push_warning("[me_level] matinee trigger %s has no shape" % t["name"])
	return null


## Metres below the section's lowest geometry where falling out begins.
const FALL_OUT_MARGIN := 10.0


## Arena.fall_out_height for a section: under everything it contains. A fixed
## default kills on every spawn in a level built underground.
static func fall_out_height(manifest: Dictionary) -> float:
	var lowest := INF
	for placement: Dictionary in manifest["placements"]:
		if placement.has("aabb"):
			lowest = minf(lowest, float(placement["aabb"]["min"][1]))
	return (lowest if lowest != INF else 0.0) - FALL_OUT_MARGIN


## Packed text of build()'s root -> a scene inheriting base_level.
static func compose(text: String, fall_out: float) -> String:
	var lines := text.split("\n")
	var out := PackedStringArray()
	var root_done := false
	for line in lines:
		if line.begins_with("[gd_scene "):
			out.append(line)
			out.append("")
			out.append('[ext_resource type="PackedScene" path="%s" id="me_base_level"]' % BASE_LEVEL)
			continue
		if not root_done and line.begins_with('[node name="Arena" type="Node3D"'):
			out.append('[node name="Arena" instance=ExtResource("me_base_level")]')
			out.append("fall_out_height = %s" % snappedf(fall_out, 0.01))
			root_done = true
			continue
		for name: String in OVERRIDDEN:
			if line.begins_with('[node name="%s" type="' % name) and line.contains('parent="."'):
				line = RegEx.create_from_string(' type="[^"]*"').sub(line, "")
				line = RegEx.create_from_string(' unique_id=[0-9]+').sub(line, "")
		out.append(line)
	if not root_done:
		# WHAT IT SAW, not just that it failed. The root line is the one thing
		# this function needs and the one thing the old message never showed,
		# which turned a one-line mismatch into an afternoon.
		var first_node := "(no [node line at all)"
		for line in lines:
			if line.begins_with("[node "):
				first_node = line
				break
		push_error("[me_level] packed shell has no Arena root: %d chars, %d lines, first node line %s\n---8<---\n%s\n---8<---"
			% [text.length(), lines.size(), first_node, text.substr(0, 700)])
		return ""
	return "\n".join(out)


static func _own(root: Node, group: Node) -> void:
	root.add_child(group)
	_set_owner(group, root)


static func _set_owner(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		# Runtime children (a wire's mesh, a line's rope) are never packed.
		_set_owner(child, owner)


## The package an annotation's node came from, for PackagePresence: an air
## wall of a package that is not in the level must not stand in the way.
static func _stamp(node: Node, annotation: Dictionary) -> void:
	if annotation.has("package"):
		node.set_meta(Common.PACKAGE_META, Common.package_key(str(annotation["package"])))
		if annotation.has("name"):
			node.set_meta(Common.ACTOR_META, Common.actor_id(str(annotation["package"]), str(annotation["name"])))


## {path from the shell's root: {meta: value}} for every node that carries
## where it came from, outside the instanced geometry. How a shell that was
## built before the stamp existed, and has been edited by hand since, still
## gets its nodes found: the table rides on the chapter geometry and
## PackagePresence puts it on the real shell's nodes by path. A node renamed or
## deleted since simply finds no entry.
static func origins(shell: Node) -> Dictionary:
	var out := {}
	var todo: Array[Node] = []
	for child in shell.get_children():
		if child.scene_file_path.is_empty():
			todo.append(child)
	while not todo.is_empty():
		var node: Node = todo.pop_back()
		var found := {}
		for meta in [Common.PACKAGE_META, Common.ACTOR_META, Common.MATINEE_META]:
			if node.has_meta(meta):
				found[String(meta)] = node.get_meta(meta)
		if not found.is_empty():
			out[String(shell.get_path_to(node))] = found
			continue
		todo.append_array(node.get_children())
	return out


func _group(name: String) -> Node3D:
	var group := Node3D.new()
	group.name = name
	return group


func _hull_shapes(node: Node3D, annotation: Dictionary, frame: Transform3D) -> int:
	# Hull vertices are local and unscaled; the annotation's basis carries both.
	var relative := frame.affine_inverse() * Common.transform_of(annotation)
	var names := Common.NameAllocator.new()
	var made := 0
	for hull: Dictionary in annotation.get("hull", []):
		if hull["vertices"].size() < 4:
			continue
		var points := PackedVector3Array()
		for v: Array in hull["vertices"]:
			points.append(relative * Common.v3(v))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.name = names.take("CollisionShape3D")
		collision.shape = shape
		node.add_child(collision)
		made += 1
	return made


func _air_walls(annotations: Array) -> Node3D:
	var group := _group("AirWalls")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if a["kind"] != "blocking":
			continue
		var wall := StaticBody3D.new()
		wall.name = names.take(a["name"])
		wall.set_meta("exclude_hand", a["exclude_hand"])
		wall.set_meta("exclude_foot", a["exclude_foot"])
		if a["exclude_hand"] and a["exclude_foot"]:
			wall.add_to_group("no_interaction", true)
		# [ME:CONFIRMED] the volume's PhysMaterialOverride decides what standing
		# on it is. Escape's slanted-building chute is one of these, lying 0-10 cm
		# over a mesh with no slide flag: without the group the capsule stood on
		# the wall and never slid.
		if a.get("uncontrolled_slide", false):
			wall.add_to_group(Probes.UNCONTROLLED_SLIDE_GROUP, true)
		if a.get("soft_landing", false):
			wall.add_to_group(Probes.SOFT_LANDING_GROUP, true)
		if _hull_shapes(wall, a, Transform3D.IDENTITY) == 0:
			push_error("[me_level] air wall %s has no hull" % a["name"])
			wall.free()
			continue
		_stamp(wall, a)
		group.add_child(wall)
	return group


func _interest_lines(annotations: Array, placements: Array) -> Node3D:
	var group := _group("InterestLines")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if not LINE_KINDS.has(a["kind"]):
			continue
		var points := _swing_points(a, placements) if a["kind"] == "swing" else GeometryBuilder.line_points(a)
		if points.size() < 2:
			push_error("[me_level] %s has no usable interaction line" % a["name"])
			continue
		var line := Path3D.new()
		line.set_script(INTEREST_LINE_SCRIPT)
		line.name = names.take(a["name"])
		line.transform = Transform3D(_front_basis(a), points[0])
		var inverse := line.transform.affine_inverse()
		var curve := Curve3D.new()
		for p in points:
			curve.add_point(inverse * p)
		line.curve = curve
		line.set("kind", LINE_KINDS[a["kind"]])
		# THE REACH IS NOT TAKEN FROM THE ORIGINAL'S BOX, though the manifest
		# still measures it (annotations._volume_reach) and it is worth having
		# on record. The box says where the move is allowed and which bar it is
		# about -- _swing_points() above already uses it for exactly that --
		# and it is nothing like how far a hand stretches: read as a reach it
		# gave the Subway's tunnel swings a 5.75 m capsule, catchable from the
		# far rail. InterestLine.KIND_REACH owns this number; see its note.
		_stamp(line, a)
		group.add_child(line)
	return group


## Yaw-only basis whose -Z is InterestLine.front(). The original's WallNormal
## points OUT of the wall on every kind (measured on every ledge walk in three
## levels), but front() does not mean the same thing on every kind: a LADDER's
## front is the side it is climbed from, which is WallNormal, while a LEDGE
## WALK's front points AT the wall (LedgeWalkMove._yaw_offset(), and the
## hand-built balance course). DO NOT hand WallNormal to a ledge walk as-is:
## every extracted ledge walk comes out turned round.
static func _front_basis(a: Dictionary) -> Basis:
	if not a.has("wall"):
		return Basis()
	var wall := Common.v3(a["wall"])
	wall.y = 0.0
	if wall.length_squared() < 0.0001:
		return Basis()
	var front := -wall if a["kind"] == "ledgewalk" else wall
	var z := -front.normalized()
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)


## Swing volumes describe a vertical trigger, not the grip bar. The bar is
## whatever horizontal pole or pipe runs through the volume: the tutorial
## hangs S_SwingPole_01c there, the Stormdrain hangs ceiling pipes, Escape
## rotates a catwalk support into a horizontal bar, Cranes hangs a bar on
## rods under a bridge, Convoy uses a scaffold tube, and the Boat and the
## Scraper swing on ceiling frames. Candidates still have to run horizontally
## through the volume. Join collinear segments and clip.
const SWING_BAR_TOKENS: Array[String] = ["swingpole", "swingbar", "pipe",
		"catwalksystem_05_support", "scaffolding", "ceilingframe"]
const SWING_BAR_MIN_M := 0.5
const SWING_COLLINEAR_M := 0.1
## Vertices this close across the long axis belong to one member of a mesh.
const SWING_MEMBER_CELL_M := 0.1
## Members closer than this are one: the rings of a pipe's round section each
## run its whole length, and apart they would put the bar off the pipe's axis.
const SWING_MEMBER_MERGE_M := 0.4

func _swing_points(a: Dictionary, placements: Array) -> Array[Vector3]:
	var volume := Common.transform_of(a)
	var inverse := volume.affine_inverse()
	var local_bounds := AABB()
	var first := true
	for hull: Dictionary in a.get("hull", []):
		for v: Array in hull["vertices"]:
			var p := Common.v3(v)
			local_bounds = AABB(p, Vector3.ZERO) if first else local_bounds.expand(p)
			first = false
	if first:
		return []
	var bars := []
	for placement: Dictionary in placements:
		var lower := str(placement["mesh"]).to_lower()
		if not SWING_BAR_TOKENS.any(func(token): return lower.contains(token)):
			continue
		var mesh: ArrayMesh = load(preload("res://tools/me_level/mesh_library.gd").path_for(placement["mesh"]))
		var local: AABB = mesh.get_meta("bounds")
		var transform := Common.transform_of(placement)
		for member: Array in _long_members(mesh, local):
			var p0: Vector3 = transform * member[0]
			var p1: Vector3 = transform * member[1]
			# Through the volume, not centred in it: one 9.4 m frame on the
			# Boat carries four swing volumes in a row.
			if _clip_segment(inverse * p0, inverse * p1, local_bounds.grow(0.05)).is_empty():
				continue
			var direction := p1 - p0
			if direction.length() < SWING_BAR_MIN_M or absf(direction.normalized().y) > 0.1:
				continue
			bars.append([p0, p1])
	if bars.is_empty():
		return []
	# The bar passes through the volume's middle; the ceiling pipes around it
	# are often just as long. Nearest the middle first, longest on a tie.
	var middle := volume.origin
	bars.sort_custom(func(x, y):
		var dx := _off_line(middle, x[0], x[1])
		var dy := _off_line(middle, y[0], y[1])
		if absf(dx - dy) > SWING_COLLINEAR_M:
			return dx < dy
		return x[0].distance_to(x[1]) > y[0].distance_to(y[1]))
	var origin: Vector3 = bars[0][0]
	var along: Vector3 = (bars[0][1] - bars[0][0]).normalized()
	var lo := INF
	var hi := -INF
	for bar in bars:
		for p: Vector3 in bar:
			var offset := p - origin
			if (offset - along * offset.dot(along)).length() > SWING_COLLINEAR_M:
				break
			lo = minf(lo, offset.dot(along))
			hi = maxf(hi, offset.dot(along))
	# Clip the joined bar to the volume, measured in the volume's local frame.
	var a_local := inverse * (origin + along * lo)
	var b_local := inverse * (origin + along * hi)
	var clipped := _clip_segment(a_local, b_local, local_bounds)
	if clipped.is_empty():
		return []
	return [volume * clipped[0], volume * clipped[1]]


## The mesh's members that run its whole length, as [start, end] in its own
## frame. A pole or pipe is one, its bounding box's centre line. Cranes' swing
## bar hangs on rods from a rail, and that centre line runs through neither,
## 0.85 m above the bar: a mesh wider across than SWING_MEMBER_MERGE_M is split
## into the groups of vertices that reach both of its ends.
##
## DO NOT split the thin ones too. A pipe's flanges shift the averaged line by
## a few centimetres, enough to stop it joining the next piece of the run, and
## Stormdrain's bars came out up to 1.7 m short.
static func _long_members(mesh: ArrayMesh, local: AABB) -> Array:
	var axis := local.size.max_axis_index()
	var span := local.size[axis]
	var start := local.position[axis]
	var across := local.size
	across[axis] = 0.0
	if across[across.max_axis_index()] < SWING_MEMBER_MERGE_M:
		var half := Vector3.ZERO
		half[axis] = span * 0.5
		return [[local.get_center() - half, local.get_center() + half]]
	var groups := {}
	for surface in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var off := v
			off[axis] = 0.0
			var key := Vector3i((off / SWING_MEMBER_CELL_M).round())
			if not groups.has(key):
				groups[key] = [INF, -INF, Vector3.ZERO, 0]
			var g: Array = groups[key]
			g[0] = minf(g[0], v[axis])
			g[1] = maxf(g[1], v[axis])
			g[2] += off
			g[3] += 1
	# [sum of across-positions, vertex count] per merged member.
	var merged := []
	for g: Array in groups.values():
		if g[1] - g[0] < span * 0.9:
			continue
		var centre: Vector3 = g[2] / float(g[3])
		var home: Array = []
		for m: Array in merged:
			if (m[0] / float(m[1])).distance_to(centre) < SWING_MEMBER_MERGE_M:
				home = m
				break
		if home.is_empty():
			merged.append([g[2], g[3]])
		else:
			home[0] += g[2]
			home[1] += g[3]
	var members := []
	for m: Array in merged:
		var a: Vector3 = m[0] / float(m[1])
		var b := a
		a[axis] = start
		b[axis] = start + span
		members.append([a, b])
	if members.is_empty():
		var half := Vector3.ZERO
		half[axis] = span * 0.5
		members.append([local.get_center() - half, local.get_center() + half])
	return members


## Distance from `p` to the infinite line through `a` and `b`.
static func _off_line(p: Vector3, a: Vector3, b: Vector3) -> float:
	var along := (b - a).normalized()
	var offset := p - a
	return (offset - along * offset.dot(along)).length()


static func _clip_segment(a: Vector3, b: Vector3, box: AABB) -> Array[Vector3]:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 3:
		if absf(d[axis]) < 1e-6:
			if a[axis] < box.position[axis] or a[axis] > box.end[axis]:
				return []
			continue
		var near := (box.position[axis] - a[axis]) / d[axis]
		var far := (box.end[axis] - a[axis]) / d[axis]
		if near > far:
			var swap := near
			near = far
			far = swap
		t0 = maxf(t0, near)
		t1 = minf(t1, far)
	if t1 - t0 <= 0.0:
		return []
	return [a + d * t0, a + d * t1]


func _barbed_wire(annotations: Array) -> Node3D:
	var group := _group("BarbedWire")
	var names := Common.NameAllocator.new()
	var spec := StatusSpec.new()
	spec.effect = Status.Effect.STAGGER
	spec.amount = WIRE_DAMAGE
	spec.seconds = WIRE_STAGGER_S
	for a: Dictionary in annotations:
		if a["kind"] != "barbedwire":
			continue
		var points := _wire_points(a)
		if points.is_empty():
			push_error("[me_level] wire %s has no brush" % a["name"])
			continue
		var wire := Path3D.new()
		wire.set_script(BARBED_WIRE_SCRIPT)
		wire.name = names.take(a["name"])
		wire.position = points[0]
		var curve := Curve3D.new()
		for p in points:
			curve.add_point(p - points[0])
		wire.curve = curve
		var hazard := Area3D.new()
		hazard.set_script(MODIFIER_VOLUME_SCRIPT)
		hazard.name = "Hazard"
		hazard.set("apply", [spec] as Array[StatusSpec])
		hazard.set("refresh_interval", WIRE_REFRESH_S)
		_hull_shapes(hazard, a, wire.transform)
		wire.add_child(hazard)
		_stamp(wire, a)
		group.add_child(wire)
	return group


## Cached Start/End/SplineLocations on wire volumes are stale (zeros, NaNs);
## the brush sits on the fence, so its long axis is the wire.
func _wire_points(a: Dictionary) -> Array[Vector3]:
	var vertices: Array[Vector3] = []
	for hull: Dictionary in a.get("hull", []):
		for v: Array in hull["vertices"]:
			vertices.append(Common.v3(v))
	if vertices.is_empty():
		return []
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		bounds = bounds.expand(v)
	var axis := bounds.size.max_axis_index()
	var start := bounds.get_center()
	var end := start
	start[axis] = bounds.position[axis]
	end[axis] = bounds.end[axis]
	var transform := Common.transform_of(a)
	return [transform * start, transform * end]


## Lethal volumes: the level's own TdKillVolumes, plus any volume riding a
## mover whose touch reaches the original's player-fail. A Mall train kills
## with one of these and with nothing else -- its cars have no collision.
##
## `borne` collects, per ridden actor, the path of every node built here that
## has to travel with it. _matinees() turns those into Matinee targets.
func _death_volumes(annotations: Array, borne: Dictionary) -> Node3D:
	var group := _group("DeathVolumes")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if a["kind"] != "kill" and not _effect_of(a).get("kill", false):
			continue
		var volume := Area3D.new()
		volume.set_script(DEATH_VOLUME_SCRIPT)
		volume.name = names.take(a["name"])
		if _shapes_on(volume, a) == 0:
			push_error("[me_level] kill volume %s has no shape" % a["name"])
			volume.free()
			continue
		_stamp(volume, a)
		group.add_child(volume)
		_record_rider(borne, a, "DeathVolumes", volume.name)
	return group


## What the original's Kismet does when this volume is touched, or {}.
static func _effect_of(a: Dictionary) -> Dictionary:
	var effects: Variant = a.get("effects")
	return effects if effects is Dictionary else {}


## Notes that `node` rides whatever `a` is attached to, as a Matinee sees it:
## a Matinee sits in its own group beside this one, so two levels up and back
## down. Silently does nothing for an annotation that rides nothing.
static func _record_rider(borne: Dictionary, a: Dictionary, group: String, node: StringName) -> void:
	var base: Variant = a.get("base")
	if base == null:
		return
	if not borne.has(base):
		borne[base] = [] as Array[NodePath]
	(borne[base] as Array[NodePath]).append(NodePath("../../%s/%s" % [group, node]))


## Shapes for a volume, IN THE NODE'S OWN FRAME, with the node standing where
## the volume stands.
##
## The older volumes here are built the other way round -- node at the origin,
## shapes carrying the world transform -- which is equivalent for anything that
## never moves. It is NOT equivalent for a rider: a Matinee moves the NODE, so
## a node sitting at the world origin has its sound come from the world origin
## however far away its shapes are. Positioning the node is also what lets a
## person find it in the editor.
func _shapes_on(node: Node3D, a: Dictionary) -> int:
	var frame := Common.transform_of(a)
	node.transform = frame
	var made := _hull_shapes(node, a, frame)
	if made > 0 or not a.has("radius"):
		return made
	# A Trigger is a cylinder, not a brush: the original's CollisionHeight is a
	# HALF-height, Godot's is the whole of it.
	var shape := CylinderShape3D.new()
	shape.radius = float(a["radius"])
	shape.height = float(a.get("height", 0.0)) * 2.0
	if shape.radius <= 0.0 or shape.height <= 0.0:
		return 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	# The node carries the volume's basis, which for a Trigger is the actor's
	# rotation; the cylinder stands along the node's own Y.
	node.add_child(collision)
	collision.shape = shape
	return 1


## Volumes that are heard and felt rather than survived: the horn box ahead of
## a train, the shake cylinder around its head. A volume that also kills has a
## DeathVolume of its own built beside this one -- see DeathVolume's own note
## on why it carries no settings.
func _effect_volumes(annotations: Array, config: Dictionary, borne: Dictionary) -> Node3D:
	var group := _group("EffectVolumes")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		var effect := _effect_of(a)
		if effect.is_empty():
			continue
		var streams := _streams_for(effect.get("sounds", []), config)
		var shake: Dictionary = effect.get("shake") if effect.get("shake") is Dictionary else {}
		if streams.is_empty() and shake.is_empty():
			# Its only outcome was the kill, which the DeathVolume carries; or
			# its sounds are ones this project has no file for yet.
			continue
		var volume := Area3D.new()
		volume.set_script(EFFECT_VOLUME_SCRIPT)
		volume.name = names.take(a["name"])
		if _shapes_on(volume, a) == 0:
			push_error("[me_level] effect volume %s has no shape" % a["name"])
			volume.free()
			continue
		volume.set("sounds", streams)
		volume.set("shake_amplitude", float(shake.get("amplitude", 0.0)))
		volume.set("shake_frequency", float(shake.get("frequency", 0.0)))
		volume.set("shake_hold", float(shake.get("hold", 0.0)))
		_stamp(volume, a)
		group.add_child(volume)
		_record_rider(borne, a, "EffectVolumes", volume.name)
	return group


## The streams behind a list of the original's cue names.
##
## A name the config does not map makes NO stream and NO error. The original's
## audio is never extracted and the map lives outside this repository, so a
## build with no map at all has to produce a level that runs -- silent, not
## broken. A path that IS mapped but does not load is a mistake worth saying.
static func _streams_for(cues: Array, config: Dictionary) -> Array[AudioStream]:
	var sounds: Dictionary = config.get("sounds", {})
	var out: Array[AudioStream] = []
	for cue: Dictionary in cues:
		var path: String = str(sounds.get(cue["name"], ""))
		if path.is_empty():
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			push_error("[me_level] sound %s: %s is not an AudioStream" % [cue["name"], path])
			continue
		out.append(stream)
	return out


## The original's LensFlareSources, as lamps with a glow card. It places them
## on the front of the things that move: a train's pair sits 11.52 m ahead of
## the head and 1.28 m either side.
##
## A flare has no Kismet and no shape -- there is nothing to read about it
## beyond where it is -- so unlike an effect volume it is built from its
## position alone.
func _headlights(annotations: Array, borne: Dictionary) -> Node3D:
	var group := _group("Headlights")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if a["kind"] != "flare":
			continue
		var lamp := Node3D.new()
		lamp.set_script(HEADLIGHT_SCRIPT)
		lamp.name = names.take(a["name"])
		lamp.transform = Common.transform_of(a)
		var light := OmniLight3D.new()
		light.name = "Light"
		# Shadows off: a train carries four of these through a tunnel full of
		# geometry, and none of them is there to shape the scene.
		light.shadow_enabled = false
		lamp.add_child(light)
		var glow := MeshInstance3D.new()
		glow.name = "Glow"
		glow.mesh = QuadMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# A glow that hides what is behind it stops being a glow. Depth write
		# off, depth TEST on: it is still occluded by the tunnel wall.
		material.no_depth_test = false
		glow.material_override = material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(glow)
		_stamp(lamp, a)
		group.add_child(lamp)
		_record_rider(borne, a, "Headlights", lamp.name)
	return group


## PhysicsVolumes that hurt: Escape's electric fences. [ME:CONFIRMED] the
## original drains DamagePerSec while the body touches the fence; here a touch
## is a knock-down like the wire's, costing one second of it, so the fence
## cannot be climbed.
func _pain_volumes(annotations: Array) -> Node3D:
	var group := _group("PainVolumes")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if a["kind"] != "pain":
			continue
		var spec := StatusSpec.new()
		spec.effect = Status.Effect.STAGGER
		spec.amount = float(a["damage_per_sec"])
		spec.seconds = WIRE_STAGGER_S
		if a["damage_type"] == "TdDmgType_ElectricShock":
			spec.tint = ELECTRIC_TINT
		var volume := Area3D.new()
		volume.set_script(MODIFIER_VOLUME_SCRIPT)
		volume.name = names.take(a["name"])
		volume.set("apply", [spec] as Array[StatusSpec])
		if a.get("once", false):
			# [ME:CONFIRMED Factory Kismet] switched off by its own touch: one
			# hit per life, not a volume to stand in.
			volume.set("max_trigger_count", 1)
		else:
			volume.set("refresh_interval", WIRE_REFRESH_S)
		if _hull_shapes(volume, a, Transform3D.IDENTITY) == 0:
			push_error("[me_level] pain volume %s has no hull" % a["name"])
			volume.free()
			continue
		_stamp(volume, a)
		group.add_child(volume)
	return group


## Panes the body smashes by running into them (BreakableGlass). The pane is
## the geometry's own mover; Reach is its bounds grown by GLASS_REACH_M.
func _glass(manifest: Dictionary, movers: NodePath) -> Node3D:
	var group := _group("Glass")
	var placed := {}
	for p: Dictionary in manifest["placements"]:
		placed["%s.%s" % [p["package"], p["name"]]] = p
	var names := Common.NameAllocator.new()
	for a: Dictionary in manifest["annotations"]:
		if a["kind"] != "glass":
			continue
		if not placed.has(a["pane"]):
			push_error("[me_level] glass %s is not placed" % a["pane"])
			continue
		var pane: Dictionary = placed[a["pane"]]
		var glass := Node3D.new()
		glass.set_script(GLASS_SCRIPT)
		glass.name = names.take(a["name"])
		glass.set("pane", NodePath(String(movers) + "/" + Common.mover_name(pane["package"], pane["name"])))
		var lo := Common.v3(pane["aabb"]["min"])
		var hi := Common.v3(pane["aabb"]["max"])
		var reach := Area3D.new()
		reach.name = "Reach"
		reach.collision_mask = Arena.PLAYER_LAYER
		reach.position = (lo + hi) * 0.5
		var shape := BoxShape3D.new()
		shape.size = (hi - lo) + Vector3.ONE * GLASS_REACH_M * 2.0
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = shape
		reach.add_child(collision)
		glass.add_child(reach)
		_stamp(glass, a)
		group.add_child(glass)
	return group


## The touches that end the chapter (LevelEnd), in the shapes of the original's
## triggers.
## The chapter's PackagePresence and the KismetRunner under it, or null for a
## level the extractor wrote no graph for. They go into the chapter GEOMETRY,
## which is rebuilt every time, not into the shell, which is edited by hand.
## `graph_path` is where the graph itself is saved, as a resource of its own:
## thousands of nodes have no business in a scene file.
func build_streaming(manifest: Dictionary, kismet: Dictionary, graph_path: String) -> Node3D:
	var flow = manifest.get("streaming")
	if not flow is Dictionary or kismet.is_empty():
		return null
	var snapshots := {}
	var checkpoint_actors := {}
	var streamed := {}
	var start := ""
	for c: Dictionary in manifest["checkpoints"]:
		if (c.get("streaming", []) as Array).is_empty():
			continue
		var label := str(c["label"]) if str(c.get("label", "")) != "" else str(c["name"])
		snapshots[label] = PackedStringArray(c["streaming"])
		checkpoint_actors[label] = Common.actor_id(str(c["package"]), str(c["name"]))
		for key: String in c["streaming"]:
			streamed[key] = true
		if c.get("default", false) and start == "":
			start = label
	if snapshots.is_empty():
		return null
	var spawn = manifest["config"].get("initial_spawn")
	if spawn is String and snapshots.has(spawn):
		start = spawn
	var presence := Node3D.new()
	presence.name = "Streaming"
	presence.set_script(PRESENCE_SCRIPT)
	presence.set("snapshots", snapshots)
	presence.set("start", start)
	presence.set("managed", PackedStringArray(flow["managed"]))
	presence.set("shell_origins", manifest.get("shell_origins", {}))

	# A mesh the graph swaps in, as the path the level loads it from.
	for id: String in kismet["nodes"]:
		if (kismet["nodes"][id] as Dictionary).has("mesh"):
			kismet["nodes"][id]["mesh_path"] = MeLibrary.path_for(str(kismet["nodes"][id]["mesh"]))
	var graph: Resource = KISMET_GRAPH_SCRIPT.new()
	graph.set("nodes", kismet["nodes"])
	graph.set("variables", kismet["vars"])
	graph.set("actors", kismet["actors"])
	var error := ResourceSaver.save(graph, graph_path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("[me_level] saving %s: %s" % [graph_path, error_string(error)])
		presence.free()
		return null
	var pressed := {}
	var originates := {}
	for id: String in kismet["nodes"]:
		var node: Dictionary = kismet["nodes"][id]
		if node.has("levels"):
			for key: String in node["levels"]:
				streamed[key] = true
		if node.has("originator"):
			originates[node["originator"]] = true
			if str(node["cls"]) in ["SeqEvent_Used", "SeqEvent_TdUsed"]:
				pressed[node["originator"]] = true
	var runner := Node3D.new()
	runner.name = "Kismet"
	runner.set_script(KISMET_RUNNER_SCRIPT)
	runner.set("graph", load(graph_path))
	runner.set("checkpoint_actors", checkpoint_actors)
	runner.set("streamed", PackedStringArray(streamed.keys()))
	presence.add_child(runner)
	# What the original's events listen to: a trigger has no picture and no
	# placement, so nothing else has built it. This project has no use key --
	# standing in a UseZone for its dwell is the press, as it is for a lift.
	var names := Common.NameAllocator.new()
	for actor: String in kismet["actors"]:
		var entry: Dictionary = kismet["actors"][actor]
		# Only where a touch or a press can lead to something that has an
		# effect here (kismet.py, mark_useful): the rest set checkpoints, move
		# the look-at hint and steer AI, and were two hundred zones of nothing.
		if not originates.has(actor) or not entry.has("trigger") or not entry.get("useful", false):
			continue
		var zone := _matinee_trigger(entry["trigger"], pressed.has(actor))
		if zone == null:
			continue
		zone.name = names.take(actor.validate_node_name())
		zone.set_meta(Common.ACTOR_META, actor)
		zone.set_meta(Common.PACKAGE_META, str(entry["package"]))
		runner.add_child(zone)
	# ...and the walls that exist only to be switched by it.
	for actor: String in kismet["actors"]:
		var entry: Dictionary = kismet["actors"][actor]
		if not entry.has("wall") or not (entry["wall"] as Dictionary).has("hull"):
			continue
		var wall := StaticBody3D.new()
		wall.name = names.take(actor.validate_node_name())
		wall.position = Common.v3(entry["wall"]["position"])
		if _hull_shapes(wall, entry["wall"], wall.transform) == 0:
			wall.free()
			continue
		wall.set_meta(Common.ACTOR_META, actor)
		wall.set_meta(Common.PACKAGE_META, str(entry["package"]))
		runner.add_child(wall)
	return presence


func _level_ends(annotations: Array) -> Node3D:
	var group := _group("LevelEnds")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if a["kind"] != "level_end":
			continue
		var area := _matinee_trigger(a["trigger"], false)
		if area == null:
			continue
		area.set_script(LEVEL_END_SCRIPT)
		area.name = names.take(area.name)
		group.add_child(area)
	return group


func _checkpoints(manifest: Dictionary, movers: NodePath = NodePath(), sequences: Dictionary = {}) -> Node3D:
	var group := _group("Checkpoints")
	var names := Common.NameAllocator.new()
	var spawns: Array = manifest["spawns"]
	# Tutorial: respawn volumes with real shapes, sitting at their nearest start.
	for a: Dictionary in manifest["annotations"]:
		if a["kind"] != "checkpointvolume":
			continue
		var checkpoint := Area3D.new()
		checkpoint.set_script(CHECKPOINT_SCRIPT)
		checkpoint.name = names.take(a["name"])
		var nearest := _nearest(Common.v3(a["position"]), spawns)
		if not nearest.is_empty():
			checkpoint.transform = _spawn_transform(nearest)
		_hull_shapes(checkpoint, a, checkpoint.transform)
		group.add_child(checkpoint)
	# Chapters: the persistent level's TdCheckpoints, with a box to adjust.
	for c: Dictionary in manifest["checkpoints"]:
		if c["class"] != "TdCheckpoint":
			continue
		var checkpoint := Area3D.new()
		checkpoint.set_script(CHECKPOINT_SCRIPT)
		checkpoint.name = names.take(c["label"] if c.get("label", "") != "" else c["name"])
		checkpoint.transform = _spawn_transform(c)
		checkpoint.set("index", int(c.get("weight", 0)))
		checkpoint.set("display_name", str(c.get("label", "")))
		var restores := _checkpoint_restores(c, manifest, movers, sequences)
		if not restores.is_empty():
			checkpoint.set("restores", restores)
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * CHAPTER_CHECKPOINT_BOX_M
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = box
		checkpoint.add_child(collision)
		group.add_child(checkpoint)
	return group


## What a respawn onto this checkpoint has to put the level into, as node paths
## seen from the checkpoint. The manifest names ACTORS (package.name); this
## turns them into the mover nodes they became, and -- for `play` -- into the
## Matinee that drives the named actor.
##
## `play` names the driven actor rather than the sequence because a sequence
## has no name of its own worth carrying: the original identifies it only by
## export index, which means nothing to a person editing the config.
func _checkpoint_restores(c: Dictionary, manifest: Dictionary, movers: NodePath, sequences: Dictionary) -> Dictionary:
	var wanted: Dictionary = c.get("restores", {})
	if wanted.is_empty() or String(movers).is_empty():
		return {}
	var present := {}
	for p: Dictionary in manifest.get("all_placements", manifest["placements"]):
		if p.get("mover", false):
			present["%s.%s" % [p["package"], p["name"]]] = Common.mover_name(p["package"], p["name"])
	var out := {}
	for key: String in ["hide", "show"]:
		var paths: Array[NodePath] = []
		for actor: String in wanted.get(key, []):
			if present.has(actor):
				paths.append(NodePath(String(movers) + "/" + present[actor]))
			else:
				push_warning("[me_level] checkpoint %s: %s names no mover" % [c.get("label", ""), actor])
		if not paths.is_empty():
			out[key] = paths
	var played: Array[NodePath] = []
	for actor: String in wanted.get("play", []):
		if not sequences.has(actor):
			push_warning("[me_level] checkpoint %s: nothing drives %s" % [c.get("label", ""), actor])
			continue
		# A Matinee sits in its own group beside the Checkpoints group.
		played.append(NodePath("../../Matinees/" + sequences[actor]))
	if not played.is_empty():
		out["play"] = played
	return out


## The config's cutscene cuts: a box where the original takes the body away,
## and the checkpoint it wakes at. Chapter-wide, because a cut leads from one
## section to another and belongs to neither.
func _teleports(manifest: Dictionary) -> Node3D:
	var group := _group("Teleports")
	var names := Common.NameAllocator.new()
	for spot: Dictionary in manifest["config"].get("teleports", []):
		var volume := Area3D.new()
		volume.set_script(TELEPORT_SCRIPT)
		volume.name = names.take("TeleportTo" + str(spot["to"]).validate_node_name())
		volume.position = Common.v3(spot["at"])
		volume.set("checkpoint_name", str(spot["to"]))
		var box := BoxShape3D.new()
		box.size = Common.v3(spot["size"])
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = box
		volume.add_child(collision)
		group.add_child(volume)
	return group


func _place_spawn(root: Node3D, manifest: Dictionary) -> void:
	var candidates: Array = manifest["spawns"] + manifest.get("all_checkpoints", manifest["checkpoints"])
	if candidates.is_empty():
		push_error("[me_level] no spawn or checkpoint to start from")
		return
	# The configured start wins, then the original's own level start
	# (DefaultCheckpoint), then whatever comes first.
	var wanted = manifest["config"].get("initial_spawn")
	var chosen: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if c.get("default", false):
			chosen = c
			break
	for c: Dictionary in candidates:
		# By label too: that is the name the checkpoint's node carries.
		if c["name"] == wanted or c.get("label", "") == wanted:
			chosen = c
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.transform = _spawn_transform(chosen)
	_own(root, spawn)


## Body centre at the origin, facing -Z: the SpawnPoint/Checkpoint convention.
static func _spawn_transform(entry: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(entry["yaw_deg"]))), Common.v3(entry["position"]))


static func _nearest(position: Vector3, spawns: Array) -> Dictionary:
	var best := {}
	var best_distance := INF
	for s: Dictionary in spawns:
		var d := position.distance_squared_to(Common.v3(s["position"]))
		if d < best_distance:
			best_distance = d
			best = s
	return best

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
const BASE_LEVEL := "res://templates/base_level.tscn"
const INTEREST_LINE_SCRIPT := preload("res://scripts/level/interest_line.gd")
const CHECKPOINT_SCRIPT := preload("res://scripts/level/checkpoint.gd")
const BARBED_WIRE_SCRIPT := preload("res://scripts/level/barbed_wire.gd")
const MODIFIER_VOLUME_SCRIPT := preload("res://scripts/level/modifier_volume.gd")
const DEATH_VOLUME_SCRIPT := preload("res://scripts/level/death_volume.gd")

const LINE_KINDS := {zipline = 0, swing = 1, balance = 2, ladder = 3, ledgewalk = 4}

## [ME:CONFIRMED 13 §13.3] Wire costs 35 whatever the difficulty.
const WIRE_DAMAGE := 35.0
## The volume renews its STAGGER while the body stays inside; the status must
## outlive at least two renewals (see ModifierVolume.refresh_interval).
const WIRE_REFRESH_S := 0.05
const WIRE_STAGGER_S := 0.1
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
	_own(root, _air_walls(annotations))
	_own(root, _interest_lines(annotations, manifest["placements"]))
	_own(root, _barbed_wire(annotations))
	_own(root, _death_volumes(annotations))
	_own(root, _checkpoints(manifest))
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
	var lines := text.split("
")
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
		push_error("[me_level] packed shell has no Arena root")
		return ""
	return "
".join(out)


static func _own(root: Node, group: Node) -> void:
	root.add_child(group)
	_set_owner(group, root)


static func _set_owner(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		# Runtime children (a wire's mesh, a line's rope) are never packed.
		_set_owner(child, owner)


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
		if _hull_shapes(wall, a, Transform3D.IDENTITY) == 0:
			push_error("[me_level] air wall %s has no hull" % a["name"])
			wall.free()
			continue
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
## hangs S_SwingPole_01c there, the Stormdrain hangs ceiling pipes. Take the
## longest one, join the segments collinear with it, clip to the volume.
const SWING_BAR_TOKENS: Array[String] = ["swingpole", "pipe"]
const SWING_BAR_MIN_M := 0.5
const SWING_COLLINEAR_M := 0.1

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
		var centre := transform * local.get_center()
		if not local_bounds.grow(0.05).has_point(inverse * centre):
			continue
		var axis := local.size.max_axis_index()
		var half := Vector3.ZERO
		half[axis] = local.size[axis] * 0.5
		var p0 := transform * (local.get_center() - half)
		var p1 := transform * (local.get_center() + half)
		var direction := p1 - p0
		if direction.length() < SWING_BAR_MIN_M or absf(direction.normalized().y) > 0.1:
			continue
		bars.append([p0, p1])
	if bars.is_empty():
		return []
	bars.sort_custom(func(x, y): return x[0].distance_to(x[1]) > y[0].distance_to(y[1]))
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


func _death_volumes(annotations: Array) -> Node3D:
	var group := _group("DeathVolumes")
	var names := Common.NameAllocator.new()
	for a: Dictionary in annotations:
		if a["kind"] != "kill":
			continue
		var volume := Area3D.new()
		volume.set_script(DEATH_VOLUME_SCRIPT)
		volume.name = names.take(a["name"])
		if _hull_shapes(volume, a, Transform3D.IDENTITY) == 0:
			push_error("[me_level] kill volume %s has no hull" % a["name"])
			volume.free()
			continue
		group.add_child(volume)
	return group


func _checkpoints(manifest: Dictionary) -> Node3D:
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
		checkpoint.name = names.take(c["name"])
		checkpoint.transform = _spawn_transform(c)
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * CHAPTER_CHECKPOINT_BOX_M
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = box
		checkpoint.add_child(collision)
		group.add_child(checkpoint)
	return group


func _place_spawn(root: Node3D, manifest: Dictionary) -> void:
	var candidates: Array = manifest["spawns"] + manifest["checkpoints"]
	if candidates.is_empty():
		push_error("[me_level] no spawn or checkpoint to start from")
		return
	var wanted = manifest["config"].get("initial_spawn")
	var chosen: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if c["name"] == wanted:
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

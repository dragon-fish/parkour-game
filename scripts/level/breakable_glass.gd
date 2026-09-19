class_name BreakableGlass
extends Node3D

## A pane the body smashes by running into it. [ME:CONFIRMED Cranes Kismet]
## the original breaks it on TdDmgType_Barge, the damage of crashing into it;
## this project has no barge move, so the speed at which the original would
## barge rather than kick decides.
##
## The pane is a mover of the level's geometry, pointed at by `pane`. Breaking
## hides it and takes its collision away BEFORE the body moves this tick, so
## the run carries straight through at full speed; the shards are thrown from
## where it stood and fade away on their own.
##
## Reach is the Area3D child: the pane's bounds grown by enough to see a body
## coming a tick before it arrives.

## The pane's body, whose Mesh and CollisionShape3D children break.
@export var pane: NodePath
## [ME:CONFIRMED A1] TdMove_Barge.BargeKickThresholdSpeed = 250 uu/s: slower,
## the original kicks instead. Speed TOWARD the pane, not the body's speed.
@export var barge_speed: float = 2.5
## Roughly how big a shard is, in metres. A dial.
@export var shard_size: float = 0.45
## How much of the body's velocity the shards take with them. A dial.
@export var shard_carry: float = 0.6
## Seconds the shards lie there before fading, and how long the fade takes.
@export var shard_linger: float = 3.0
@export var shard_fade: float = 1.0

const SHARD_COLOR := Color(0.78, 0.88, 0.92, 0.35)
const SHARD_THICKNESS := 0.01
## Never more shards than this from one pane, however large.
const MAX_SHARDS := 48

var _broken := false
var _shards: Node3D = null
var _fade_left := 0.0
var _material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(Arena.RESET_ON_RESPAWN)
	# Before the Player's own physics tick, so the pane is gone by the time the
	# body moves into it.
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	if _broken:
		_age_shards(delta)
		return
	var reach := get_node_or_null("Reach") as Area3D
	if reach == null:
		return
	for body in reach.get_overlapping_bodies():
		if body is CharacterBody3D and body.has_method("touch_checkpoint") \
				and approach_speed(body.global_position, (body as CharacterBody3D).velocity) >= barge_speed:
			shatter((body as CharacterBody3D).velocity)
			return


## How fast something at `at` moving at `velocity` closes on the pane's plane.
func approach_speed(at: Vector3, velocity: Vector3) -> float:
	var frame := _pane_frame()
	if frame.is_empty():
		return 0.0
	var normal: Vector3 = frame["normal"]
	var side := signf((at - (frame["centre"] as Vector3)).dot(normal))
	if side == 0.0:
		side = 1.0
	return -velocity.dot(normal * side)


## Breaks the pane now, throwing the shards along `velocity`.
func shatter(velocity: Vector3 = Vector3.ZERO) -> void:
	if _broken:
		return
	var frame := _pane_frame()
	_set_pane(false)
	_broken = true
	if frame.is_empty():
		return
	_spawn_shards(frame, velocity)


func is_broken() -> bool:
	return _broken


func reset_for_respawn() -> void:
	_broken = false
	_set_pane(true)
	if _shards != null:
		_shards.queue_free()
		_shards = null


func _set_pane(whole: bool) -> void:
	var body := get_node_or_null(pane) as Node3D
	if body == null:
		return
	for child in body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = whole
		elif child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not whole


## The pane's centre, its normal and its two in-plane edges (full length), in
## world space, from its drawn mesh: the thinnest axis of its bounds is the
## normal. Empty when there is no pane.
func _pane_frame() -> Dictionary:
	var body := get_node_or_null(pane) as Node3D
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D if body != null else null
	if mesh == null or mesh.mesh == null:
		return {}
	var box: AABB = mesh.get_aabb()
	var xf: Transform3D = mesh.global_transform
	var thin := box.size.min_axis_index()
	var edges: Array[Vector3] = []
	for axis in 3:
		if axis != thin:
			edges.append(xf.basis[axis] * box.size[axis])
	return {
		centre = xf * box.get_center(),
		normal = xf.basis[thin].normalized(),
		u = edges[0],
		v = edges[1],
	}


## Cuts the pane into jittered triangles and throws them.
func _spawn_shards(frame: Dictionary, velocity: Vector3) -> void:
	var u: Vector3 = frame["u"]
	var v: Vector3 = frame["v"]
	var corner: Vector3 = (frame["centre"] as Vector3) - u * 0.5 - v * 0.5
	var cols := clampi(roundi(u.length() / shard_size), 1, 8)
	var rows := clampi(roundi(v.length() / shard_size), 1, 12)
	while cols * rows * 2 > MAX_SHARDS:
		if rows > cols:
			rows -= 1
		else:
			cols -= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_path())
	# Grid points, interior ones jittered so the cuts do not read as a grid.
	var points := []
	for j in rows + 1:
		var row := []
		for i in cols + 1:
			var a := float(i) / cols
			var b := float(j) / rows
			if i > 0 and i < cols:
				a += rng.randf_range(-0.3, 0.3) / cols
			if j > 0 and j < rows:
				b += rng.randf_range(-0.3, 0.3) / rows
			row.append(corner + u * a + v * b)
		points.append(row)
	_material = StandardMaterial3D.new()
	_material.albedo_color = SHARD_COLOR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.roughness = 0.1
	_shards = Node3D.new()
	_shards.name = "Shards"
	add_child(_shards)
	var normal: Vector3 = frame["normal"]
	for j in rows:
		for i in cols:
			var p00: Vector3 = points[j][i]
			var p10: Vector3 = points[j][i + 1]
			var p01: Vector3 = points[j + 1][i]
			var p11: Vector3 = points[j + 1][i + 1]
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				_add_shard(tri, normal, velocity, rng)
	_fade_left = shard_linger + shard_fade


func _add_shard(tri: Array, normal: Vector3, velocity: Vector3, rng: RandomNumberGenerator) -> void:
	var centre: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
	var half := normal * SHARD_THICKNESS * 0.5
	var local := PackedVector3Array()
	for p: Vector3 in tri:
		local.append(p - centre + half)
	for p: Vector3 in tri:
		local.append(p - centre - half)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 2, 3, 5, 4, 0, 3, 1, 1, 3, 4, 1, 4, 2, 2, 4, 5, 2, 5, 0, 0, 5, 3]:
		st.add_vertex(local[index])
	st.generate_normals()
	var shard := RigidBody3D.new()
	shard.name = "Shard"
	# Collides with the level, never with the body that broke it.
	shard.collision_layer = 0
	shard.collision_mask = 1
	shard.mass = 0.2
	var drawn := MeshInstance3D.new()
	drawn.mesh = st.commit()
	drawn.material_override = _material
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard.add_child(drawn)
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = local
	shape.shape = hull
	shard.add_child(shape)
	_shards.add_child(shard)
	shard.global_position = centre
	shard.linear_velocity = velocity * shard_carry \
		+ Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0))
	shard.angular_velocity = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))


## Lets the shards lie, then fades them together and frees them.
func _age_shards(delta: float) -> void:
	if _shards == null:
		return
	_fade_left -= delta
	if _fade_left <= 0.0:
		_shards.queue_free()
		_shards = null
		return
	if _fade_left < shard_fade and _material != null:
		_material.albedo_color.a = SHARD_COLOR.a * _fade_left / maxf(shard_fade, 0.001)

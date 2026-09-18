class_name Matinee
extends Node3D

## One movement sequence from an extracted level: when something that can
## touch a checkpoint enters one of this node's Area3D children, every target
## is carried along its keys, once.
##
## Keys are RELATIVE to where each target stands when THIS sequence starts,
## not when the level loaded: a sequence chained after another one continues
## from wherever the first left the targets. Positions are world offsets;
## rotations turn each target about its own origin in world axes.
## [ME:INFERRED] UE3 InterpTrackMove's default frame -- see the extractor's
## matinee.py.
##
## Only the "touch plays it" shape of the original's Kismet is reproduced.
## Gates, switches and "used" buttons are not; neither are sounds or events.

## One entry per moving group: {targets: Array[NodePath], and per channel
## (pos_, rot_) times, values, arrive, leave, modes}. Positions are metres;
## rotations the original's (roll, pitch, yaw) in degrees, turned into a basis
## after sampling. modes: 0 constant, 1 linear, 2 curve (Hermite on the
## stored tangents).
@export var tracks: Array[Dictionary] = []
@export var length: float = 0.0
## Played when this one finishes -- the original's "Completed" output.
@export var next: Array[NodePath] = []

var _time: float = -1.0
var _played := false
var _starts: Array = []


func _ready() -> void:
	set_physics_process(false)
	for child in get_children():
		if child is Area3D:
			(child as Area3D).body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Duck-typed like Checkpoint: whatever can touch a checkpoint is a player.
	if body.has_method("touch_checkpoint"):
		play()


func play() -> void:
	if _played:
		return
	_played = true
	_starts.clear()
	for track: Dictionary in tracks:
		var starts: Array[Transform3D] = []
		for path: NodePath in track["targets"]:
			var target := get_node_or_null(path) as Node3D
			starts.append(target.global_transform if target != null else Transform3D())
		_starts.append(starts)
	_time = 0.0
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_time = minf(_time + delta, length)
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		var offset := sample(track["pos_times"], track["pos_values"], track["pos_arrive"],
			track["pos_leave"], track["pos_modes"], _time)
		var euler := sample(track["rot_times"], track["rot_values"], track["rot_arrive"],
			track["rot_leave"], track["rot_modes"], _time)
		var turn := basis_from_euler(euler)
		var targets: Array = track["targets"]
		for j in targets.size():
			var target := get_node_or_null(targets[j]) as Node3D
			if target == null:
				continue
			var start: Transform3D = _starts[i][j]
			target.global_transform = Transform3D(turn * start.basis, start.origin + offset)
	if _time >= length:
		set_physics_process(false)
		for path in next:
			var following := get_node_or_null(path) as Matinee
			if following != null:
				following.play()


## UE3 FInterpCurve::Eval: the leaving key's mode decides the segment.
static func sample(times: PackedFloat32Array, values: PackedVector3Array, arrive: PackedVector3Array,
		leave: PackedVector3Array, modes: PackedByteArray, t: float) -> Vector3:
	if times.is_empty():
		return Vector3.ZERO
	if t <= times[0]:
		return values[0]
	for k in range(1, times.size()):
		if t > times[k]:
			continue
		var span := maxf(times[k] - times[k - 1], 0.0001)
		var a := (t - times[k - 1]) / span
		match modes[k - 1]:
			0:
				return values[k - 1]
			1:
				return values[k - 1].lerp(values[k], a)
		var a2 := a * a
		var a3 := a2 * a
		return values[k - 1] * (2.0 * a3 - 3.0 * a2 + 1.0) + leave[k - 1] * span * (a3 - 2.0 * a2 + a) \
			+ arrive[k] * span * (a3 - a2) + values[k] * (-2.0 * a3 + 3.0 * a2)
	return values[values.size() - 1]


## (roll, pitch, yaw) degrees -> Godot basis. The same conjugation by the
## Y/Z axis swap as the extractor's common.godot_basis(); DO NOT re-derive it
## in Godot's own Euler conventions, that is how a mirrored level happened.
static func basis_from_euler(euler: Vector3) -> Basis:
	var r := deg_to_rad(euler.x)
	var p := deg_to_rad(euler.y)
	var y := deg_to_rad(euler.z)
	var sp := sin(p)
	var sy := sin(y)
	var sr := sin(r)
	var cp := cos(p)
	var cy := cos(y)
	var cr := cos(r)
	var row0 := Vector3(cp * cy, cp * sy, sp)
	var row1 := Vector3(sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp)
	var row2 := Vector3(-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp)
	return Basis(Vector3(row0.x, row0.z, row0.y), Vector3(row2.x, row2.z, row2.y), Vector3(row1.x, row1.z, row1.y))

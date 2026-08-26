class_name BlinkController
extends Node

# Drives one blend shape as a blink, on a randomised clock. Close, open,
# wait 2-6 s, repeat -- and after a LONG wait the eyes have gone dry, so
# there is a chance the blink comes twice (✅ the owner: 超过 4.8 秒才眨眼则
# 有概率连续眨两下). Model-agnostic: the mesh and shape name are exports,
# so a VRM's Fcl_EYE_Close works as well as this FBX's `blink`.

@export var mesh_path: NodePath
@export var shape_name: String = "blink"
@export var min_interval: float = 2.0
@export var max_interval: float = 6.0
## Waits longer than this are "dry eyes": a second blink may follow.
@export var dry_eye_after: float = 4.8
@export_range(0.0, 1.0) var double_blink_chance: float = 0.6
@export var close_time: float = 0.1
@export var open_time: float = 0.15
## The pause between the two blinks of a double.
@export var double_gap: float = 0.09

enum Phase { WAIT, CLOSING, OPENING, GAP }

## Seconds to close the eyes when they are held shut. Slower than a blink:
## ✅ THE OWNER asked for closed eyes on death, and a body that dies by
## BLINKING reads as a wink. This is the lids giving up, not a reflex.
const HELD_CLOSE_TIME := 0.35

var _mesh: MeshInstance3D
var _shape: int = -1
var _phase: Phase = Phase.WAIT
var _left: float = 0.0
var _double_pending: bool = false
## Held shut, overriding the blink clock entirely. DeathSequence sets it.
var _held_closed: bool = false
var _held_weight: float = 0.0

func _ready() -> void:
	_mesh = get_node_or_null(mesh_path) as MeshInstance3D
	if _mesh != null:
		_shape = _mesh.find_blend_shape_by_name(shape_name)
	if _shape < 0:
		set_process(false)
		return
	_schedule()

func _schedule() -> void:
	_left = randf_range(min_interval, max_interval)
	_double_pending = _left > dry_eye_after and randf() < double_blink_chance
	_phase = Phase.WAIT

## Closes the eyes and keeps them closed until told otherwise. The blink clock
## is left running underneath and simply not applied, so releasing this hands
## back a controller in a sane state rather than one frozen mid-blink.
func set_held_closed(closed: bool) -> void:
	_held_closed = closed

func _process(delta: float) -> void:
	# The hold outranks the blink. Eased rather than snapped for the same
	# reason the death camera is: an instant cut reads as a dropped frame.
	if _held_closed or _held_weight > 0.0:
		var target: float = 1.0 if _held_closed else 0.0
		_held_weight = move_toward(_held_weight, target, delta / HELD_CLOSE_TIME)
		if _held_closed or _held_weight > 0.0:
			_apply(_held_weight)
			if _held_closed:
				return
	_left -= delta
	match _phase:
		Phase.WAIT:
			if _left <= 0.0:
				_phase = Phase.CLOSING
				_left = close_time
		Phase.CLOSING:
			_apply(1.0 - maxf(_left, 0.0) / close_time)
			if _left <= 0.0:
				_phase = Phase.OPENING
				_left = open_time
		Phase.OPENING:
			_apply(maxf(_left, 0.0) / open_time)
			if _left <= 0.0:
				if _double_pending:
					_double_pending = false
					_phase = Phase.GAP
					_left = double_gap
				else:
					_schedule()
		Phase.GAP:
			if _left <= 0.0:
				_phase = Phase.CLOSING
				_left = close_time

func _apply(weight: float) -> void:
	_mesh.set_blend_shape_value(_shape, clampf(weight, 0.0, 1.0))

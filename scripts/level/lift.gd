class_name Lift
extends Node3D

## A lift between two stops, hand-written rather than replayed: the
## original's is a Kismet state machine (gates, sub-sequences, "used"
## buttons, and doubling as a streaming gate), none of which is worth
## reproducing. Its numbers -- travel, travel time, door slide -- are the
## original's, carried in the level config.
##
## Idle: the car's doors and the landing doors where it stands are OPEN.
## Stand in the car for UseZone.dwell: doors close, the car travels, the doors
## at the other stop open.
##
## A lift with a call button idles CLOSED at stop 0 instead, until the button's
## zone is used: the original's Escape lift opens on its exterior button and
## nothing else. [ME:CONFIRMED] the original allows no jump or
## crouch in the car, and base walking speed only; the car's ModifierVolume
## says so.

@export var car: NodePath
## Doors that travel with the car.
@export var car_doors: Array[NodePath] = []
## Landing doors, one list per stop. Stop 0 is where the car stands at load;
## stop 1 is `travel` from there.
@export var stop_doors: Array[Array] = []
## In the car's own frame, like door_open_offset in each door's: the
## original's lift tracks are IMF_RelativeToInitial.
@export var travel: Vector3 = Vector3.ZERO
@export var travel_time: float = 5.0
## Offset from a door's closed transform (as the level stores it) to open, in
## THAT DOOR'S OWN FRAME: the two leaves of a pair face opposite ways, so one
## offset opens them to opposite sides.
@export var door_open_offset: Vector3 = Vector3.ZERO
@export var door_time: float = 0.7
## The landing's call button, a UseZone child that stays where it is when the
## car moves. Empty: no button, and the doors stand open.
@export var call_zone: NodePath

enum State { IDLE, CLOSING, MOVING, OPENING }

var _state: int = State.IDLE
var _stop: int = 0
var _clock: float = 0.0
var _car_home: Transform3D
var _door_homes: Dictionary = {}
## Interior of the car in its own frame, from its mesh: where a rider must be.
var _interior := AABB()
## Children that ride with the car: the use zone and the status volume.
var _riders: Dictionary = {}
## Where the car is from its load position, and how open the doors are.
var _car_offset := Vector3.ZERO
var _door_open: float = 1.0
## The car's status volume (no jump, no crouch, base speed), or null.
var _rules: ModifierVolume = null


func _ready() -> void:
	add_to_group(Arena.RESET_ON_RESPAWN)
	var body := get_node(car) as Node3D
	_car_home = body.global_transform
	var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		_interior = mesh.transform * mesh.get_aabb()
	for path: NodePath in _all_doors():
		_door_homes[path] = (get_node(path) as Node3D).global_transform
	var button := get_node_or_null(call_zone) if not call_zone.is_empty() else null
	if button != null:
		(button as UseZone).used.connect(_on_called)
	for child in get_children():
		if child == button:
			continue
		if child is Node3D:
			_riders[child] = _car_home.affine_inverse() * (child as Node3D).global_transform
		if child is UseZone:
			(child as UseZone).used.connect(_on_used)
		elif child is ModifierVolume:
			_rules = child
	_set_doors(_idle_open())
	_apply_rules()


## How open the doors stand at stop 0 before anyone has done anything.
func _idle_open() -> float:
	return 0.0 if not call_zone.is_empty() else 1.0


func reset_for_respawn() -> void:
	_state = State.IDLE
	_stop = 0
	_clock = 0.0
	_place_car(0.0)
	_set_doors(_idle_open())


func _on_used() -> void:
	if _state != State.IDLE or _door_open < 1.0:
		return
	_state = State.CLOSING
	_clock = 0.0


## The call button only opens a car that waits closed at its landing: once
## ridden, the car stays at the other stop, as in the original.
func _on_called() -> void:
	if _state != State.IDLE or _stop != 0 or _door_open > 0.0:
		return
	_state = State.OPENING
	_clock = 0.0


func _physics_process(delta: float) -> void:
	if _state == State.IDLE:
		_carry_riders()
		return
	_clock += delta
	match _state:
		State.CLOSING:
			_set_doors(1.0 - minf(_clock / door_time, 1.0))
			if _clock >= door_time:
				_state = State.MOVING
				_clock = 0.0
		State.MOVING:
			var t := minf(_clock / travel_time, 1.0)
			var eased := t * t * (3.0 - 2.0 * t)
			_place_car(eased if _stop == 0 else 1.0 - eased)
			if t >= 1.0:
				_stop = 1 - _stop
				_state = State.OPENING
				_clock = 0.0
		State.OPENING:
			_set_doors(minf(_clock / door_time, 1.0))
			if _clock >= door_time:
				_state = State.IDLE
	_carry_riders()
	_apply_rules()
	if _state != State.IDLE:
		_keep_player_inside()


## [ME:CONFIRMED] The car's rules hold only while it MOVES: standing in a
## car at rest, or riding it while the doors work, the body may jump, crouch
## and run as anywhere. Monitoring off empties the volume's overlap list, so
## its refresh applies nothing and the statuses run out within their own
## seconds; on again, the area reports the bodies already inside.
func _apply_rules() -> void:
	if _rules != null:
		_rules.monitoring = _state == State.MOVING


func _place_car(along: float) -> void:
	_car_offset = _car_home.basis.orthonormalized() * travel * along
	(get_node(car) as Node3D).global_transform = Transform3D(_car_home.basis, _car_home.origin + _car_offset)
	_apply_doors()


## 0 closed .. 1 open, for the car's doors and the landing doors at its stop.
func _set_doors(open: float) -> void:
	_door_open = open
	_apply_doors()


func _apply_doors() -> void:
	for path: NodePath in car_doors:
		var home: Transform3D = _door_homes[path]
		var slide := home.basis.orthonormalized() * door_open_offset * _door_open
		(get_node(path) as Node3D).global_transform = Transform3D(home.basis, home.origin + _car_offset + slide)
	for i in stop_doors.size():
		for path: NodePath in stop_doors[i]:
			var home: Transform3D = _door_homes[path]
			var open := _door_open if i == _stop else 0.0
			var slide := home.basis.orthonormalized() * door_open_offset * open
			(get_node(path) as Node3D).global_transform = Transform3D(home.basis, home.origin + slide)


func _carry_riders() -> void:
	var now := (get_node(car) as Node3D).global_transform
	for child: Node3D in _riders:
		child.global_transform = now * (_riders[child] as Transform3D)


## A body half out of the car when the doors shut would be cut by them or
## left behind by the floor. Shameless, and on purpose: put it back inside.
func _keep_player_inside() -> void:
	if _interior.size == Vector3.ZERO:
		return
	var body := get_node(car) as Node3D
	for zone in _riders:
		if not zone is UseZone:
			continue
		for p: Node3D in (zone as UseZone).get_overlapping_bodies():
			if p.has_method("touch_checkpoint"):
				_squeeze(body, p)


## Pushes a body whose centre is over the car but whose capsule pokes past
## its walls back in by the capsule's radius. Bodies not over the car at all
## are left alone: they were never riding.
func _squeeze(body: Node3D, p: Node3D) -> void:
	const RADIUS := 0.4
	var local := body.global_transform.affine_inverse() * p.global_position
	if local.y < _interior.position.y - 0.5 or local.y > _interior.end.y + 0.5:
		return
	var over_car := local.x >= _interior.position.x and local.x <= _interior.end.x \
		and local.z >= _interior.position.z and local.z <= _interior.end.z
	if not over_car:
		return
	var clamped := Vector3(
		clampf(local.x, _interior.position.x + RADIUS, _interior.end.x - RADIUS), local.y,
		clampf(local.z, _interior.position.z + RADIUS, _interior.end.z - RADIUS))
	if clamped != local:
		p.global_position = body.global_transform * clamped


func _all_doors() -> Array[NodePath]:
	var out: Array[NodePath] = []
	out.append_array(car_doors)
	for doors in stop_doors:
		for path: NodePath in doors:
			out.append(path)
	return out

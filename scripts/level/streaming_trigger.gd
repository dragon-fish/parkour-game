class_name StreamingTrigger
extends Node3D

## Where the original loads or unloads packages: one of these per event that
## does, holding the steps it sets off. Its one child is the shape -- an Area3D
## for a touch, a UseZone for what the original had pressed (this project has
## no use key; standing there for the zone's dwell is the press, as it is for
## a lift).
##
## Fires ONCE per life, like the original's triggers, and comes back with the
## level on a respawn. It carries its package like any other node of the
## level, so a trigger whose package is not present cannot fire.

signal fired(trigger: StreamingTrigger)

const GROUP := &"streaming_triggers"
## How far outside a lift's car a button still counts as that lift's.
const LIFT_REACH_M := 1.5

## package.actor of the originator, for the log and the HUD.
@export var source: String = ""
## What the original had pressed or shot rather than walked into.
@export var pressed: bool = false
## {op: "load" | "unload", packages: PackedStringArray, delay: float,
## order: int}, in the order they happen.
@export var steps: Array[Dictionary] = []

## The lift this is the button of, or null. Its doors closing is then the
## press: the original's button unloads what is behind the rider, and hidden
## at once -- the original's unload took seconds -- the way back went while
## the doors still stood open.
var lift: Lift = null

var _fired := false


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Arena.RESET_ON_RESPAWN)
	for child in get_children():
		if child is UseZone:
			(child as UseZone).used.connect(_fire)
		elif child is Area3D:
			(child as Area3D).body_entered.connect(_on_body_entered)
	if pressed:
		_find_lift.call_deferred()


func reset_for_respawn() -> void:
	_fired = false


func _find_lift() -> void:
	# The zone is where the button is; this node stands at the origin.
	var zone := get_child(0) as Node3D if get_child_count() > 0 else null
	if zone == null:
		return
	for node in get_tree().get_nodes_in_group(Lift.GROUP):
		var candidate := node as Lift
		if candidate != null and candidate.is_button(zone.global_position, LIFT_REACH_M):
			lift = candidate
			lift.doors_closed.connect(_fire)
			for child in get_children():
				child.process_mode = Node.PROCESS_MODE_DISABLED
			return


func _on_body_entered(body: Node3D) -> void:
	# Duck-typed like Checkpoint: whatever can touch a checkpoint is a player.
	if body.has_method("touch_checkpoint"):
		_fire()


func _fire() -> void:
	if _fired or not can_process():
		return
	_fired = true
	fired.emit(self)

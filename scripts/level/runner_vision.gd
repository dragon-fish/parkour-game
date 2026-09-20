class_name RunnerVision
extends Node

# Drives every RunnerVisionTarget in the level from one place.
#
# ONE TICKER, NOT ONE PER TARGET. The original tags 1268 objects across its
# eleven chapters, 255 of them in a single one; that many nodes each running
# their own _physics_process is a cost paid whether or not anything is near.
# Here one node walks the group and hands each target the player's eye.
#
# It does nothing when the level holds no target, which is the usual case for
# a blockout, so it costs nothing to leave in the base template.

const SETTING := "runner_vision"

## Off hides every target at once, for a level that would rather not have it
## and for judging a blockout without the paint.
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not value:
			_darken()

var _player: Node3D = null


func _ready() -> void:
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var targets := get_tree().get_nodes_in_group(RunnerVisionTarget.GROUP)
	if targets.is_empty():
		return
	if not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return
	var eye := _player.global_position
	for target in targets:
		(target as RunnerVisionTarget).advance(delta, eye)


## The Arena's player, or whatever else can touch a checkpoint: the same
## duck-typed stance DeathVolume and Checkpoint take.
func _find_player() -> Node3D:
	var arena := get_parent()
	while arena != null and not arena is Arena:
		arena = arena.get_parent()
	if arena != null and (arena as Arena).player != null:
		return (arena as Arena).player
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D:
			return node
	return null


func _darken() -> void:
	for target in get_tree().get_nodes_in_group(RunnerVisionTarget.GROUP):
		var t := target as RunnerVisionTarget
		t.fade_out_speed = maxf(t.fade_out_speed, 0.001)
		t.advance(1000.0, Vector3(1.0e9, 1.0e9, 1.0e9))

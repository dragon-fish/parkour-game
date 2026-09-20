class_name PackagePresence
extends Node

## SPIKE, throwaway: answers whether the original's own streaming data is
## enough to keep packages that never coexisted from standing in each other.
##
## [ME:CONFIRMED] every TdCheckpoint lists the packages a restore there loads.
## Present here means exactly that list for the player's active checkpoint;
## the Kismet loads and unloads between two checkpoints are NOT replayed, so
## the stretch ahead appears on touching its checkpoint, not on approaching it.
##
## Everything stays instanced. An absent package is hidden and its bodies are
## taken out of the physics space (process_mode DISABLED, which a
## CollisionObject3D answers by removing itself).

const TABLE_META := &"me_streaming"
const START_META := &"me_streaming_start"
const PACKAGE_META := &"me_package"

## Checkpoint label -> Array of package keys.
var table: Dictionary = {}
## The label that stands for "no checkpoint touched yet".
var start: String = ""

var _nodes_of: Dictionary = {}
var _applied: String = "\n"
var _was_warming := true


func _ready() -> void:
	_index(get_parent())
	print("[presence] %d packages indexed, %d checkpoint sets" % [_nodes_of.size(), table.size()])


func _physics_process(_delta: float) -> void:
	var arena := get_parent() as Arena
	if arena == null or arena.player == null:
		return
	var checkpoint: Checkpoint = arena.player.active_checkpoint
	var label := start
	if checkpoint != null and is_instance_valid(checkpoint):
		label = Arena.checkpoint_label(checkpoint)
	# Lights switch themselves on in batches while the level warms, whatever
	# package they belong to: apply once more when that is over.
	var warming := not get_tree().get_nodes_in_group(Arena.WARMING).is_empty()
	if label == _applied and warming == _was_warming:
		return
	_was_warming = warming
	_applied = label
	_apply(label)


func _index(node: Node) -> void:
	if node.has_meta(PACKAGE_META):
		_nodes_of.get_or_add(String(node.get_meta(PACKAGE_META)), []).append(node)
		return
	for child in node.get_children():
		_index(child)


func _apply(label: String) -> void:
	if not table.has(label):
		push_warning("[presence] no streaming set for checkpoint '%s': everything stays as it is" % label)
		return
	var present := {}
	for key: String in table[label]:
		present[key] = true
	var shown := 0
	for key: String in _nodes_of:
		# A package no checkpoint ever names is the chapter's own and stays.
		var on: bool = present.has(key) or not _streamed(key)
		shown += int(on)
		for node: Node in _nodes_of[key]:
			if node is Node3D:
				(node as Node3D).visible = on
			node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	print("[presence] checkpoint '%s': %d of %d packages present" % [label, shown, _nodes_of.size()])


func _streamed(key: String) -> bool:
	for label: String in table:
		if (table[label] as Array).has(key):
			return true
	return false

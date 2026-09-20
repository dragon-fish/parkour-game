class_name PackagePresence
extends Node3D

## Which of the original's packages are in the level right now.
##
## The original streams: a chapter is some fifty packages, and its level design
## leans on two of them never being loaded together -- a distant shell of a
## building stands where the next stretch's corridor is, and is gone by the
## time the corridor loads. Here a chapter is instanced whole, so without this
## node the shells block corridors and keep the sun out of whole rooms.
##
## [ME:CONFIRMED] two sources, both the original's own. A TdCheckpoint lists
## the packages a restore there loads: `snapshots`, taken on every respawn.
## Between checkpoints Kismet loads and unloads as the player goes: the
## StreamingTrigger children, flattened by the extractor's streaming.py.
## Touching a checkpoint on foot takes NO snapshot -- by then the triggers
## have already brought the level there, and the snapshot is what a restore
## loads, not what the player is standing in.
##
## Everything stays instanced. A package that is not present is hidden and out
## of the physics space (process_mode DISABLED, which a CollisionObject3D
## answers by removing itself). DO NOT free and re-instance here without
## reading docs/seamless-loading.md: _show() is the one place that would
## change, and the frame budget is why it has not.

## Spelt the same in tools/me_level/me_level_common.gd, which cannot name this
## class: a build runs without the autoloads Arena needs.
const PACKAGE_META := &"me_package"
const GROUP := &"package_presence"

## Checkpoint label -> packages present after a restore there.
@export var snapshots: Dictionary = {}
## The label that stands for no checkpoint at all: the level's own spawn.
@export var start: String = ""
## Packages this node governs. Any other package is always present.
@export var managed: PackedStringArray = []
## Section shell root name -> {path from that root: package}, for the volumes
## of shells built before nodes carried their package: see
## ShellBuilder.package_paths().
@export var shell_packages: Dictionary = {}
## A pressed trigger that is no configured lift's button waits at least this
## long. The original's button path often carries no delay of its own -- its
## unload took seconds and the doors shut meanwhile -- and hiding is instant.
@export var pressed_min_delay: float = 3.0

var present: Dictionary = {}
## For the HUD: what fired last.
var last_source: String = ""

var _nodes_of: Dictionary = {}
var _managed: Dictionary = {}
var _applied := false
## Steps waiting out their delay: {at: seconds, order, op, packages, source}.
var _pending: Array[Dictionary] = []
var _clock: float = 0.0
var _arena: Arena = null


func _ready() -> void:
	add_to_group(Arena.RESET_ON_RESPAWN)
	add_to_group(GROUP)
	set_physics_process(false)
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	_arena = node as Arena
	# Deferred: the sections are instanced by a sibling's _ready().
	_begin.call_deferred()


func _begin() -> void:
	for key in managed:
		_managed[key] = true
	# The whole level; with no Arena above (a test, a scene opened on its own)
	# whatever stands beside this node.
	_index(_arena if _arena != null else get_parent())
	if _arena != null:
		_index_shells()
	for trigger in get_tree().get_nodes_in_group(StreamingTrigger.GROUP):
		if is_ancestor_of(trigger):
			(trigger as StreamingTrigger).fired.connect(_on_fired)
	print("[presence] %d packages in the level, %d governed, %d snapshots" % [_nodes_of.size(), _managed.size(), snapshots.size()])
	reset_for_respawn()


func reset_for_respawn() -> void:
	if _nodes_of.is_empty():
		return
	var label := start
	var checkpoint: Checkpoint = _arena.player.active_checkpoint if _arena != null and _arena.player != null else null
	if checkpoint != null and is_instance_valid(checkpoint):
		label = Arena.checkpoint_label(checkpoint)
	restore(label)


## The level as a restore at that checkpoint finds it. Steps still waiting out
## a delay are dropped: they belong to the life that set them off.
func restore(label: String) -> void:
	_pending.clear()
	set_physics_process(false)
	if not snapshots.has(label):
		push_warning("[presence] no snapshot for checkpoint '%s': the level stays as it is" % label)
		return
	var wanted := {}
	for key: String in snapshots[label]:
		wanted[key] = true
	_become(wanted, "restore " + label)


func is_present(key: String) -> bool:
	return present.has(key) or not _managed.has(key)


## Governed packages that are in the level. `present` alone also counts the
## audio and music packages a snapshot names, which govern nothing here.
func present_count() -> int:
	var count := 0
	for key: String in present:
		count += int(_managed.has(key))
	return count


func _on_fired(trigger: StreamingTrigger) -> void:
	for step: Dictionary in trigger.steps:
		var delay: float = step.get("delay", 0.0)
		if trigger.lift != null:
			delay = 0.0
		elif trigger.pressed:
			delay = maxf(delay, pressed_min_delay)
		_pending.append({at = _clock + delay, order = int(step.get("order", 0)), op = step["op"],
				packages = step["packages"], source = trigger.source})
	_run_due()
	set_physics_process(not _pending.is_empty())


func _physics_process(delta: float) -> void:
	_clock += delta
	_run_due()
	set_physics_process(not _pending.is_empty())


func _run_due() -> void:
	var due: Array[Dictionary] = []
	var later: Array[Dictionary] = []
	for step in _pending:
		(due if step.at <= _clock else later).append(step)
	if due.is_empty():
		return
	_pending = later
	# Unload before load, as the original chains them: `order` is the depth of
	# the Finished chain.
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.at < b.at if a.at != b.at else a.order < b.order)
	var wanted := present.duplicate()
	for step in due:
		for key: String in step.packages:
			if step.op == "load":
				wanted[key] = true
			else:
				wanted.erase(key)
		last_source = step.source
	_become(wanted, due[0].source)


func _become(wanted: Dictionary, why: String) -> void:
	var added: Array[String] = []
	var removed: Array[String] = []
	if not _applied:
		# Nothing has been applied yet and everything is showing: every
		# governed package the snapshot leaves out has to go.
		_applied = true
		for key: String in _managed:
			if not wanted.has(key):
				removed.append(key)
	else:
		for key: String in wanted:
			if not present.has(key):
				added.append(key)
		for key: String in present:
			if not wanted.has(key):
				removed.append(key)
	present = wanted
	if why.begins_with("restore "):
		last_source = why
	for key in removed:
		_show(key, false)
	for key in added:
		_show(key, true)
	if not added.is_empty() or not removed.is_empty():
		print("[presence] %s: +%s -%s, %d present" % [why, added, removed, present.size()])


func _show(key: String, on: bool) -> void:
	if not _managed.has(key):
		return
	for node: Node in _nodes_of.get(key, []):
		if node is Light3D and node.get_parent().has_method("set_present"):
			# Lit a few per frame, as at load: a package's lights drawn for the
			# first time all at once cost seconds.
			node.get_parent().set_present(node, on)
			continue
		if node is Node3D:
			(node as Node3D).visible = on
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _index_shells() -> void:
	for root_name: String in shell_packages:
		var shell: Node = null
		for loader in _arena.find_children("*", "Node3D", false, false):
			if loader is SectionLoader and loader.has_node(NodePath(root_name)):
				shell = loader.get_node(NodePath(root_name))
		if shell == null:
			continue
		var paths: Dictionary = shell_packages[root_name]
		for path: String in paths:
			var node := shell.get_node_or_null(NodePath(path))
			# A shell built since carries the stamp itself and is indexed by it.
			if node != null and not node.has_meta(PACKAGE_META):
				_nodes_of.get_or_add(String(paths[path]), []).append(node)


func _index(node: Node) -> void:
	if node.has_meta(PACKAGE_META):
		_nodes_of.get_or_add(String(node.get_meta(PACKAGE_META)), []).append(node)
		return
	for child in node.get_children():
		_index(child)

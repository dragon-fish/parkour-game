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
## Between checkpoints the level's Kismet loads and unloads as the player
## goes: KismetRunner calls load_packages() and unload_packages() when a
## streaming action fires, and waits for `settled` before the action's
## Finished. Touching a checkpoint on foot takes NO snapshot -- by then Kismet
## has already brought the level there, and the snapshot is what a restore
## loads, not what the player is standing in.
##
## Everything stays instanced. A package that is not present is hidden, its
## scripts stopped (process_mode DISABLED) and its bodies and areas on no
## collision layer. NOT taken out of the physics space, which is what a
## disabled CollisionObject3D does by default: coming back in rebuilds every
## shape, and a level has hulls Jolt cannot build, each failing again for
## 30-47 ms -- four in one frame was a 169 ms hitch. DO NOT free and
## re-instance here without reading docs/seamless-loading.md: _set_node() is
## the one place that would change, and the frame budget is why it has not.
##
## A FEW NODES PER FRAME, NEAREST FIRST. Stormdrain's first lift swaps some
## four thousand nodes; done in one go that was a 286 ms frame in the middle
## of a run. The queue is sorted by distance from the player, so what is
## underfoot and in reach is there on the first frame and the far end of the
## stretch fills in over the next second -- the original took longer to load.

## What came and what went, as package keys. Emitted when the change is
## DECIDED, before a node has been switched: a package's Kismet goes with it.
signal changed(loaded: Array[String], unloaded: Array[String])
## Every node of the last change has been switched.
signal settled
## A restore is about to replace the level, and has. KismetRunner hangs on
## these two rather than on the respawn itself: the packages have to be
## decided BETWEEN its forgetting the old life and its starting the new one,
## and the order of a group call is nothing to build that on.
signal restoring
signal restored(label: String)

## Spelt the same in tools/me_level/me_level_common.gd, which cannot name this
## class: a build runs without the autoloads Arena needs.
const PACKAGE_META := &"me_package"
const GROUP := &"package_presence"
## On a body or area: the layers it was BUILT on, [layer, mask], and what the
## level's Kismet last made of its collision (KismetRunner.COLLIDE_*). Two
## things decide whether it collides -- is its package in the level, and has
## Kismet switched it off -- and both this node and the runner answer with
## collides(). Each writing the layers on its own account, the last writer
## won: a lift's doorway wall, which its package's LevelLoaded switches off,
## was switched back on when the package's nodes were brought in a moment
## later, and nobody could board.
const BUILT_LAYERS_META := &"kismet_layers"
const KISMET_MODE_META := &"kismet_mode"


## Whether a body or area may collide as far as Kismet is concerned: an area
## listens when it touches or blocks, a body is solid only when it blocks.
static func kismet_allows(body: CollisionObject3D) -> bool:
	var mode: int = body.get_meta(KISMET_MODE_META, 2)
	return mode >= 1 if body is Area3D else mode == 2


## Puts a body on its built layers or on none.
static func set_colliding(body: CollisionObject3D, on: bool) -> void:
	if not body.has_meta(BUILT_LAYERS_META):
		body.set_meta(BUILT_LAYERS_META, [body.collision_layer, body.collision_mask])
	var built: Array = body.get_meta(BUILT_LAYERS_META)
	body.collision_layer = built[0] if on else 0
	body.collision_mask = built[1] if on else 0

## Checkpoint label -> packages present after a restore there.
@export var snapshots: Dictionary = {}
## The label that stands for no checkpoint at all: the level's own spawn.
@export var start: String = ""
## Packages this node governs. Any other package is always present.
@export var managed: PackedStringArray = []
## Section shell root name -> {path from that root: {meta name: value}}, for
## shells built before their nodes carried what they came from. Stamped onto
## the nodes when the level opens: see ShellBuilder.origins().
@export var shell_origins: Dictionary = {}
## Nodes switched per frame while a change is under way. A COUNT, not a time:
## what a switch costs is not paid here but when the physics and render
## servers flush it, at about 0.1 ms a node -- 400 a frame measured 46 ms.
@export var nodes_per_frame: int = 64

var present: Dictionary = {}
## For the HUD: what changed the level last.
var last_source: String = ""

var _nodes_of: Dictionary = {}
## Where each indexed node stood when it was indexed, for the queue's order.
## Read once: four thousand global_position calls were most of a 30 ms sort.
var _at: Dictionary = {}
## Indexed node -> the bodies and areas that are it or below it.
var _bodies_of: Dictionary = {}
## Body or area -> the indexed node it belongs to, for is_body_present().
var _owner_of: Dictionary = {}
var _managed: Dictionary = {}
var _applied := false
var _restoring := false
var _begun := false
## Nodes still to be switched, as [node, on], in the order they will be.
var _queue: Array[Array] = []
var _arena: Arena = null


func _ready() -> void:
	add_to_group(Arena.RESET_ON_RESPAWN)
	add_to_group(GROUP)
	set_process(false)
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
	var level: Node = _arena if _arena != null else get_parent()
	_stamp_shells(level)
	_index(level)
	# Only now can an actor be found by name: the shells have their origins,
	# and the bodies are known for is_body_present().
	for child in get_children():
		if child.has_method("bind"):
			child.bind(level)
	_begun = true
	print("[presence] %d packages in the level, %d governed, %d snapshots" % [_nodes_of.size(), _managed.size(), snapshots.size()])
	reset_for_respawn()


func has_begun() -> bool:
	return _begun


func reset_for_respawn() -> void:
	if not _begun:
		return
	var label := start
	var checkpoint: Checkpoint = _arena.player.active_checkpoint if _arena != null and _arena.player != null else null
	if checkpoint != null and is_instance_valid(checkpoint):
		label = Arena.checkpoint_label(checkpoint)
	restore(label)


## The level as a restore at that checkpoint finds it.
func restore(label: String) -> void:
	if not snapshots.has(label):
		push_warning("[presence] no snapshot for checkpoint '%s': the level stays as it is" % label)
		return
	var wanted := {}
	for key: String in snapshots[label]:
		wanted[key] = true
	_restoring = true
	restoring.emit()
	_become(wanted, "restore " + label)
	_restoring = false
	restored.emit(label)


func load_packages(keys: PackedStringArray, why: String) -> void:
	var wanted := present.duplicate()
	for key in keys:
		wanted[key] = true
	_become(wanted, why)


func unload_packages(keys: PackedStringArray, why: String) -> void:
	var wanted := present.duplicate()
	for key in keys:
		wanted.erase(key)
	_become(wanted, why)


func is_present(key: String) -> bool:
	return present.has(key) or not _managed.has(key)


## Whether the package a body belongs to is in the level. A body that belongs
## to none is.
func is_body_present(body: CollisionObject3D) -> bool:
	return not _owner_of.has(body) or is_present(_owner_of[body])


func is_settled() -> bool:
	return _queue.is_empty()


## Governed packages that are in the level. `present` alone also counts the
## audio and music packages a snapshot names, which govern nothing here.
func present_count() -> int:
	var count := 0
	for key: String in present:
		count += int(_managed.has(key))
	return count


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
	last_source = why
	# Arrivals before departures: what is coming is what the player is
	# running at, and a shell lingering a moment longer blocks nobody yet.
	for key in added:
		_enqueue(key, true)
	for key in removed:
		_enqueue(key, false)
	_sort_queue()
	if not added.is_empty() or not removed.is_empty():
		print("[presence] %s: +%s -%s, %d present" % [why, added, removed, present_count()])
		changed.emit(added, removed)
	if _queue.is_empty():
		settled.emit()
		return
	# Holds the loading curtain while the level opens; harmless later.
	add_to_group(Arena.WARMING)
	set_process(true)
	_process(0.0)


func _enqueue(key: String, on: bool) -> void:
	if not _managed.has(key):
		return
	for node: Node in _nodes_of.get(key, []):
		_queue.append([node, on])


## Nearest the player first. A node switched twice keeps only its last word.
func _sort_queue() -> void:
	var last := {}
	for entry in _queue:
		last[entry[0]] = entry[1]
	var focus := _focus()
	var keyed: Array[Array] = []
	for node: Node in last:
		if not is_instance_valid(node):
			continue
		keyed.append([(_at.get(node, focus) as Vector3).distance_squared_to(focus), node, last[node]])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_queue.clear()
	for entry in keyed:
		_queue.append([entry[1], entry[2]])
	_queue.reverse()


func _focus() -> Vector3:
	if _arena != null and _arena.player != null:
		var checkpoint: Checkpoint = _arena.player.active_checkpoint
		# On a respawn this runs before the body is moved: where it is going.
		if _restoring and checkpoint != null and is_instance_valid(checkpoint):
			return checkpoint.global_position
		return _arena.player.global_position
	return global_position


func _process(_delta: float) -> void:
	# From the back: the queue is reversed so that taking one is O(1).
	for i in nodes_per_frame:
		if _queue.is_empty():
			break
		var entry: Array = _queue.pop_back()
		if is_instance_valid(entry[0]):
			_set_node(entry[0], entry[1])
	if _queue.is_empty():
		remove_from_group(Arena.WARMING)
		set_process(false)
		settled.emit()


func _set_node(node: Node, on: bool) -> void:
	if node is Light3D and node.get_parent().has_method("set_present"):
		# Lit a few per frame, as at load: a package's lights drawn for the
		# first time all at once cost seconds.
		node.get_parent().set_present(node, on)
		return
	if node is Node3D:
		(node as Node3D).visible = on
	node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for body: CollisionObject3D in _bodies_of.get(node, []):
		if is_instance_valid(body):
			set_colliding(body, on and kismet_allows(body))


## A shell is edited by hand and not rebuilt, so one written before its nodes
## carried their origin never will by itself: the build reads the origins off
## a shell made in memory, and they are put on the real one's nodes here, by
## path. A node renamed or deleted since simply finds no entry.
func _stamp_shells(level: Node) -> void:
	for root_name: String in shell_origins:
		var shell: Node = null
		for loader in level.find_children("*", "Node3D", false, false):
			if loader is SectionLoader and loader.has_node(NodePath(root_name)):
				shell = loader.get_node(NodePath(root_name))
		if shell == null:
			continue
		var origins: Dictionary = shell_origins[root_name]
		for path: String in origins:
			var node := shell.get_node_or_null(NodePath(path))
			if node == null:
				continue
			for meta: String in origins[path]:
				if not node.has_meta(meta):
					node.set_meta(meta, origins[path][meta])


func _register(key: String, node: Node) -> void:
	_nodes_of.get_or_add(key, []).append(node)
	if node is Node3D:
		_at[node] = (node as Node3D).global_position
	var bodies: Array = []
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var at: Node = todo.pop_back()
		if at is CollisionObject3D:
			var body := at as CollisionObject3D
			body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			bodies.append(body)
		todo.append_array(at.get_children())
	if not bodies.is_empty():
		_bodies_of[node] = bodies
		for body: CollisionObject3D in bodies:
			_owner_of[body] = key


func _index(node: Node) -> void:
	if node.has_meta(PACKAGE_META):
		_register(String(node.get_meta(PACKAGE_META)), node)
		return
	for child in node.get_children():
		_index(child)

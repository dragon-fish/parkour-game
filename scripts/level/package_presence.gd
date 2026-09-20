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
## Everything stays instanced. A package that is not present is hidden, its
## scripts stopped (process_mode DISABLED) and its bodies and areas on no
## collision layer. NOT taken out of the physics space, which is what a
## disabled CollisionObject3D does by default: coming back in rebuilds every
## shape, and a level has hulls Jolt cannot build, each failing again for
## 30-47 ms -- four in one frame was a 169 ms hitch. DO NOT free and re-instance here without
## reading docs/seamless-loading.md: _set_node() is the one place that would
## change, and the frame budget is why it has not.
##
## A FEW NODES PER FRAME, NEAREST FIRST. Stormdrain's first lift swaps some
## four thousand nodes; done in one go that was a 286 ms frame in the middle
## of a run. The queue is sorted by distance from the player, so what is
## underfoot and in reach is there on the first frame and the far end of the
## stretch fills in over the next second -- the original took longer to load.

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
## Nodes switched per frame while a change is under way. A COUNT, not a time:
## what a switch costs is not paid here but when the physics and render
## servers flush it, at about 0.1 ms a node -- 400 a frame measured 46 ms.
@export var nodes_per_frame: int = 64

var present: Dictionary = {}
## For the HUD: what fired last.
var last_source: String = ""

var _nodes_of: Dictionary = {}
## Where each indexed node stood when it was indexed, for the queue's order.
## Read once: four thousand global_position calls were most of a 30 ms sort.
var _at: Dictionary = {}
## Indexed node -> [[CollisionObject3D, layer, mask], ...] of it and below it,
## with the layers they were built on.
var _bodies_of: Dictionary = {}
var _managed: Dictionary = {}
var _applied := false
var _restoring := false
## Steps waiting out their delay: {at: seconds, order, op, packages, source}.
var _pending: Array[Dictionary] = []
## Nodes still to be switched, as [node, on], in the order they will be.
var _queue: Array[Array] = []
var _clock: float = 0.0
var _arena: Arena = null


func _ready() -> void:
	add_to_group(Arena.RESET_ON_RESPAWN)
	add_to_group(GROUP)
	set_physics_process(false)
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
	_restoring = true
	_restore(label)
	_restoring = false


func _restore(label: String) -> void:
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
	# Arrivals before departures: what is coming is what the player is
	# running at, and a shell lingering a moment longer blocks nobody yet.
	for key in added:
		_enqueue(key, true)
	for key in removed:
		_enqueue(key, false)
	_sort_queue()
	if not _queue.is_empty():
		# Holds the loading curtain while the level opens; harmless later.
		add_to_group(Arena.WARMING)
		set_process(true)
		_process(0.0)
	if not added.is_empty() or not removed.is_empty():
		print("[presence] %s: +%s -%s, %d present" % [why, added, removed, present.size()])


func _enqueue(key: String, on: bool) -> void:
	if not _managed.has(key):
		return
	for node: Node in _nodes_of.get(key, []):
		_queue.append([node, on])


## Nearest the player first, arrivals before departures at equal distance.
## A node switched twice keeps only its last word.
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


func _set_node(node: Node, on: bool) -> void:
	if node is Light3D and node.get_parent().has_method("set_present"):
		# Lit a few per frame, as at load: a package's lights drawn for the
		# first time all at once cost seconds.
		node.get_parent().set_present(node, on)
		return
	if node is Node3D:
		(node as Node3D).visible = on
	node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for entry: Array in _bodies_of.get(node, []):
		var body: CollisionObject3D = entry[0]
		if is_instance_valid(body):
			body.collision_layer = entry[1] if on else 0
			body.collision_mask = entry[2] if on else 0


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
				_register(String(paths[path]), node)


func _register(key: String, node: Node) -> void:
	_nodes_of.get_or_add(key, []).append(node)
	if node is Node3D:
		# A trigger stands at the origin; its zone is where it is.
		var placed := node as Node3D
		if node is StreamingTrigger and node.get_child_count() > 0 and node.get_child(0) is Node3D:
			placed = node.get_child(0)
		_at[node] = placed.global_position
	var bodies: Array = []
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var at: Node = todo.pop_back()
		if at is CollisionObject3D:
			var body := at as CollisionObject3D
			body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			bodies.append([body, body.collision_layer, body.collision_mask])
		todo.append_array(at.get_children())
	if not bodies.is_empty():
		_bodies_of[node] = bodies


func _index(node: Node) -> void:
	if node.has_meta(PACKAGE_META):
		_register(String(node.get_meta(PACKAGE_META)), node)
		return
	for child in node.get_children():
		_index(child)

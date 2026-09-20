class_name KismetRunner
extends Node3D

## Runs a chapter's Kismet -- the original's visual script -- as the original
## did, from the graph the extractor's kismet.py writes.
##
## WHY A RUNNER AND NOT FACTS READ OUT OF THE GRAPH. The graph holds state: a
## Gate is shut until a touch further on opens it, a Switch's outlet is an Int
## some other node sets, a steel door waits for a load's Finished. Read as
## though it held none -- "which button unloads this stretch?" -- a button
## unloaded the floor the player stood on. Every such question is answered
## here by running the thing, and nowhere by walking it.
##
## The model is UE3's: a node is activated on one of its INPUTS and fires its
## OUTPUTS, each wired to inputs of other nodes. Most finish at once; a few are
## latent (Delay, Interp, streaming) and fire later. Everything a node needs to
## remember is in _state[node id], which is what makes forgetting cheap:
##
##   * A package's Kismet exists only while the package is loaded. Unloading
##     one forgets its nodes' state and drops what they had pending;
##     loading one fires its LevelLoaded events. [ME:CONFIRMED] Stormdrain
##     re-arms its doors this way.
##   * A respawn forgets everything, lets PackagePresence take the snapshot,
##     then starts the level again and fires the checkpoint's own
##     TdCheckpointLoaded, which is how the original puts a level back.
##
## WHAT A NODE MEANS lives in _run(), one class at a time. A class with no
## entry there passes the signal straight on (its first output, and any
## Finished), which is right for the hundred kinds that have nothing to act on
## here -- AI, sound, weapons, camera -- and is counted, so what is missing
## can be read off `unknown` rather than guessed at.
##
## Defaults are UE3's class defaults, NOT zero: a cooked export holds only what
## differs from them. MaxTriggerCount is 1 (an event fires ONCE unless it says
## 0), a Gate is open, a Delay is one second.

const GROUP := &"kismet_runner"
const ACTOR_META := &"me_actor"
const MATINEE_META := &"me_matinee"

## A tick that fires this many activations is a loop in the data, not a level.
const MAX_ACTIVATIONS_PER_TICK := 20000

const TOUCH := ["SeqEvent_Touch", "SeqEvent_TdTouch"]
const USED := ["SeqEvent_Used", "SeqEvent_TdUsed"]
const DAMAGED := ["SeqEvent_TakeDamage"]
const LEVEL_START := ["SeqEvent_LevelLoaded", "SeqEvent_LevelStartup", "SeqEvent_LevelBeginning"]
## [ME:CONFIRMED] no jump, no crouch and walking pace in a lift car; the
## original says so with SeqAct_TdInElevator on the car's button.
const LIFT_SUBJECT := &"kismet_lift"
const LIFT_SPEED_M_S := 4.0

## The graph: a KismetGraph resource, kept out of the scene text.
@export var graph: KismetGraph
## Checkpoint label -> the TdCheckpoint actor it was made from.
@export var checkpoint_actors: Dictionary = {}
## Every package something streams, geometry or not. A package not named here
## is the chapter's own and always loaded.
@export var streamed: PackedStringArray = []
## Print every activation. Loud: a chapter fires hundreds on a button.
@export var trace: bool = false

## Class -> how often a class with no meaning here was passed through.
var unknown: Dictionary = {}

var _nodes: Dictionary = {}
var _vars: Dictionary = {}
var _state: Dictionary = {}
var _var_values: Dictionary = {}
## Lower-case event name -> ids of the SeqEvent_RemoteEvents listening for it.
var _listeners: Dictionary = {}
## Actor id -> ids of the events it originates.
var _events_of: Dictionary = {}
## Actor id -> nodes built from that actor.
var _actors: Dictionary = {}
## Matinee name (kismet.py's `matinee`) -> the Matinee node playing it.
var _matinees: Dictionary = {}
## Variable name -> ids of the variables carrying it.
var _named: Dictionary = {}
var _by_class: Dictionary = {}
var _streamed: Dictionary = {}
## Actor id -> {flag: value} for what Kismet has changed, so a respawn can put
## it back and a Toggle can know what it is toggling.
var _touched_state: Dictionary = {}
## Waiting: {at, node, output} fires an output, {at, node, input} activates.
var _timers: Array[Dictionary] = []
## Interp ids in motion.
var _playing: Dictionary = {}
## Streaming actions waiting for the level to settle, in order.
var _loading: Array[String] = []
var _queue: Array[Array] = []
var _clock: float = 0.0
var _presence: PackagePresence = null
var _running := false
var _starts := 0
var _activations := 0


func _ready() -> void:
	add_to_group(GROUP)
	if graph == null:
		return
	_nodes = graph.nodes
	_vars = graph.variables
	for key in streamed:
		_streamed[key] = true
	for id: String in _nodes:
		var node: Dictionary = _nodes[id]
		_by_class.get_or_add(node["cls"], []).append(id)
		if node["cls"] == "SeqEvent_RemoteEvent":
			_listeners.get_or_add(str(_prop(node, "EventName", "")).to_lower(), []).append(id)
		if node.has("originator"):
			_events_of.get_or_add(node["originator"], []).append(id)
	for id: String in _vars:
		if _vars[id].has("name"):
			_named.get_or_add(_vars[id]["name"], []).append(id)
	_presence = get_parent() as PackagePresence
	if _presence == null:
		_presence = get_tree().get_first_node_in_group(PackagePresence.GROUP) as PackagePresence
	if _presence != null:
		_presence.restoring.connect(_forget_everything)
		_presence.restored.connect(_start_level)
		_presence.changed.connect(_on_packages_changed)
		_presence.settled.connect(_on_settled)


## Called once the level's nodes carry their origins: PackagePresence stamps
## the shells, and only then can an actor be found by name.
func bind(level: Node) -> void:
	_actors.clear()
	_matinees.clear()
	var todo: Array[Node] = [level]
	while not todo.is_empty():
		var node: Node = todo.pop_back()
		if node.has_meta(ACTOR_META):
			_actors.get_or_add(String(node.get_meta(ACTOR_META)), []).append(node)
		if node.has_meta(MATINEE_META) and node is Matinee:
			_matinees[String(node.get_meta(MATINEE_META))] = node
		todo.append_array(node.get_children())
	for id: String in _by_class.get("SeqAct_Interp", []):
		var matinee: Matinee = _matinees.get(_nodes[id].get("matinee", ""))
		if matinee != null:
			matinee.take_over()
	for actor: String in _events_of:
		for node: Node in _actors.get(actor, []):
			_listen(actor, node)
	for actor: String in _actors:
		if graph.actors.get(actor, {}).get("starts_off", false):
			for node: Node in _actors[actor]:
				_set_layers(node, COLLIDE_NONE)
	print("[kismet] %d nodes, %d actors found of %d named, %d matinees driven" % [
		_nodes.size(), _actors.size(), graph.actors.size(), _matinees.size()])


func _listen(actor: String, node: Node) -> void:
	if node is UseZone:
		(node as UseZone).used.connect(_on_used.bind(actor))
	if node is Area3D:
		(node as Area3D).body_entered.connect(_on_touch.bind(actor, true))
		(node as Area3D).body_exited.connect(_on_touch.bind(actor, false))


## For the debug HUD.
func status_line() -> String:
	return "%d waiting  %d playing  %d loading  %d kinds passed through" % [
		_timers.size(), _playing.size(), _loading.size(), unknown.size()]


# ---------------------------------------------------------------- lifecycle

func _forget_everything() -> void:
	_running = false
	_state.clear()
	_var_values.clear()
	_timers.clear()
	_queue.clear()
	_loading.clear()
	for id: String in _playing:
		_drive_matinee(id, "reset")
	_playing.clear()
	for actor: String in _touched_state:
		_restore_actor(actor)
	_touched_state.clear()
	_set_lift_rules(false)


func _start_level(label: String) -> void:
	_running = true
	_starts += 1
	for id: String in _nodes:
		var cls: String = _nodes[id]["cls"]
		# LevelReset is the original's own word for a respawn.
		if (cls in LEVEL_START or (cls == "SeqEvent_LevelReset" and _starts > 1)) and _is_loaded(_nodes[id]["package"]):
			_fire_event(id, ["Loaded and Visible", "Out"])
	var actor: String = checkpoint_actors.get(label, "")
	for id: String in _events_of.get(actor, []):
		if _nodes[id]["cls"] == "SeqEvt_TdCheckpointLoaded":
			_fire_event(id, [])
	_drain()


func _on_packages_changed(loaded: Array[String], unloaded: Array[String]) -> void:
	if not _running:
		return
	for key in unloaded:
		_forget_package(key)
	for key in loaded:
		for id: String in _nodes:
			if _nodes[id]["package"] == key and _nodes[id]["cls"] in LEVEL_START:
				_fire_event(id, ["Loaded and Visible", "Out"])
	_drain()


func _forget_package(key: String) -> void:
	for id: String in _state.keys():
		if _nodes[id]["package"] == key:
			_state.erase(id)
	for id: String in _var_values.keys():
		if String(id).begins_with(key + "#"):
			_var_values.erase(id)
	_timers = _timers.filter(func(t: Dictionary) -> bool: return _nodes[t.node]["package"] != key)
	for id: String in _playing.keys():
		if _nodes[id]["package"] == key:
			_drive_matinee(id, "reset")
			_playing.erase(id)


func _is_loaded(key: String) -> bool:
	if not _streamed.has(key) or _presence == null:
		return true
	return _presence.present.has(key)


# ------------------------------------------------------------------- events

func _on_touch(body: Node3D, actor: String, entered: bool) -> void:
	# Duck-typed like Checkpoint: whatever can touch a checkpoint is a player.
	if not _running or not body.has_method("touch_checkpoint"):
		return
	for id: String in _events_of.get(actor, []):
		if _nodes[id]["cls"] in TOUCH:
			_fire_event(id, ["Touched"] if entered else ["UnTouched"], not entered)
		elif entered and _nodes[id]["cls"] in DAMAGED:
			_fire_event(id, [])
	_drain()


func _on_used(actor: String) -> void:
	if not _running:
		return
	for id: String in _events_of.get(actor, []):
		if _nodes[id]["cls"] in USED:
			# TdUsed is held: Started, then Finished. This project's press is
			# the dwell in the zone, already over when it arrives here.
			_fire_event(id, ["Used", "Started", "Finished"])
	_drain()


## Fires an event's named outputs (all of them when `names` is empty), if the
## event is enabled, loaded, and has triggers left. `free` fires do not count
## against MaxTriggerCount: an UnTouch is the tail of the Touch that did.
func _fire_event(id: String, names: Array, free: bool = false) -> void:
	var node: Dictionary = _nodes[id]
	if not _is_loaded(node["package"]):
		return
	var state: Dictionary = _state.get_or_add(id, {})
	if not state.get("enabled", _prop(node, "bEnabled", true)):
		return
	if not free:
		var limit: int = int(_prop(node, "MaxTriggerCount", 1))
		if limit > 0 and state.get("count", 0) >= limit:
			return
		if _clock < state.get("again_at", 0.0):
			return
		state["count"] = state.get("count", 0) + 1
		state["again_at"] = _clock + float(_prop(node, "ReTriggerDelay", 0.0))
	if trace:
		print("[kismet] EVENT %s %s %s" % [id, node["cls"], node.get("originator", "")])
	var fired := false
	for i in (node["outs"] as Array).size():
		if names.is_empty() or names.has(node["outs"][i]["name"]):
			_fire(id, i)
			fired = true
	if not fired and not names.is_empty() and not (node["outs"] as Array).is_empty() and names[0] != "UnTouched":
		_fire(id, 0)


# ---------------------------------------------------------------- the engine

func _physics_process(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	_activations = 0
	if not _timers.is_empty():
		var due: Array[Dictionary] = []
		var later: Array[Dictionary] = []
		for timer in _timers:
			(due if timer.at <= _clock else later).append(timer)
		_timers = later
		for timer in due:
			if timer.has("output"):
				_fire(timer.node, timer.output, false)
			else:
				_queue.append([timer.node, timer.input])
	for id: String in _playing.keys():
		_advance_interp(id, delta)
	_drain()


func _drain() -> void:
	while not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_activations += 1
		if _activations > MAX_ACTIVATIONS_PER_TICK:
			push_error("[kismet] %d activations in one tick: a loop with no delay in it, at %s" % [_activations, next[0]])
			_queue.clear()
			return
		_activate(next[0], next[1])


## Fires one output of a node: every input wired to it is activated, after the
## output's own ActivateDelay if it has one.
func _fire(id: String, output: int, honour_delay: bool = true) -> void:
	var outs: Array = _nodes[id]["outs"]
	if output < 0 or output >= outs.size():
		return
	var out: Dictionary = outs[output]
	if out.get("disabled", false) or _state.get(id, {}).get("off_outs", {}).has(output):
		return
	if honour_delay and float(out.get("delay", 0.0)) > 0.0:
		_timers.append({at = _clock + float(out["delay"]), node = id, output = output})
		return
	for link: Array in out["to"]:
		_queue.append([link[0], int(link[1])])


func _fire_named(id: String, names: Array) -> bool:
	var outs: Array = _nodes[id]["outs"]
	for i in outs.size():
		if names.has(outs[i]["name"]):
			_fire(id, i)
			return true
	return false


func _activate(id: String, input: int) -> void:
	var node: Dictionary = _nodes.get(id, {})
	if node.is_empty() or not _is_loaded(node["package"]):
		return
	if trace:
		var ins: Array = node["ins"]
		print("[kismet]   %s %s <- %s  %s" % [id, node["cls"], ins[input] if input < ins.size() else input, node.get("comment", "")])
	_run(id, node, input, _state.get_or_add(id, {}))


func _run(id: String, node: Dictionary, input: int, state: Dictionary) -> void:
	match node["cls"]:
		"SeqAct_Gate":
			# In, Open, Close, Toggle.
			var open: bool = state.get("open", _prop(node, "bOpen", true))
			match input:
				1: open = true
				2: open = false
				3: open = not open
				_:
					if open:
						var closes_after: int = int(_prop(node, "AutoCloseCount", 0))
						state["passed"] = state.get("passed", 0) + 1
						if closes_after > 0 and state["passed"] >= closes_after:
							open = false
							state["passed"] = 0
						_fire(id, 0)
			state["open"] = open
		"SeqAct_Switch":
			_run_switch(id, node, state)
		"SeqAct_RandomSwitch":
			_run_random_switch(id, node, state)
		"SeqAct_Delay":
			# Start, Stop, Pause. Out: Finished, Aborted.
			if input == 0:
				if not state.get("waiting", false):
					state["waiting"] = true
					state["serial"] = state.get("serial", 0) + 1
					_timers.append({at = _clock + _number(node, "Duration", float(_prop(node, "Duration", 1.0))),
							node = id, input = 100 + int(state["serial"])})
			elif input == 1:
				if state.get("waiting", false):
					state["waiting"] = false
					_fire(id, 1)
			elif input >= 100:
				# The timer set above coming home; a stopped Delay ignores it.
				if state.get("waiting", false) and input == 100 + int(state.get("serial", 0)):
					state["waiting"] = false
					_fire(id, 0)
		"SeqAct_ActivateRemoteEvent":
			for listener: String in _listeners.get(str(_prop(node, "EventName", "")).to_lower(), []):
				_fire_event(listener, [])
			_fire(id, 0)
		"Sequence":
			# Activated on an input: that input's SequenceActivated, inside.
			var ports: Array = node.get("ports", [])
			if input < ports.size() and ports[input] != null:
				_fire_event(ports[input], [])
		"SeqAct_FinishSequence":
			var parent: Dictionary = _nodes.get(node.get("sequence", ""), {})
			for i in (parent.get("outs", []) as Array).size():
				if parent["outs"][i].get("from", "") == id:
					_fire(node["sequence"], i)
		"SeqAct_Interp":
			_run_interp(id, node, input, state)
		"SeqAct_MultiLevelStreaming", "SeqAct_LevelStreaming":
			_run_streaming(id, node, input)
		"SeqAct_Toggle":
			# Turn On, Turn Off, Toggle.
			for actor: String in _targets(node, "Target"):
				var on: bool = input == 0 or (input == 2 and not _actor_on(actor))
				_set_actor(actor, "on", int(on))
			for event: String in node.get("events", []):
				var event_state: Dictionary = _state.get_or_add(event, {})
				var enabled: bool = event_state.get("enabled", _prop(_nodes.get(event, {}), "bEnabled", true))
				event_state["enabled"] = input == 0 or (input == 2 and not enabled)
			for variable: String in node.get("vars", {}).get("Bool", []):
				_set_value(variable, input == 0 or (input == 2 and not bool(_value(variable, false))))
			_fire(id, 0)
		"SeqAct_ToggleHidden":
			# Hide, UnHide, Toggle.
			for actor: String in _targets(node, "Target"):
				var shown: bool = input == 1 or (input == 2 and not bool(_actor_flag(actor, "shown", 1)))
				_set_actor(actor, "shown", int(shown))
			_fire(id, 0)
		"SeqAct_ChangeCollision":
			# CollisionType ALONE. The node also carries bCollideActors and
			# bBlockActors, left over from before the enum and still written
			# `true` beside COLLIDE_NoCollision: read, they turned the steam
			# ON where the level turns it off. Unwritten, the type is
			# COLLIDE_CustomDefault -- the actor's class default, which for
			# every kind switched here is "blocks".
			var mode: int = COLLISION_MODES.get(str(_prop(node, "CollisionType", "COLLIDE_CustomDefault")), COLLIDE_BLOCK)
			for actor: String in _targets(node, "Target"):
				_set_actor(actor, "collision", mode)
			_fire(id, 0)
		"SeqAct_Destroy":
			for actor: String in _targets(node, "Target"):
				_set_actor(actor, "shown", 0)
				_set_actor(actor, "collision", COLLIDE_NONE)
			_fire(id, 0)
		"SeqAct_TdInElevator":
			# Enter, Exit.
			_set_lift_rules(input == 0)
			_fire(id, 0)
		"SeqAct_SetBool", "SeqAct_SetInt", "SeqAct_SetFloat", "SeqAct_SetString":
			var source: Array = node.get("vars", {}).get("Value", [])
			var value: Variant = _value(source[0], null) if not source.is_empty() else _prop(node, "DefaultValue", _prop(node, "Value", null))
			for variable: String in node.get("vars", {}).get("Target", []):
				_set_value(variable, value)
			_fire(id, 0)
		"SeqCond_CompareBool":
			var flags: Array = node.get("vars", {}).get("Bool", [])
			var truth: bool = not flags.is_empty()
			for variable: String in flags:
				truth = truth and bool(_value(variable, false))
			_fire_named(id, ["True"] if truth else ["False"])
		"SeqCond_CompareInt", "SeqCond_CompareFloat":
			_compare(id, _number(node, "A", float(_prop(node, "ValueA", 0.0))), _number(node, "B", float(_prop(node, "ValueB", 0.0))))
		"SeqCond_IncrementInt", "SeqCond_IncrementFloat":
			var a: float = _number(node, "A", float(_prop(node, "ValueA", 0.0))) + float(_prop(node, "IncrementAmount", 1.0))
			for variable: String in node.get("vars", {}).get("A", []):
				_set_value(variable, a)
			_compare(id, a, _number(node, "B", float(_prop(node, "ValueB", 0.0))))
		_:
			if not node["cls"].begins_with("SeqEvent") and not node["cls"].begins_with("SeqEvt"):
				unknown[node["cls"]] = unknown.get(node["cls"], 0) + 1
				# Whatever it would have done is not done here, and the level
				# goes on as though it had been: the first output, and the one
				# a latent action would have fired when it was through.
				_fire(id, 0)
				var outs: Array = node["outs"]
				for i in range(1, outs.size()):
					if outs[i]["name"] in ["Finished", "Completed"]:
						_fire(id, i)


func _compare(id: String, a: float, b: float) -> void:
	var outs: Array = _nodes[id]["outs"]
	for i in outs.size():
		var holds := false
		match str(outs[i]["name"]).replace(" ", ""):
			"A<=B": holds = a <= b
			"A>B": holds = a > b
			"A==B": holds = is_equal_approx(a, b)
			"A<B": holds = a < b
			"A>=B": holds = a >= b
		if holds:
			_fire(id, i)


## [ME:INFERRED from UE3's SeqAct_Switch] fires output `index`, then moves the
## index on by IncrementAmount; past LinkCount it wraps when bLooping and
## otherwise stays past the end, firing nothing more. The index is the linked
## Int when there is one, which is how a level routes a signal: IncrementAmount
## 0 and a SetInt somewhere else.
func _run_switch(id: String, node: Dictionary, state: Dictionary) -> void:
	var count: int = int(_prop(node, "LinkCount", (node["outs"] as Array).size()))
	var linked: Array = node.get("vars", {}).get("Index", [])
	var index: int = int(_value(linked[0], 1)) if not linked.is_empty() else int(state.get("index", 1))
	if index >= 1 and index <= count:
		_fire(id, index - 1)
		if _prop(node, "bAutoDisableLinks", false):
			state.get_or_add("off_outs", {})[index - 1] = true
	index += int(_prop(node, "IncrementAmount", 1))
	if index > count and _prop(node, "bLooping", false):
		index = 1
	state["index"] = index
	for variable: String in linked:
		_set_value(variable, index)


func _run_random_switch(id: String, node: Dictionary, state: Dictionary) -> void:
	var count: int = int(_prop(node, "LinkCount", (node["outs"] as Array).size()))
	var off: Dictionary = state.get_or_add("off_outs", {})
	var free: Array[int] = []
	for i in count:
		if not off.has(i):
			free.append(i)
	if free.is_empty():
		if not _prop(node, "bLooping", false):
			return
		off.clear()
		for i in count:
			free.append(i)
	var pick: int = free[randi() % free.size()]
	if _prop(node, "bAutoDisableLinks", false):
		off[pick] = true
	_fire(id, pick)


# ----------------------------------------------------------------- matinees

## Play, Reverse, Stop, Pause, Change Dir. Out: Completed, then the one a
## REVERSE ends on -- labelled "Aborted" in this build of the engine and
## "Reversed" in later ones, and the second output in both. [ME:CONFIRMED
## Stormdrain] a steel door is `Completed -> Delay -> Switch -> Reverse`: with
## the way back ending on Completed too, the door opened again the moment it
## had shut, onto a hall that was still loading. Stop fires nothing.
##
## The position is kept HERE, whether
## or not a Matinee node shows it: a sequence with nothing to move (a lift this
## project runs by hand, a camera, a sound) still takes its time and still
## fires its event track, and the rest of the level waits on both.
func _run_interp(id: String, node: Dictionary, input: int, state: Dictionary) -> void:
	var length: float = float(node.get("length", 0.0))
	var at: float = state.get("at", 0.0)
	match input:
		0:
			if at >= length or _prop(node, "bRewindOnPlay", false):
				at = 0.0
			state["direction"] = 1
			_drive_matinee(id, "play")
		1:
			if at <= 0.0:
				_fire(id, 1)
				return
			state["direction"] = -1
			_drive_matinee(id, "reverse")
		2:
			state["direction"] = 0
			_playing.erase(id)
			_drive_matinee(id, "stop")
			return
		3:
			state["direction"] = 0
			_playing.erase(id)
			_drive_matinee(id, "stop")
			return
		4:
			state["direction"] = -int(state.get("direction", 1))
			_drive_matinee(id, "play" if state["direction"] > 0 else "reverse")
	state["at"] = at
	_playing[id] = true
	_interp_events(id, node, at, at, int(state["direction"]), true)


func _advance_interp(id: String, delta: float) -> void:
	var node: Dictionary = _nodes[id]
	var state: Dictionary = _state.get_or_add(id, {})
	var direction: int = state.get("direction", 0)
	if direction == 0:
		_playing.erase(id)
		return
	var length: float = float(node.get("length", 0.0))
	var before: float = state.get("at", 0.0)
	var after: float = clampf(before + delta * float(_prop(node, "PlayRate", 1.0)) * direction, 0.0, length)
	state["at"] = after
	_interp_events(id, node, before, after, direction, false)
	if direction > 0 and after >= length:
		if _prop(node, "bLooping", false):
			state["at"] = 0.0
			_drive_matinee(id, "play")
			return
		state["direction"] = 0
		_playing.erase(id)
		_fire_named(id, ["Completed"])
	elif direction < 0 and after <= 0.0:
		state["direction"] = 0
		_playing.erase(id)
		_fire(id, 1)


## Event-track keys crossed going from `before` to `after`. A key AT the
## starting position fires on the start itself (`starting`), and not again.
func _interp_events(id: String, node: Dictionary, before: float, after: float, direction: int, starting: bool) -> void:
	for key: Dictionary in node.get("events_at", []):
		if not key["forwards" if direction > 0 else "backwards"]:
			continue
		var time: float = key["time"]
		var crossed: bool
		if starting:
			crossed = is_equal_approx(time, before)
		elif direction > 0:
			crossed = time > before and time <= after
		else:
			crossed = time < before and time >= after
		if crossed:
			var outs: Array = node["outs"]
			for i in outs.size():
				if str(outs[i]["name"]).to_lower() == str(key["name"]).to_lower():
					_fire(id, i)


func _drive_matinee(id: String, action: String) -> void:
	var matinee: Matinee = _matinees.get(_nodes[id].get("matinee", ""))
	if matinee != null and is_instance_valid(matinee):
		matinee.drive(action)


# ---------------------------------------------------------------- streaming

## Load, Unload. Finished fires when the level has SETTLED, not when the
## change is decided: [ME:CONFIRMED] Stormdrain opens its steel door on the
## pillar hall's Finished, and a door opening onto a hall still filling in is
## the original's loading hitch without its reason.
func _run_streaming(id: String, node: Dictionary, input: int) -> void:
	var keys := PackedStringArray(node.get("levels", []))
	if _presence != null:
		if input == 0:
			_presence.load_packages(keys, id)
		else:
			_presence.unload_packages(keys, id)
	if _presence == null or _presence.is_settled():
		_fire_named(id, ["Finished"])
	else:
		_loading.append(id)


func _on_settled() -> void:
	if not _running or _loading.is_empty():
		return
	var done := _loading.duplicate()
	_loading.clear()
	for id in done:
		_fire_named(id, ["Finished"])
	_drain()


# ------------------------------------------------------------------- actors

func _actor_flag(actor: String, flag: String, fallback: int) -> int:
	return _touched_state.get(actor, {}).get(flag, fallback)


func _actor_on(actor: String) -> bool:
	var starts_on: bool = not graph.actors.get(actor, {}).get("starts_off", false)
	return bool(_actor_flag(actor, "on", int(starts_on)))


## `on` is a Toggle (a volume hurts or does not, a light shines or does not, a
## trigger listens or does not), `shown` a ToggleHidden, `collision` a
## ChangeCollision with one of COLLIDE_NONE, COLLIDE_TOUCH, COLLIDE_BLOCK.
func _set_actor(actor: String, flag: String, value: int) -> void:
	_touched_state.get_or_add(actor, {})[flag] = value
	for node: Node in _actors.get(actor, []):
		if not is_instance_valid(node):
			continue
		match flag:
			"shown":
				_set_shown(node, bool(value))
			"collision":
				_set_layers(node, value)
			"on":
				if node is Light3D or node is GPUParticles3D or node is CPUParticles3D:
					(node as Node3D).visible = bool(value)
				else:
					_set_layers(node, COLLIDE_BLOCK if value else COLLIDE_NONE)


func _restore_actor(actor: String) -> void:
	var starts_off: bool = graph.actors.get(actor, {}).get("starts_off", false)
	for node: Node in _actors.get(actor, []):
		if not is_instance_valid(node):
			continue
		_set_shown(node, true, true)
		_set_layers(node, COLLIDE_NONE if starts_off else COLLIDE_BLOCK)


## A placement's picture is its Mesh child, and one the original starts hidden
## has the CHILD hidden, the node itself left visible for the editor: showing
## the node showed nothing. What the child started as is kept on it, for the
## respawn.
func _set_shown(node: Node, shown: bool, restore: bool = false) -> void:
	var picture := node.get_node_or_null("Mesh") as Node3D
	if picture == null:
		picture = node as Node3D
	if picture == null:
		return
	if not picture.has_meta(&"kismet_shown"):
		picture.set_meta(&"kismet_shown", picture.visible)
	picture.visible = picture.get_meta(&"kismet_shown") if restore else shown


## COLLIDE_NONE, COLLIDE_TOUCH or COLLIDE_BLOCK, as UE3's ECollisionType sorts them for a player: a
## body is solid only when it BLOCKS, an area listens when it blocks or
## touches. COLLIDE_BlockWeapons blocks bullets and lets the player through.
## The layers a node was built on are kept on it the first time they change,
## so that this and PackagePresence agree on what "back" means.
const COLLIDE_NONE := 0
const COLLIDE_TOUCH := 1
const COLLIDE_BLOCK := 2
const COLLISION_MODES := {
	"COLLIDE_CustomDefault": COLLIDE_BLOCK, "COLLIDE_NoCollision": COLLIDE_NONE,
	"COLLIDE_BlockAll": COLLIDE_BLOCK, "COLLIDE_BlockAllButWeapons": COLLIDE_BLOCK,
	"COLLIDE_BlockWeapons": COLLIDE_NONE, "COLLIDE_BlockWeaponsKickable": COLLIDE_NONE,
	"COLLIDE_TouchAll": TOUCH, "COLLIDE_TouchAllButWeapons": TOUCH, "COLLIDE_TouchWeapons": COLLIDE_NONE,
}


func _set_layers(node: Node, mode: int) -> void:
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var at: Node = todo.pop_back()
		if at is CollisionObject3D:
			var body := at as CollisionObject3D
			if not body.has_meta(&"kismet_layers"):
				body.set_meta(&"kismet_layers", [body.collision_layer, body.collision_mask])
			var layers: Array = body.get_meta(&"kismet_layers")
			var on: bool = mode >= COLLIDE_TOUCH if body is Area3D else mode == COLLIDE_BLOCK
			body.collision_layer = layers[0] if on else 0
			body.collision_mask = layers[1] if on else 0
		todo.append_array(at.get_children())


func _set_lift_rules(on: bool) -> void:
	var player: Node = _player()
	if player == null or not player.has_method("apply_status"):
		return
	for effect in [Status.Effect.BLOCK_JUMP, Status.Effect.BLOCK_CROUCH, Status.Effect.SPEED_LIMIT]:
		if not on:
			player.remove_status(effect, LIFT_SUBJECT)
			continue
		var spec := StatusSpec.new()
		spec.effect = effect
		spec.subject = LIFT_SUBJECT
		if effect == Status.Effect.SPEED_LIMIT:
			spec.amount = LIFT_SPEED_M_S
		player.apply_status(spec, self, 0)


func _player() -> Node:
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	return (node as Arena).player if node != null else null


# ---------------------------------------------------------------- variables

func _prop(node: Dictionary, key: String, fallback: Variant) -> Variant:
	return node.get("props", {}).get(key, fallback)


func _targets(node: Dictionary, link: String) -> Array[String]:
	var out: Array[String] = []
	for variable: String in node.get("vars", {}).get(link, []):
		var resolved: Dictionary = _vars.get(_resolve(variable), {})
		if resolved.get("actor") != null:
			out.append(resolved["actor"])
		for actor in resolved.get("actors", []):
			out.append(actor)
	return out


## A SeqVar_Named stands for the variable that carries that name.
func _resolve(variable: String) -> String:
	var entry: Dictionary = _vars.get(variable, {})
	if entry.get("cls", "") != "SeqVar_Named":
		return variable
	var package: String = variable.get_slice("#", 0)
	var found: Array = _named.get(entry.get("find", ""), [])
	for candidate: String in found:
		if candidate.begins_with(package + "#"):
			return candidate
	return found[0] if not found.is_empty() else variable


func _value(variable: String, fallback: Variant) -> Variant:
	var id := _resolve(variable)
	if _var_values.has(id):
		return _var_values[id]
	var entry: Dictionary = _vars.get(id, {})
	var initial: Dictionary = entry.get("value", {})
	if entry.get("cls", "") == "SeqVar_RandomFloat":
		return randf_range(float(initial.get("Min", 0.0)), float(initial.get("Max", 1.0)))
	for key in ["bValue", "IntValue", "FloatValue", "StrValue"]:
		if initial.has(key):
			return initial[key]
	match entry.get("cls", ""):
		"SeqVar_Bool": return false
		"SeqVar_Int": return 0
		"SeqVar_Float": return 0.0
	return fallback


func _set_value(variable: String, value: Variant) -> void:
	_var_values[_resolve(variable)] = value


## A number a node reads off a variable link when one is wired, else `fallback`.
func _number(node: Dictionary, link: String, fallback: float) -> float:
	var linked: Array = node.get("vars", {}).get(link, [])
	if linked.is_empty():
		return fallback
	var value: Variant = _value(linked[0], fallback)
	return float(value) if value is float or value is int else fallback

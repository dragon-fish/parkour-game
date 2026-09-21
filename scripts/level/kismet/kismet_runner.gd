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
## Event classes whose MaxTriggerCount defaults to 0, unlimited, where every
## other event's is 1. [ME:CONFIRMED Stormdrain] none of its ninety
## SequenceActivated writes a count, while every other event meant to fire
## twice writes its 0: a sub-sequence is a subroutine, entered as often as it
## is called. Given the common default, a lift's "open the car doors" ran at
## the bottom and never again, and the car arrived to doors that stayed shut.
const UNLIMITED_BY_DEFAULT := {"SeqEvent_SequenceActivated": 0}
## What an object variable holds when it holds the player. There is nobody
## else to touch or press anything, so an event's Instigator is always this.
const THE_PLAYER := &"the player"
const PLAYER_VARIABLES := ["SeqVar_Player", "SeqVar_TdLocalPawn"]
## Outputs of a Used event that say the press did NOT happen.
const NOT_PRESSED := ["Unused", "Aborted"]
const LEVEL_START := ["SeqEvent_LevelLoaded", "SeqEvent_LevelStartup", "SeqEvent_LevelBeginning"]
## [ME:CONFIRMED] no jump, no crouch and walking pace in a lift car; the
## original says so with SeqAct_TdInElevator on the car's button.
## NO SUBJECT on these statuses: a status is looked up by effect AND subject,
## the moves ask with none, and one filed under a name of its own was on the
## player the whole ride and restricted nothing.
const LIFT_SPEED_M_S := 4.0
## How long the screen shows a scripted hit. [ME:CONFIRMED TdGame.u]
## TdDamageType.PhysicsHitReactionDuration, the original's flinch.
const FLINCH_S := 0.4
const UU_TO_M := 0.01
## The same for a knock-down.
const KNOCKDOWN_STANDS_S := 0.1

## The graph: a KismetGraph resource, kept out of the scene text.
@export var graph: KismetGraph
## Checkpoint label -> the TdCheckpoint actor it was made from.
@export var checkpoint_actors: Dictionary = {}
## Every package something streams, geometry or not. A package not named here
## is the chapter's own and always loaded.
@export var streamed: PackedStringArray = []
## What the screen is washed with when the level's Kismet hurts the player.
@export var hurt_tint: Color = Color(0.85, 0.08, 0.05, 0.5)
## Print every activation. Loud: a chapter fires hundreds on a button.
@export var trace: bool = false
## Print what a person would call the events of the level: a press, a touch
## that leads somewhere, a sequence starting and ending, a load and its
## Finished, the lift's restrictions. A few lines a minute, and what to paste
## when something does not happen.
@export var story: bool = true

## Class -> how often a class with no meaning here was passed through.
var unknown: Dictionary = {}
## Seconds of a scripted hit's wash still to show.
var _flinch_left: float = 0.0

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
## Placement -> {mesh, shapes} as it was built, for one SetStaticMesh has changed.
var _swapped: Dictionary = {}
## Path -> mesh, held so that a swap is a pointer and not a disk read.
var _meshes: Dictionary = {}
## Package -> what its factories have spawned in this life.
var _spawned: Dictionary = {}
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
	# Loaded now, behind the curtain, not on the lap that first wants them.
	for id: String in _by_class.get("SeqAct_SetStaticMesh", []) + _by_class.get("SeqAct_ActorFactory", []):
		var path: String = _nodes[id].get("mesh_path", "")
		if not path.is_empty() and ResourceLoader.exists(path) and not _meshes.has(path):
			_meshes[path] = load(path)
	for id: String in _by_class.get("SeqAct_Interp", []):
		var matinee: Matinee = _matinees.get(_nodes[id].get("matinee", ""))
		if matinee != null:
			matinee.take_over()
			matinee.looping = bool(_prop(_nodes[id], "bLooping", false))
	for actor: String in _events_of:
		var touched := false
		for id: String in _events_of[actor]:
			touched = touched or _nodes[id]["cls"] in TOUCH
		for node: Node in _actors.get(actor, []).duplicate():
			if touched and not node is Area3D and node.get_node_or_null("Mesh") is MeshInstance3D:
				node = _touch_area_of(node as Node3D)
			_listen(actor, node)
	for actor: String in _actors:
		if graph.actors.get(actor, {}).get("starts_off", false):
			for node: Node in _actors[actor]:
				_set_layers(node, COLLIDE_NONE)
	print("[kismet] %d nodes, %d actors found of %d named, %d matinees driven" % [
		_nodes.size(), _actors.size(), graph.actors.size(), _matinees.size()])


## [ME:CONFIRMED] a mesh can be what is touched: the subway's tunnel pieces
## collide without blocking (BlockActors off) and their Touch causes damage,
## which is the whole of "the beam hit you". A body reports no touch here, so
## the piece gets an area in the shape of its mesh, riding with it.
func _touch_area_of(placed: Node3D) -> Area3D:
	var area := Area3D.new()
	area.name = "KismetTouch"
	area.collision_layer = 0
	area.collision_mask = Arena.PLAYER_LAYER
	placed.add_child(area)
	_shape_touch_area(area, placed.get_node("Mesh") as MeshInstance3D)
	return area


## Convex shapes only: an area does not work with a concave one. A mesh with
## no simple collision -- the tunnel's clear pieces -- touches nothing, which
## is what it should do.
func _shape_touch_area(area: Area3D, picture: MeshInstance3D) -> void:
	for child in area.get_children():
		area.remove_child(child)
		child.queue_free()
	if picture.mesh == null:
		return
	for shape: Shape3D in picture.mesh.get_meta("simple_shapes", []):
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = picture.transform
		area.add_child(collision)


func _listen(actor: String, node: Node) -> void:
	if node is UseZone:
		(node as UseZone).used.connect(_on_used.bind(actor))
	if node is Area3D:
		(node as Area3D).body_entered.connect(_on_touch.bind(actor, true))
		(node as Area3D).body_exited.connect(_on_touch.bind(actor, false))


func _tell(text: String) -> void:
	if story and not trace:
		print("[kismet] %6.1fs  %s" % [_clock, text])


func _leads_somewhere(node: Dictionary) -> bool:
	for out: Dictionary in node["outs"]:
		if not (out["to"] as Array).is_empty():
			return true
	return false


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
	# EVERY sequence, not only the ones in motion: a train that has run to the
	# end of its track is as much the old life's as one half way along.
	for matinee: Matinee in _matinees.values():
		if is_instance_valid(matinee):
			matinee.drive("reset")
	_playing.clear()
	for actor: String in _touched_state:
		_restore_actor(actor)
	_touched_state.clear()
	_restore_meshes()
	_free_spawned()
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
	_free_spawned(key)
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
			# The original's press has STAGES, one output each -- a valve is
			# Start, Looping, Last turn, Finished; a button is Out or Used --
			# and a level wires whichever it likes: Stormdrain's steam hangs
			# on Finished and its water on Start. This project's press is the
			# dwell in the zone, over by the time it arrives here, so every
			# stage has happened; only the ones that mean "did not" are left.
			var stages: Array = []
			for out: Dictionary in _nodes[id]["outs"]:
				if not out["name"] in NOT_PRESSED:
					stages.append(out["name"])
			_fire_event(id, stages)
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
		var limit: int = int(_prop(node, "MaxTriggerCount", UNLIMITED_BY_DEFAULT.get(node["cls"], 1)))
		if limit > 0 and state.get("count", 0) >= limit:
			return
		if _clock < state.get("again_at", 0.0):
			return
		state["count"] = state.get("count", 0) + 1
		state["again_at"] = _clock + float(_prop(node, "ReTriggerDelay", 0.0))
	# Whoever touched or pressed: read further on as "the one to hurt".
	for variable: String in node.get("vars", {}).get("Instigator", []):
		_set_value(variable, THE_PLAYER)
	if trace:
		print("[kismet] EVENT %s %s %s" % [id, node["cls"], node.get("originator", "")])
	elif node.has("originator") and _leads_somewhere(node):
		_tell("%s %s %s" % [node["cls"].trim_prefix("SeqEvent_").trim_prefix("SeqEvt_"), node["originator"], names])
	var fired := false
	for i in (node["outs"] as Array).size():
		if names.is_empty() or names.has(node["outs"][i]["name"]):
			_fire(id, i)
			fired = true
	if not fired and not names.is_empty() and not (node["outs"] as Array).is_empty() and names[0] != "UnTouched":
		_fire(id, 0)


# ---------------------------------------------------------------- the engine

func _physics_process(delta: float) -> void:
	_show_flinch(delta)
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
			var heard: Array = _listeners.get(str(_prop(node, "EventName", "")).to_lower(), [])
			_tell("remote event '%s' -> %d listening" % [_prop(node, "EventName", ""), heard.size()])
			for listener: String in heard:
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
		"SeqAct_CauseDamage":
			# Only the player has health here. [ME:CONFIRMED] the scale is the
			# original's: 100 is a life, and the tunnel's beams deal 100.
			var hurts_player := _names_the_player(node, "Target")
			var player: Node = _player()
			if hurts_player and player != null and player.has_method("apply_status"):
				_tell("%s hurts the player for %s (%s)" % [id, _prop(node, "DamageAmount", 0.0), node.get("damage_type", "no type")])
				# HEALTH AND A FLINCH, NOT A LOCKOUT. [ME:CONFIRMED TdGame.u] no
				# damage type carries a stumble: TdDamageType's whole reaction
				# is bCausePhysicalHitReaction, a 0.4 s physics flinch of the
				# skeleton, and the types a level deals (Bullet, Explosion,
				# Fell, Shove) leave it at that. The knock-downs are their OWN
				# classes -- TdBarbedWireVolume, SeqAct_TdFallOnBack -- so a
				# level that wants one says so beside the damage. Dealt as a
				# STAGGER, every scripted hit cost two seconds on the floor.
				player.take_damage(float(_prop(node, "DamageAmount", 0.0)), Health.Cause.HAZARD)
				_flinch_left = FLINCH_S
			_fire(id, 0)
		"SeqAct_CauseDamageRadial":
			# A blast: whoever is within DamageRadius of what it names. Most
			# of the original's hang off a barrel being shot apart and never
			# fire here; the scripted ones -- the Boat's deck, the Scraper's
			# shaft -- do. [ME:INFERRED] falling off linearly to the edge, as
			# UE3's HurtRadius does by default; the node has no flag for it.
			var victim: Node3D = _player() as Node3D
			var reach: float = float(_prop(node, "DamageRadius", 0.0)) * UU_TO_M
			if victim != null and reach > 0.0 and victim.has_method("take_damage"):
				for centre: Dictionary in node.get("centres", []):
					var at: Vector3 = _v3(centre["position"])
					var standing: Node3D = _actors.get(centre["actor"]) as Node3D
					if standing != null and is_instance_valid(standing):
						at = standing.global_position
					var away: float = victim.global_position.distance_to(at)
					if away >= reach:
						continue
					var hurt: float = float(_prop(node, "DamageAmount", 0.0)) * (1.0 - away / reach)
					_tell("%s blasts the player for %.0f from %.1f m (%s)" % [id, hurt, away, node.get("damage_type", "no type")])
					victim.take_damage(hurt, Health.Cause.HAZARD)
					_flinch_left = FLINCH_S
			_fire(id, 0)
		"SeqAct_TdActorFactory":
			# THE ORIGINAL'S ENEMIES, and there are none here. A fight nobody
			# turns up to is over as it begins: everything the spawning would
			# have set going still goes (a door the police come through still
			# bursts open), and then "All Dead" -- which is what the level
			# waits on to open the way on, 25 times across the game. Left as a
			# class to pass through, only Finished fired and those ways stayed
			# shut for good.
			if input == 0:
				_tell("%s spawns nobody: its fight is over" % id)
				unknown[node["cls"]] = unknown.get(node["cls"], 0) + 1
				var outs: Array = node["outs"]
				for i in outs.size():
					if outs[i]["name"] == "Finished" or str(outs[i]["name"]).begins_with("Spawned"):
						_fire(id, i)
				_fire_named(id, ["All Dead"])
		"SeqAct_Teleport":
			# Only the player is anybody here; the original's other targets
			# are its AI. A destination the level has built and may have moved
			# is asked where it IS; the rest travel with the node.
			var spots: Array = node.get("destinations", [])
			var arena := _arena()
			if _names_the_player(node, "Target") and not spots.is_empty() and arena != null:
				var spot: Dictionary = spots[0]
				var columns: Array = spot["basis"]
				var to := Transform3D(Basis(_v3(columns[0]), _v3(columns[1]), _v3(columns[2])), _v3(spot["position"]))
				var standing: Node3D = _actors.get(spot["actor"]) as Node3D
				if standing != null and is_instance_valid(standing):
					to = standing.global_transform
				_tell("%s teleports the player to %s %s" % [id, spot["actor"], to.origin])
				# DEFERRED. A checkpoint's own sequence teleports -- the Boat's
				# intro puts the player in the container at time 0 -- and it
				# runs from INSIDE the respawn, which sets the body on the
				# checkpoint only after the level has been restored: done at
				# once, the teleport was overwritten on the same frame.
				arena.teleport_player.call_deferred(to)
			_fire(id, 0)
		"SeqAct_ActorFactory":
			# Scenery put in at run time; any other factory (rigid bodies,
			# emitters, AI) makes nothing here and passes the signal on.
			if node.has("spawn_points") and _meshes.has(node.get("mesh_path", "")):
				var made: Array = _spawned.get_or_add(node["package"], [])
				var spots: Array = node["spawn_points"]
				for i in maxi(int(_prop(node, "SpawnCount", 1)), 1):
					var spot: Dictionary = spots[i % spots.size()]
					var piece := MeshInstance3D.new()
					piece.mesh = _meshes[node["mesh_path"]]
					var columns: Array = spot["basis"]
					# `spawn_yaw_deg`: a config override (kismet_overrides), for a
					# spawn point that does not say which way round.
					var turned := Basis(Vector3.UP, deg_to_rad(float(node.get("spawn_yaw_deg", 0.0)))) \
							* Basis(_v3(columns[0]), _v3(columns[1]), _v3(columns[2]))
					piece.transform = Transform3D(turned, _v3(spot["position"]))
					add_child(piece)
					made.append(piece)
				_tell("%s spawned %d x %s" % [id, int(_prop(node, "SpawnCount", 1)), String(node["mesh_path"]).get_file()])
			else:
				unknown[node["cls"]] = unknown.get(node["cls"], 0) + 1
			_pass_on(id, node)
		"SeqAct_TdPlayerFail":
			# The original's "you did not make it": under a train, off the
			# roof of one. The same death as any other here.
			var arena := _arena()
			if arena != null:
				_tell("%s: the player fails" % id)
				arena.kill_player()
			_fire(id, 0)
		"SeqAct_SetStaticMesh":
			for actor: String in _targets(node, "Target"):
				for placed: Node in _actors.get(actor, []):
					_swap_mesh(placed, node.get("mesh_path", ""))
			_fire(id, 0)
		"SeqAct_Destroy":
			for actor: String in _targets(node, "Target"):
				_set_actor(actor, "shown", 0)
				_set_actor(actor, "collision", COLLIDE_NONE)
			_fire(id, 0)
		"SeqAct_TdInElevator":
			# Enter, Exit.
			_tell("lift rules %s (no jump, no crouch, walking pace)" % ("ON" if input == 0 else "off"))
			_set_lift_rules(input == 0)
			# [ME:COMMUNITY] and on its feet: a ride begun lying down, crouched
			# or in the air is standing the next frame.
			var rider: Node = _player()
			if input == 0 and rider != null and rider.has_method("stand_as_walking"):
				rider.stand_as_walking()
			_fire(id, 0)
		"SeqAct_TdFallOnBack":
			# [ME:CONFIRMED] no properties at all: the Subway's falling lift
			# and its train ride's end each pair one with a CauseDamage.
			var fallen: Node = _player()
			if fallen != null and fallen.has_method("apply_status"):
				_tell("%s puts the player on their back" % id)
				var down := StatusSpec.new()
				down.effect = Status.Effect.KNOCKDOWN
				down.seconds = KNOCKDOWN_STANDS_S
				fallen.apply_status(down, self, 0, true)
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
				_pass_on(id, node)


## Whatever the node would have done is done or is not, and the level goes on:
## the first output, and the one a latent action fires when it is through --
## ONCE, where the two are the same output.
func _pass_on(id: String, node: Dictionary) -> void:
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
	# Fired BEFORE it is disabled: _fire() honours off_outs, and the other way
	# round the link's one firing was the one it lost.
	_fire(id, pick)
	if _prop(node, "bAutoDisableLinks", false):
		off[pick] = true


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
			# Where a PLAY begins, and only a play: the subway's four tunnel
			# pieces are one 4 s loop entered at 0, 1, 2 and 3 s, and a wrap
			# that went back to the entry point instead of to 0 ran each piece
			# over a quarter of its track.
			if _prop(node, "bForceStartPos", false):
				at = clampf(float(_prop(node, "ForceStartPosition", 0.0)), 0.0, length)
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
			_seek_matinee(id, at)
			return
		3:
			state["direction"] = 0
			_playing.erase(id)
			_drive_matinee(id, "stop")
			_seek_matinee(id, at)
			return
		4:
			state["direction"] = -int(state.get("direction", 1))
			_drive_matinee(id, "play" if state["direction"] > 0 else "reverse")
	state["at"] = at
	_playing[id] = true
	_tell("sequence %s %s from %.2f of %.2f s%s  %s" % [id, "plays" if int(state["direction"]) > 0 else "reverses", at, length,
			"" if _matinees.has(node.get("matinee", "")) else " (nothing of it is built)", node.get("comment", "")])
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
	# The rate is a VARIABLE wherever the level means to change it: the
	# subway's tunnel rolls at a Float that starts at 0, is stepped up 0.05 at
	# a time once the player is on the roof and back down before the end. Read
	# as the constant beside it, the tunnel never moved. The Matinee node
	# showing the sequence is kept at the same rate.
	var rate: float = _number(node, "PlayRate", float(_prop(node, "PlayRate", 1.0)))
	if node.get("vars", {}).has("PlayRate"):
		var matinee: Matinee = _matinees.get(node.get("matinee", ""))
		if matinee != null and is_instance_valid(matinee):
			matinee.play_rate = rate
	var after: float = clampf(before + delta * rate * direction, 0.0, length)
	state["at"] = after
	_interp_events(id, node, before, after, direction, false)
	if direction > 0 and after >= length:
		if _prop(node, "bLooping", false):
			# The Matinee node goes round by itself, keeping what ran over;
			# this clock does the same, so the two stay on the same frame.
			state["at"] = fmod(before + delta * rate, length) if length > 0.0 else 0.0
			# A lap begins AT 0, and a key at 0 is on it: the subway's tunnel
			# keys everything there -- "this piece is back at the far end,
			# change its obstacle" -- and crossing alone (time > before) never
			# sees 0 again after the first play.
			_interp_events(id, node, 0.0, 0.0, 1, true)
			return
		state["direction"] = 0
		_playing.erase(id)
		_tell("sequence %s completed" % id)
		_fire_named(id, ["Completed"])
	elif direction < 0 and after <= 0.0:
		state["direction"] = 0
		_playing.erase(id)
		_tell("sequence %s back at its start" % id)
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


func _seek_matinee(id: String, at: float) -> void:
	var matinee: Matinee = _matinees.get(_nodes[id].get("matinee", ""))
	if matinee != null and is_instance_valid(matinee):
		matinee.seek(at)


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
	_tell("%s %s %s" % [id, "loads" if input == 0 else "unloads", keys])
	if _presence == null or _presence.is_settled():
		_tell("%s finished at once" % id)
		_fire_named(id, ["Finished"])
	else:
		_loading.append(id)


func _on_settled() -> void:
	if not _running or _loading.is_empty():
		return
	var done := _loading.duplicate()
	_loading.clear()
	for id in done:
		_tell("%s finished: the level has settled" % id)
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
	"COLLIDE_TouchAll": COLLIDE_TOUCH, "COLLIDE_TouchAllButWeapons": COLLIDE_TOUCH, "COLLIDE_TouchWeapons": COLLIDE_NONE,
}


func _set_layers(node: Node, mode: int) -> void:
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var at: Node = todo.pop_back()
		if at is CollisionObject3D:
			var body := at as CollisionObject3D
			body.set_meta(PackagePresence.KISMET_MODE_META, mode)
			# Its package has a say too: see PackagePresence.kismet_allows().
			var present: bool = _presence == null or _presence.is_body_present(body)
			PackagePresence.set_colliding(body, present and PackagePresence.kismet_allows(body))
		todo.append_array(at.get_children())


## A placement's mesh AND what it collides with: the subway swaps a clear
## tunnel piece for one with a beam to duck, and a beam that is only a picture
## is no obstacle. The shapes are the new mesh's own, as the geometry builder
## would have given it; what the node was built with is kept for the respawn.
func _swap_mesh(placed: Node, path: String) -> void:
	var picture := placed.get_node_or_null("Mesh") as MeshInstance3D
	if picture == null or path.is_empty() or not ResourceLoader.exists(path):
		return
	var mesh := load(path) as ArrayMesh
	if mesh == null or picture.mesh == mesh:
		return
	if not _swapped.has(placed):
		var built: Array[Node] = []
		for child in placed.get_children():
			if child is CollisionShape3D:
				built.append(child)
		_swapped[placed] = {mesh = picture.mesh, shapes = built}
	for child in placed.get_children():
		if child is CollisionShape3D:
			placed.remove_child(child)
			if not (_swapped[placed].shapes as Array).has(child):
				child.queue_free()
	picture.mesh = mesh
	var touch := placed.get_node_or_null("KismetTouch") as Area3D
	if touch != null:
		_shape_touch_area(touch, picture)
	# Solid only if it was built solid: the tunnel's pieces never block, and a
	# beam given shapes was a wall arriving at thirty metres a second.
	if not placed is CollisionObject3D or placed.get_meta("me_collision", "none") == "none":
		return
	var shapes: Array = mesh.get_meta("simple_shapes", [])
	if shapes.is_empty() and mesh.has_meta("per_poly_shape"):
		shapes = [mesh.get_meta("per_poly_shape")]
	for shape: Shape3D in shapes:
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = picture.position
		placed.add_child(collision)


func _restore_meshes() -> void:
	for placed: Node in _swapped:
		if not is_instance_valid(placed):
			continue
		for child in placed.get_children():
			if child is CollisionShape3D:
				placed.remove_child(child)
				child.queue_free()
		var built: Dictionary = _swapped[placed]
		var picture := placed.get_node("Mesh") as MeshInstance3D
		picture.mesh = built.mesh
		for shape: Node in built.shapes:
			placed.add_child(shape)
		var touch := placed.get_node_or_null("KismetTouch") as Area3D
		if touch != null:
			_shape_touch_area(touch, picture)
	_swapped.clear()


func _exit_tree() -> void:
	# The built shapes of a swapped node are out of the tree, and nobody's.
	for placed: Node in _swapped:
		for shape: Node in _swapped[placed].shapes:
			if is_instance_valid(shape) and not shape.is_inside_tree():
				shape.free()


func _set_lift_rules(on: bool) -> void:
	var player: Node = _player()
	if player == null or not player.has_method("apply_status"):
		return
	for effect in [Status.Effect.BLOCK_JUMP, Status.Effect.BLOCK_CROUCH, Status.Effect.SPEED_LIMIT]:
		if not on:
			player.remove_status(effect, &"")
			continue
		var spec := StatusSpec.new()
		spec.effect = effect
		if effect == Status.Effect.SPEED_LIMIT:
			spec.amount = LIFT_SPEED_M_S
		player.apply_status(spec, self, 0)


static func _v3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


## What a factory made belongs to the life and the package it was made in.
func _free_spawned(package: String = "") -> void:
	for key: String in _spawned.keys():
		if package != "" and key != package:
			continue
		for piece: Node in _spawned[key]:
			if is_instance_valid(piece):
				piece.queue_free()
		_spawned.erase(key)


## The wash of a scripted hit, fading. The tint channel has other owners -- the
## landing's lockout, a knock-down's blow -- and while one of them has the
## body this stands aside: they write every tick and two writers would flicker.
func _show_flinch(delta: float) -> void:
	if _flinch_left <= 0.0:
		return
	_flinch_left = maxf(_flinch_left - delta, 0.0)
	var player: Node = _player()
	if player == null or player.get("screen_effects") == null or player.get("move_manager") == null:
		return
	if player.move_manager.current_name in [Move.LANDING, Move.LAY_ON_GROUND, Move.FALL_UNCONTROLLED]:
		return
	player.screen_effects.set_tint(hurt_tint, _flinch_left / FLINCH_S)


## Whether a variable link of `node` holds the player: a player variable, or
## an object variable an event has written its instigator into.
func _names_the_player(node: Dictionary, link: String) -> bool:
	for variable: String in node.get("vars", {}).get(link, []):
		var resolved := _resolve(variable)
		if _vars.get(resolved, {}).get("cls", "") in PLAYER_VARIABLES or _var_values.get(resolved) == THE_PLAYER:
			return true
	return false


func _arena() -> Arena:
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	return node as Arena


func _player() -> Node:
	var arena := _arena()
	return arena.player if arena != null else null


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

class_name StatusList
extends RefCounted

# The temporary modifications currently on the player.
#
# Deliberately RefCounted and fed plain values: it owns no node and does no
# queries, so the whole layer can be tested without a physics world -- the
# same stance as FallTracker and SpeedEnergy.
#
# KEYED BY (effect, subject), at most one entry per key. `subject` is part of
# the key because BLOCK_INTEREST_LINE must be able to forbid several ropes at
# once; keying on the effect alone would let a level block exactly one. Every
# other effect leaves subject empty and so degrades to one entry per effect.

## Reported so a HUD, a sound, or the debug panel can react. REPORT ONLY --
## nothing here votes on whether a status is applied. Godot signals cannot
## return a value, and their dispatch order follows connection order, which
## follows scene structure; "may the player jump" must not change because a
## node was dragged in the editor.
signal status_applied(effect: int, subject: StringName)
signal status_removed(effect: int, subject: StringName)

## key -> {effect, subject, amount, view, seconds_left, source, priority}
var _entries: Dictionary = {}
## Conflicts already reported, so polling cannot repeat one every refresh.
## Cleared by clear_all() -- see there for why.
var _warned: Dictionary = {}
## How many DISTINCT conflicts have ever been pushed. Separate from _warned's
## size on purpose: clear_all() resets the dedup memory so a fresh life warns
## again about a conflict it meets again, but that re-warning is still one
## MORE distinct report, not the same one counted twice -- so this total is
## never rolled back.
var _warning_total: int = 0

static func _key(effect: int, subject: StringName) -> String:
	return "%d|%s" % [effect, subject]

## Puts `spec` on the player, or refuses. Returns whether it took effect.
##
## The refusal rules exist because two volumes may legitimately overlap:
##   same source          -> always refreshes
##   higher priority      -> overwrites
##   lower priority       -> ignored
##   equal, different src -> incumbent keeps its place, reported once
##
## THE FIRST RULE IS LOAD-BEARING, not an optimisation. A volume with a
## refresh_interval re-applies at its OWN priority; if equal priority were
## ignored across the board it would ignore its own refresh, and the status
## would expire while the player is still standing inside the volume.
func apply(spec: StatusSpec, source: Object, priority: int) -> bool:
	var key := _key(spec.effect, spec.subject)
	var existing: Dictionary = _entries.get(key, {})
	if not existing.is_empty() and existing["source"] != source:
		var incumbent: int = existing["priority"]
		if priority < incumbent:
			return false
		if priority == incumbent:
			_warn_conflict(key, existing["source"], source)
			return false
	var fresh := existing.is_empty()
	_entries[key] = {
		effect = int(spec.effect),
		subject = spec.subject,
		amount = spec.amount,
		view = int(spec.view),
		seconds_left = spec.seconds,
		source = source,
		priority = priority,
	}
	if fresh:
		status_applied.emit(int(spec.effect), spec.subject)
	return true

## Takes `effect` off. An empty `subject` takes every subject of that effect;
## a named one takes only that entry.
func remove(effect: int, subject: StringName = &"") -> void:
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		if e["effect"] != effect:
			continue
		if subject != &"" and e["subject"] != subject:
			continue
		_entries.erase(key)
		status_removed.emit(effect, e["subject"])

func clear_all() -> void:
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		status_removed.emit(e["effect"], e["subject"])
	_entries.clear()
	# The warning memory goes with it: a fresh life should report a conflict
	# it meets again, or the second run of a level is silent about a real
	# authoring mistake.
	_warned.clear()

## Ages every countdown. INF entries are left alone.
func tick(delta: float) -> void:
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		if is_inf(e["seconds_left"]):
			continue
		e["seconds_left"] -= delta
		if e["seconds_left"] <= 0.0:
			_entries.erase(key)
			status_removed.emit(e["effect"], e["subject"])

func has(effect: int, subject: StringName = &"") -> bool:
	return _entries.has(_key(effect, subject))

## The payload of one entry, or 0.0 when it is not present.
func amount_of(effect: int, subject: StringName = &"") -> float:
	var e: Dictionary = _entries.get(_key(effect, subject), {})
	return e.get("amount", 0.0)

func entry_count() -> int:
	return _entries.size()

## Diagnostics for the tests -- how many DISTINCT conflicts have been reported.
func warning_count() -> int:
	return _warning_total

func _warn_conflict(key: String, incumbent: Object, newcomer: Object) -> void:
	var mark := "%s|%d|%d" % [key, incumbent.get_instance_id(), newcomer.get_instance_id()]
	if _warned.has(mark):
		return
	_warned[mark] = true
	_warning_total += 1
	push_warning("StatusList: %s and %s both claim %s at the same priority; " % \
		[incumbent, newcomer, key] + "the first one keeps it. Give one a higher priority.")

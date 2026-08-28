@tool
class_name ModifierVolume
extends Area3D

# A region that puts temporary statuses on whoever walks in, of any shape:
# give it whatever CollisionShape3D children the spot needs. The same stance
# as Checkpoint -- the volume carries the shape and the intent, and nothing
# else.
#
# [ME:CONFIRMED 12 §12.2] The original's own volumes carry no behaviour data
# at all: class plus Kismet is the whole story. This one carries data instead,
# because there is no Kismet graph here to carry it -- a deliberate departure,
# not an oversight.

## Put these on whoever enters.
@export var apply: Array[StatusSpec] = []
## Take these off whoever enters. Only `effect` and `subject` are read;
## `amount`, `view` and `seconds` are ignored. An empty `subject` takes every
## subject of that effect.
##
## StatusSpec rather than Array[Status.Effect] because the latter has nowhere
## to put a subject, and "unblock pipe A while pipe B stays blocked" would
## become inexpressible.
@export var remove: Array[StatusSpec] = []

## Above zero, re-apply `apply` this often while a body is inside. This is how
## a region-wide modification is expressed: pair it with a StatusSpec.seconds
## of the same length and the status is continually renewed while the player
## is in, and lapses on its own shortly after they leave.
##
## THE POINT IS THAT NOTHING TRACKS MEMBERSHIP. No body_exited handler, no
## list of who is inside, and therefore no overlap bookkeeping.
@export var refresh_interval: float = 0.0

## Which layer this volume speaks on. When two volumes claim the same status,
## the higher layer wins; equal layers keep the incumbent and report once.
## Leave at 0 unless volumes actually overlap.
##
## DO NOT name this `priority`: Area3D already exports one, and it governs
## which overlapping area's physics overrides win. Reusing it would make
## raising a status layer silently reorder gravity and damping too.
@export var layer_priority: int = 0

## How many ENTRIES this volume acts on, 0 for unlimited. Refreshes do not
## count -- a polling volume renews many times per visit, and charging those
## would spend the whole budget on the first tick.
##
## [ME:CONFIRMED 12 §12.3] An integer rather than a boolean because the
## original's own SequenceEvent carries MaxTriggerCount (0 = unlimited), and
## because a looping level is re-entered: "only on the first lap" and "every
## lap" are two different needs and a boolean covers neither middle.
@export var max_trigger_count: int = 0

var _entries_used: int = 0
var _refresh_owed: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("modifier_volumes")
	body_entered.connect(_on_body_entered)
	# Always on, not gated by `refresh_interval > 0.0` here: exports set
	# imperatively after the node enters the tree (as every test in this
	# file does) would otherwise be read at their still-default value and
	# leave polling off for good. _physics_process() re-checks every frame.
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or refresh_interval <= 0.0:
		return
	_refresh_owed -= delta
	if _refresh_owed > 0.0:
		return
	_refresh_owed = refresh_interval
	for body in get_overlapping_bodies():
		if body.has_method("apply_status"):
			_push_apply(body)

func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, the same stance as Checkpoint's volume: the volume tells
	# whoever can listen, and cares nothing for who else wanders in.
	if not body.has_method("apply_status"):
		return
	if max_trigger_count > 0 and _entries_used >= max_trigger_count:
		return
	_entries_used += 1
	_apply_entry_effects(body)

## Shared by _on_body_entered() and enter_body_after_respawn() -- the only
## difference between a real entry and a post-respawn re-application is
## whether it charges max_trigger_count, decided by each caller before this
## runs.
func _apply_entry_effects(body: Node3D) -> void:
	for spec in remove:
		if spec != null:
			body.remove_status(spec.effect, spec.subject)
	_push_apply(body)
	# Renew immediately rather than waiting out a partial interval, so a body
	# that walks in just after a tick is not briefly unmodified.
	_refresh_owed = refresh_interval

func _push_apply(body: Node3D) -> void:
	for spec in apply:
		if spec != null:
			body.apply_status(spec, self, layer_priority)

## Called on respawn. The count is about one life: a level that cripples the
## player at its start has to cripple them again after they die there.
func reset_trigger_count() -> void:
	_entries_used = 0

## Treats a respawn inside this volume as a fresh entry, EXCEPT it does not
## charge max_trigger_count. See Arena._reapply_overlapping_modifiers() for
## why this cannot be left to the area's own signal.
##
## NOT charged: a respawn is not a player-initiated entry, and
## reset_trigger_count() already zeroed the count moments earlier as part of
## the same reset -- so nothing is being smuggled past the cap. Routing
## through _on_body_entered() would also double-charge the case where the
## body respawns from outside this volume into it: Godot's own body_entered
## fires for that transition too, and both would land on the same respawn.
func enter_body_after_respawn(body: Node3D) -> void:
	if not body.has_method("apply_status"):
		return
	_apply_entry_effects(body)

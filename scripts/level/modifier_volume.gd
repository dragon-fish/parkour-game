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
@export var apply: Array[StatusSpec] = []:
	set(value):
		apply = value
		update_configuration_warnings()
## Take these off whoever enters. Only `effect` and `subject` are read;
## `amount`, `view` and `seconds` are ignored. An empty `subject` takes every
## subject of that effect.
##
## StatusSpec rather than Array[Status.Effect] because the latter has nowhere
## to put a subject, and "unblock pipe A while pipe B stays blocked" would
## become inexpressible.
@export var remove: Array[StatusSpec] = []:
	set(value):
		remove = value
		update_configuration_warnings()

## Above zero, re-apply `apply` this often while a body is inside. This is how
## a region-wide modification is expressed: give the StatusSpec a `seconds` of
## AT LEAST TWICE this interval and the status is continually renewed while
## the player is in, and lapses on its own shortly after they leave.
##
## DO NOT pair it with a `seconds` equal to the interval. Both clocks then
## start from the same nominal value and subtract the same delta, so they reach
## zero on the very same physics tick forever, and the status survives only
## because this node is ordered ahead of the Player (see REFRESH_BEFORE_PLAYER)
## and renews it on that tick. There is no margin at all: anything that lets
## the two clocks drift -- a frame this node does not run, a body that enters
## part-way through a tick, a second volume renewing the same key -- puts the
## expiry a frame ahead of its renewal, and a one-frame hole is enough for a
## buffered jump to fire inside a region that forbids jumping. Twice the
## interval leaves a whole interval of slack instead.
##
## THE POINT IS THAT NOTHING TRACKS MEMBERSHIP. No body_exited handler, no
## list of who is inside, and therefore no overlap bookkeeping.
@export var refresh_interval: float = 0.0:
	set(value):
		refresh_interval = value
		update_configuration_warnings()
		# A volume with no interval must not be running a per-frame callback at
		# all. Gated here rather than in _ready() because an export set
		# imperatively after the node enters the tree (as every test does) would
		# otherwise be read at its still-default value and leave polling off for
		# good. DO NOT drop the is_inside_tree() guard: a setter runs before
		# _ready() during scene instantiation, and _ready() applies the settled
		# value for that case.
		if is_inside_tree():
			set_physics_process(refresh_interval > 0.0)

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

## Runs the refresh BEFORE the Player ages its status list. Godot orders
## _physics_process by this number ascending, and Player leaves it at the
## default 0.
##
## DO NOT drop this. Without it the order is scene-tree order -- which node
## happens to have been added first. A status whose countdown reaches zero on
## the same frame as its own renewal is then erased at the top of
## Player._physics_process and only re-applied later in that frame, after the
## moves have run. For SPEED_CAP that is invisible; for BLOCK_JUMP the
## buffered press fires through the gap, inside a region that forbids jumping.
const REFRESH_BEFORE_PLAYER := -1

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("modifier_volumes")
	process_physics_priority = REFRESH_BEFORE_PLAYER
	body_entered.connect(_on_body_entered)
	# The setter could not apply this before the node was in the tree.
	set_physics_process(refresh_interval > 0.0)

func _physics_process(delta: float) -> void:
	# Belt to the setter's brace. Load-bearing in the editor, where _ready()
	# returns before the gate and physics processing is on from tree entry.
	if Engine.is_editor_hint() or refresh_interval <= 0.0:
		return
	_refresh_owed -= delta
	if _refresh_owed > 0.0:
		return
	# CARRY THE OVERSHOOT, DO NOT clamp back to the whole interval. By here
	# `_refresh_owed` sits somewhere in (-delta, 0], and discarding that
	# remainder rounds every cycle up to a whole frame: a 0.1 s interval then
	# fires every seventh 60 Hz frame rather than every sixth. The status
	# being renewed rounds the other way -- it dies on the subtraction that
	# takes it past zero -- so a clamped cycle is one frame LONGER than the
	# life it exists to renew, and the status lapses one frame before every
	# single refresh.
	_refresh_owed += refresh_interval
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

## Flags a volume that cannot do what it was placed to do, in the scene tree,
## before the level is ever run. Every case here is silent at runtime: the
## volume simply never fires, or fires with a payload nothing reads.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D and child.shape != null:
			has_shape = true
	if not has_shape:
		warnings.append("No CollisionShape3D with a shape: this volume can never be entered.")
	if apply.is_empty() and remove.is_empty():
		warnings.append("Neither apply nor remove is set: this volume does nothing.")
	for spec in apply:
		if spec == null:
			warnings.append("An empty row in `apply`.")
		elif spec.effect == Status.Effect.SPEED_CAP and spec.amount <= 0.0:
			warnings.append("SPEED_CAP with amount %.2f pins the player in place." % spec.amount)
		elif spec.effect == Status.Effect.BLOCK_INTEREST_LINE and spec.subject == &"":
			warnings.append("BLOCK_INTEREST_LINE with no subject blocks nothing.")
	if refresh_interval > 0.0:
		for spec in apply:
			if spec == null:
				continue
			if is_inf(spec.seconds):
				warnings.append("refresh_interval is set but a status lasts forever: "
					+ "it will not lapse when the player leaves.")
			elif spec.seconds <= refresh_interval:
				warnings.append(("A status lasting %.2fs is refreshed every %.2fs: "
					+ "it expires on the very tick it is renewed, with no margin "
					+ "at all. Give it at least twice the interval.") \
					% [spec.seconds, refresh_interval])
	return warnings

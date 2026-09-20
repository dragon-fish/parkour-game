@tool
class_name Checkpoint
extends Area3D

# A respawn trigger of any shape: give it whatever CollisionShape3D children
# the spot needs, and walking in makes it the active respawn.
#
# [ME:CONFIRMED] AT EQUAL INDEX, LAST TOUCHED WINS -- verified directly
# against the original by noclip-flying back through the looping tutorial and
# suiciding: it still respawned at the LAST point touched, not the nearest.
# What looks like "nearest" behaviour is just the second lap walking back
# INTO the first lap's triggers, re-marking them as last-touched.
#
# `index` ranks points that must not be re-touched out of order. It exists
# for VERTICAL progress: a body falling off a spiral drops back through
# every point it already climbed past, and those touches must not undo the
# climb. A horizontal loop wants none of it -- leave every index at 0 and
# the rule collapses back to plain last-touched-wins, which is what the
# original does. No distance query, no ordering data to author unless the
# level actually stacks.
#
# The respawn puts the BODY CENTRE at this node's origin, facing its own -Z
# -- the same convention as SpawnPoint, so place the node about a body's
# half-height off the floor; the gizmo shows exactly where the capsule
# lands. The editor preview (capsule plus arrow, clickable in the viewport)
# is drawn by the respawn_gizmos editor plugin, not here.

## Announced as 「检查点 <display_name> 已保存」 when this becomes the active
## respawn. Leave empty for a silent checkpoint -- no line is shown at all.
@export var display_name: String = ""

## Rank along the level's progress. A touch on a LOWER index than the active
## one is ignored; equal ranks fall back to last-touched-wins. Leave at 0
## throughout a level that never stacks, and nothing changes. Gaps are free:
## number them 10, 20, 30 so a point can be inserted later.
@export var index: int = 0

## What the level is put into when a respawn lands HERE. Empty -- the usual
## case -- and a respawn is only the reset every other point gets.
##
## Paths are relative to THIS node. Keys, all optional:
##   show: Array[NodePath]   made visible, and its collision shapes enabled
##   hide: Array[NodePath]   made invisible, and its collision shapes disabled
##   play: Array[NodePath]   Matinees played from their start
##
## SWAP THE ACTORS, DO NOT REWIND THE SEQUENCE. A respawn onto something
## mid-flight -- a girder halfway up its rise, a train already rolling -- is
## staged in the original by hiding the ordinary actor, un-hiding a twin that
## was standing there all along, and playing the twin's OWN animation, written
## for the respawn. [ME:CONFIRMED Stormdrain Kismet] the `construction` point
## does exactly this: SeqEvt_TdCheckpointLoaded sends Rising_Girder_Event,
## which blocks-all the twin, un-collides the original, toggles both, and
## plays the twin's interp.
##
## Winding a sequence forward to a saved time looks like the obvious answer
## and is not the one the original uses. It also cannot express the half of
## this that is not movement -- what is solid, what is drawn, what is spawned.
@export var restores: Dictionary = {}

func _ready() -> void:
	# Only the body, never the level it stands in -- see Arena.PLAYER_LAYER.
	collision_mask = Arena.PLAYER_LAYER
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
		return
	body_entered.connect(_on_body_entered)

func _notification(what: int) -> void:
	# EDITOR ONLY: stay level. The respawn reads nothing but yaw, and "Align
	# Transform with View" copies the editor camera's pitch too -- the owner
	# should not have to square the view up first. Zeroing the tilt re-fires
	# this notification once; the second pass finds nothing to do.
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		if absf(rotation.x) > 0.0001 or absf(rotation.z) > 0.0001:
			rotation.x = 0.0
			rotation.z = 0.0

func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, same stance as InterestLine's volume: the checkpoint tells
	# whoever can listen, and cares nothing for who else wanders in.
	if body.has_method("touch_checkpoint"):
		body.touch_checkpoint(self)


## Puts the level into the state this point respawns into. Arena calls it
## AFTER the reset_on_respawn group has put everything back, so this is
## always the last word.
##
## A path that resolves to nothing is skipped in silence: the checkpoint
## belongs to a section, and a section can be built without the chapter.
func restore_level() -> void:
	for path: NodePath in restores.get("hide", [] as Array[NodePath]):
		_set_present(get_node_or_null(path), false)
	for path: NodePath in restores.get("show", [] as Array[NodePath]):
		_set_present(get_node_or_null(path), true)
	for path: NodePath in restores.get("play", [] as Array[NodePath]):
		var sequence := get_node_or_null(path)
		if sequence != null and sequence.has_method("play"):
			sequence.play()


## Drawn AND solid, or neither. The original spends two Kismet actions on
## this -- ToggleHidden and ChangeCollision -- because in UE3 they are
## separate; here a twin that is invisible but still standing in the way
## would be worse than either.
##
## Collision goes off at the SHAPES, not at the body's layer: a layer has to
## be remembered to be restored, and the shape's own flag does not.
static func _set_present(node: Node, present: bool) -> void:
	if node == null:
		return
	if node is Node3D:
		(node as Node3D).visible = present
	for shape in node.find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).disabled = not present

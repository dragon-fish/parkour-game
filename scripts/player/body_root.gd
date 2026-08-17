@tool
class_name BodyRoot
extends Node3D

# Editor-only alignment aid for Player.body_scene/body_mount_offset/
# body_mount_rotation_degrees. Deliberately isolated in its OWN small @tool
# script rather than making Player itself @tool -- Player owns movement,
# input polling and the state machine, and running any of that inside the
# editor (state machines ticking, physics queries firing against an editor
# camera that never moves) would be a cure worse than the "cannot see the
# body to align it" disease this exists to fix. This script does nothing but
# preview: it is a no-op everywhere Engine.is_editor_hint() is false, which
# covers both a real running game AND every headless test run (neither ever
# sets that hint), so Player's own runtime attach path in _attach_body() is
# entirely unaffected by this file existing.
#
# The preview instance below is deliberately NEVER given an owner. Both
# saving player.tscn (or any inherited scene of it) and instancing it at
# runtime go through PackedScene.pack()/loading, which only ever serialises
# nodes whose `owner` is the scene root being packed -- a node left without
# one is silently dropped (see tools/build_player_scene.gd's own nodes for
# the normal, positive use of that same rule: every node THERE sets `owner`
# deliberately, specifically so it IS kept). Leaving `owner` unset here is
# the same mechanism used in reverse, on purpose: it guarantees the preview
# can never be written into a saved scene file, and therefore can never ship
# in a runtime build either -- a player loaded from disk simply never
# contained this node to begin with, regardless of what the live editor
# tree looked like while someone was eyeballing an offset.

## Guards against rebuilding on every single edited frame for no reason:
## re-checked each editor process tick against the parent Player's current
## body_scene/body_mount_offset/body_mount_rotation_degrees, and the preview
## is only torn down and reinstanced when one of them actually changed.
## There is no signal to hook instead -- Player is not @tool, so editing its
## exported properties in the Inspector never fires a callback here; polling
## is the standard, and only available, way an @tool script can notice
## another node's plain (non-tool) script properties changing live.
var _preview: Node3D = null
var _previewed_scene: PackedScene = null
var _previewed_offset: Vector3 = Vector3.ZERO
var _previewed_rotation: Vector3 = Vector3.ZERO
var _has_built: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	set_process(true)
	_rebuild_preview()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	# `get_parent()` is untyped (see PlayerState's own note on the same
	# trap), so this needs an explicit annotation rather than `:=`.
	var player: Player = get_parent() as Player
	if player == null:
		return
	if _has_built and player.body_scene == _previewed_scene \
			and player.body_mount_offset == _previewed_offset \
			and player.body_mount_rotation_degrees == _previewed_rotation:
		return
	_rebuild_preview()

func _rebuild_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null

	var player: Player = get_parent() as Player
	if player == null:
		return

	# The capsule that the automatic vertical offset derives from is read
	# directly, as a sibling node's shape resource -- ordinary node/resource
	# access, not a call through Player.current_capsule_height() (that is an
	# INSTANCE method, and player is a placeholder here; see the file
	# header). Deliberately NOT cached into _has_built/_previewed_* below: a
	# missing CollisionShape3D or capsule is not a state anyone would ever
	# deliberately want previewed (unlike, say, a genuinely unset
	# body_scene) -- it means the scene is still mid-edit -- so this simply
	# returns and lets _process() retry, cheaply, every tick until the
	# capsule exists, rather than latching onto "no preview" the moment it
	# happens to be caught mid-build.
	var shape_node: CollisionShape3D = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var capsule: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	if capsule == null:
		return

	_has_built = true
	_previewed_scene = player.body_scene
	_previewed_offset = player.body_mount_offset
	_previewed_rotation = player.body_mount_rotation_degrees

	if player.body_scene == null:
		return
	var instance: Node = player.body_scene.instantiate()
	if not (instance is Node3D):
		instance.free()
		return

	_preview = instance as Node3D
	# No `owner` assignment -- see the file header comment on why that is
	# exactly what keeps this preview out of both the saved scene and any
	# runtime build.
	add_child(_preview)
	# Player.compute_mount_transform() is STATIC (see its own comment in
	# player.gd), so this runs the exact same formula body_mount_transform()
	# uses at runtime WITHOUT calling any method on `player` itself -- only
	# a class-level static call and plain exported-property reads, both of
	# which a placeholder instance permits; only its own instance methods
	# are off-limits.
	_preview.transform = Player.compute_mount_transform(
		capsule.height, player.body_mount_offset, player.body_mount_rotation_degrees
	)

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
var _previewed_scale: float = 1.0
var _has_built: bool = false
var _eye_marker: Node3D = null
var _feet_marker: Node3D = null
var _forward_marker: Node3D = null

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
	var wanted: Dictionary = _wanted_mount(player)
	if _has_built and wanted["scene"] == _previewed_scene \
			and wanted["offset"] == _previewed_offset \
			and wanted["rotation"] == _previewed_rotation \
			and is_equal_approx(wanted["scale"], _previewed_scale):
		return
	_rebuild_preview()

## What the body SHOULD be mounted with, profile first.
##
## A Player configured through a BodyProfile leaves its own body_* properties
## at their defaults until it applies the profile at _ready() -- which never
## happens in the editor, since Player is not a @tool script. Reading only
## those properties therefore previewed nothing at all for exactly the setups
## this aid exists to help with. See Player.body_profile.
static func _wanted_mount(player: Player) -> Dictionary:
	var profile: BodyProfile = player.body_profile
	if profile != null:
		return {
			"scene": profile.scene,
			"offset": profile.mount_offset,
			"rotation": profile.mount_rotation_degrees,
			"scale": profile.mount_scale,
		}
	return {
		"scene": player.body_scene,
		"offset": player.body_mount_offset,
		"rotation": player.body_mount_rotation_degrees,
		"scale": player.body_mount_scale,
	}

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

	var wanted: Dictionary = _wanted_mount(player)
	_has_built = true
	_previewed_scene = wanted["scene"]
	_previewed_offset = wanted["offset"]
	_previewed_rotation = wanted["rotation"]
	_previewed_scale = wanted["scale"]

	_rebuild_markers(capsule.height)

	if wanted["scene"] == null:
		return
	var instance: Node = (wanted["scene"] as PackedScene).instantiate()
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
		capsule.height, wanted["offset"], wanted["rotation"], wanted["scale"]
	)

## A ring at the CAMERA's resting height, so a model can be aligned against the
## thing it actually has to line up with.
##
## The owner's complaint, and it was fair: aligning a body meant reading numbers
## out loud and having someone else nudge them, once per model. Everything
## needed to do it by eye was already in the editor -- the capsule's own gizmo
## and this script's model preview -- except the one piece invented at runtime.
## CameraRig only takes its height in setup(), which the editor never calls, so
## the camera sits at the Player's origin there and tells you nothing.
##
## Read from a default MovementConfig, which does not exist outside a running
## Arena. That is the value every level starts from, so it is right unless a
## level overrides eye_height, and none does.
##
## Owner deliberately unset, exactly as for the body preview: this can never be
## saved into a scene or shipped in a build.
## One ring at the eye, one at the capsule's BOTTOM.
##
## The feet ring is there because its absence caused a real misreading: with
## only the collision shape's own faint wireframe to go by, the owner took the
## selected node's gizmo for the origin and concluded the model's feet were not
## on the capsule at all. They were -- 7 cm up, which is the mount offset doing
## exactly what it says. Nothing was wrong except that nothing was legible.
func _rebuild_markers(capsule_height: float) -> void:
	_eye_marker = _replace_ring(_eye_marker, 		MovementConfig.new().camera.eye_height, Color(0.2, 0.9, 1.0, 0.85))
	# Where the capsule ends, which is where the model's feet belong.
	_feet_marker = _replace_ring(_feet_marker, 		-capsule_height * 0.5, Color(1.0, 0.75, 0.2, 0.85))
	_rebuild_forward_marker(-capsule_height * 0.5)

## An arrow along -Z at the feet, because nothing else in the bench says which
## way FORWARD is.
##
## That gap has already cost a round trip: a VRM faces +Z by specification
## against Godot's -Z, so the body mounts backwards, and the symptom is not "the
## model is backwards" -- it reads as the third-person camera being on the wrong
## side, with the character apparently running in reverse. See
## Player.body_mount_rotation_degrees. With an arrow to compare against, a
## backwards model is obvious before the game is ever started.
func _rebuild_forward_marker(feet_height: float) -> void:
	if _forward_marker != null:
		_forward_marker.queue_free()
		_forward_marker = null
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.26
	arrow.mesh = cone
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 1.0, 0.4, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	arrow.material_override = material
	# A cylinder points along +Y; tip it to lie along -Z, which is forward.
	arrow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	arrow.position = Vector3(0.0, feet_height, -0.45)
	add_child(arrow)
	_forward_marker = arrow

func _replace_ring(existing: Node3D, height: float, colour: Color) -> Node3D:
	if existing != null:
		existing.queue_free()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.10
	torus.outer_radius = 0.13
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Drawn THROUGH the body on purpose: what is being judged is where these
	# heights sit INSIDE it, and a marker the body hides is no use for that.
	material.no_depth_test = true
	ring.material_override = material
	ring.position = Vector3(0.0, height, 0.0)
	add_child(ring)
	return ring

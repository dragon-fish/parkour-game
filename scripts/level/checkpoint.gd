@tool
class_name Checkpoint
extends Area3D

# A respawn trigger of any shape: give it whatever CollisionShape3D children
# the spot needs, and walking in makes it the active respawn. ✅ THE OWNER:
# "大致来说就是个任意形状的触发器，走进去就保存最后一个点."
#
# LAST TOUCHED WINS, nothing else -- the owner measured it in the original
# twice. The looping tutorial LOOKS like it picks the nearest point, but
# noclip-flying back and suiciding still respawned at the LAST one: the
# "nearest" behaviour is just the second lap walking back INTO the first
# lap's triggers, which makes them last-touched again. The loop case is
# free; no distance query, no ordering data to author.
#
# The respawn stands at this node's own origin facing its own -Z, so aim the
# node the way the player should wake up looking. In the EDITOR ONLY, a
# translucent capsule with an arrow shows exactly that -- where the body
# stands and which way it faces. The preview is never given an owner, so it
# is not saved into the scene, and the game never builds it at all.

const PREVIEW_NAME := "EditorPreview"

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
		_build_preview()
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

# --- editor preview only below this line -----------------------------------

func _build_preview() -> void:
	if has_node(PREVIEW_NAME):
		return
	var root := Node3D.new()
	root.name = PREVIEW_NAME

	var green := StandardMaterial3D.new()
	green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	green.albedo_color = Color(0.2, 0.9, 0.4, 0.35)

	# The body, at the player capsule's own size, standing on the origin.
	var capsule := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.3
	capsule_mesh.height = 1.8
	capsule.mesh = capsule_mesh
	capsule.material_override = green
	capsule.position.y = 0.9
	root.add_child(capsule)

	var solid := StandardMaterial3D.new()
	solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid.albedo_color = Color(0.2, 0.9, 0.4, 0.9)

	# The arrow: shaft plus cone, pointing down -Z at chest height -- the
	# direction the body wakes up facing. Cylinders grow along +Y, so both
	# pieces are tipped -90 about X to lie along -Z.
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.04
	shaft_mesh.bottom_radius = 0.04
	shaft_mesh.height = 0.5
	shaft.mesh = shaft_mesh
	shaft.material_override = solid
	shaft.rotation_degrees.x = -90.0
	shaft.position = Vector3(0.0, 1.0, -0.55)
	root.add_child(shaft)

	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.12
	head_mesh.height = 0.25
	head.mesh = head_mesh
	head.material_override = solid
	head.rotation_degrees.x = -90.0
	head.position = Vector3(0.0, 1.0, -0.925)
	root.add_child(head)

	add_child(root)

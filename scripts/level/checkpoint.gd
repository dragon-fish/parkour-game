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

## Announced as 「检查点 <display_name> 已保存」 when this becomes the active
## respawn. Leave empty for a silent checkpoint -- no line is shown at all.
@export var display_name: String = ""

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
		RespawnPreview.build(self, Color(0.2, 0.9, 0.4), 0.0)
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


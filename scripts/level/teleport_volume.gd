@tool
class_name TeleportVolume
extends Area3D

# Where the original cuts away and the body wakes somewhere else. SP07 leaves
# the harbour in the back of a truck and comes to inside that truck in the
# ship's hold, a chapter apart; the original plays a cutscene over the ride,
# and what the player does during it is nothing.
#
# THE RIDE IS NOT SIMULATED and there is no cutscene to play: walking in puts
# the body at `checkpoint`, under the curtain a respawn already uses. A cut
# with no cover reads as a bug, which is the same reason Arena refuses to
# teleport anyone uncovered.
#
# THE DESTINATION IS A CHECKPOINT, not a transform. It is the level's own
# statement of where a body stands, it is already placed against the floor
# there, and making it the active one means a death after the cut returns the
# player to where the cut left them rather than to the far side of the
# chapter. Searched by name from the Arena, so it may stand in another
# section's shell than this volume does.

## Name of the Checkpoint node to wake at.
@export var checkpoint_name: String = ""


func _ready() -> void:
	# Only the body, never the level it stands in -- see Arena.PLAYER_LAYER.
	collision_mask = Arena.PLAYER_LAYER
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var has_shape := false
	for child in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			has_shape = true
	if not has_shape:
		warnings.append("No CollisionShape3D with a shape: nothing can ever walk into this.")
	if checkpoint_name.is_empty():
		warnings.append("No checkpoint_name: there is nowhere to wake up.")
	return warnings


func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, as DeathVolume and Checkpoint are: whoever can be sent
	# somewhere reacts, and the volume cares nothing for who else wanders in.
	if not body.has_method("touch_checkpoint"):
		return
	var arena := _arena()
	if arena == null:
		return
	var target := arena.find_child(checkpoint_name, true, false) as Checkpoint
	if target == null:
		push_error("[teleport] no checkpoint named %s to wake at" % checkpoint_name)
		return
	# Taking the checkpoint first is what makes the respawn land there. It is
	# refused while dying and for a checkpoint ranked below the one already
	# held, both of which are the right answers here too: a body that dies on
	# the way in has died, and a cut that leads backwards is not one.
	body.touch_checkpoint(target)
	if body.get("active_checkpoint") != target:
		return
	arena.respawn_at_checkpoint()


func _arena() -> Arena:
	var node := get_parent()
	while node != null and not node is Arena:
		node = node.get_parent()
	return node as Arena

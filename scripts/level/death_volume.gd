@tool
class_name DeathVolume
extends Area3D

# Somewhere the player does not survive: give it whatever CollisionShape3D
# children the spot needs, and walking in is fatal.
#
# THE POINT IS SPEED. A lift shaft is lethal at the top, not at the bottom --
# the drop is the same either way, and the fifteen seconds spent finding out
# are fifteen seconds the player has already understood by the first one. The
# same goes for the void under a level: Arena's own fall-out-of-the-world net
# uses this exact path.
#
# IT SAVES THE FALL, NOT THE DYING. Arena.kill_player() runs the full death
# sequence, exactly as a fatal fall does. What the volume buys is the fifteen
# seconds on the way down, not the four seconds of dying -- and its other use
# needs those four: a boundary at a junction, dressed with guards, where the
# fiction is that the player was shot. Cut straight to black and that reads as
# a bug rather than as a death.
#
# NOT A STATUS. Every dial ModifierVolume carries -- seconds, refresh_interval,
# layer_priority, max_trigger_count -- is meaningless on something permanent
# and irreversible, and a status layer whose whole definition is "temporary"
# has no honest place to put death. This node has no settings at all, which is
# the whole of its interface.

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
		if child is CollisionShape3D and child.shape != null:
			has_shape = true
	if not has_shape:
		warnings.append("No CollisionShape3D with a shape: nothing can ever fall into this.")
	return warnings

func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, the same stance as Checkpoint's volume: the volume tells
	# whoever can listen, and cares nothing for who else wanders in.
	if body.has_method("die_in_volume"):
		body.die_in_volume()

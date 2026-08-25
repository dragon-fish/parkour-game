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
# node the way the player should wake up looking.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Duck-typed, same stance as InterestLine's volume: the checkpoint tells
	# whoever can listen, and cares nothing for who else wanders in.
	if body.has_method("touch_checkpoint"):
		body.touch_checkpoint(self)

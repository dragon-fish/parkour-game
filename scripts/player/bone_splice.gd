class_name BoneSplice
extends Node

# Gives a skeleton back a bone the format let its author leave out, and moves
# the bones that should hang off it back onto it.
#
# WHY A MISSING BONE IS WORSE THAN NO BONE. An animation pack authored against
# the full chain COUNTERWEIGHTS across it: over one sprint cycle beriul's packs
# turn UpperChest about 25 degrees one way while Neck and Head each take
# roughly 16 back the other, and all four spine bones sum to under 1.5 degrees
# for the whole cycle -- the shoulders roll and the head holds still, which is
# how the pack's own preview reads. A body without UpperChest drops the track
# the +25 was going to and keeps every counterweight, so the head swings 25
# degrees the WRONG way instead of holding. Measured on beriul: 41.9 degrees of
# world yaw before this, 0.03 after.
#
# VRM makes UpperChest optional, so neither side is at fault -- the model is
# legal and so is the pack. They only fail together, which is why the repair
# belongs on the model rather than in the code that plays the clips.
#
# MERGED, NOT ABSENT, and that is what `adopted_bones` is for. An author who
# leaves UpperChest out does not delete the anatomy, they hang its children off
# Chest instead: on beriul that is Neck AND both Shoulders, all three siblings
# where a complete rig has them stacked. Splice the bone back in and adopt only
# the Neck, and the clip turns the upper chest while the shoulders stay behind
# -- the neck slides from side to side between them, which reads as a small
# lateral shimmy rather than as a turn.
#
# ON THE WRAPPER, NOT IN A CONSUMER. Four separate places instantiate a body
# (Player, the animation gallery, the character showcase, the main menu) and a
# repair living in any one of them fixes exactly one. The wrapper scene is the
# single thing all four go through.
#
# DO NOT reach for this to quieten an animation. It restores what the clip was
# authored against; it does not have an opinion about the result. A bone that
# genuinely is not in the rig -- a tail, a wing -- is not this.

## The bone to create. Nothing happens if the skeleton already has it, so this
## is safe on a rig that does not need it.
@export var bone_name: String = "UpperChest"
## The bone it is spliced under.
@export var parent_bone: String = "Chest"
## Everything that should hang off the new bone instead of off `parent_bone`.
## Each must currently be a direct child of `parent_bone`; any that is not is
## skipped with a warning rather than moved, because a rig that puts them
## somewhere else is a different rig and not this one with a gap.
##
## THE SHOULDERS BELONG HERE, not just the neck. See the note above.
##
## Array[String] rather than PackedStringArray: the editor's re-save drops the
## latter silently, which this project has already lost a body's worth of
## spring-bone chains to.
@export var adopted_bones: Array[String] = ["Neck", "LeftShoulder", "RightShoulder"]

## Where the new bone sits between `parent_bone` and the FIRST adopted bone, as
## a fraction of the gap. The adopted bones have the same offset taken back off
## their own rests, so every one of them keeps the global rest position it had
## -- what moves is only the point they now rotate ABOUT.
##
## THE ANATOMICALLY CORRECT VALUE IS NOT THE ONE THAT LOOKS RIGHT, and it was
## measured both ways before landing on 0. A rig that HAS the bone (vrm_test)
## puts UpperChest 45.1 per cent of the way from Chest to Neck, so that is
## where this started. On beriul it costs more than it buys:
##
##   pivot   head sideways   head vs shoulders   head mean Z
##   0.00        2.44 cm          0.76 cm          21.74 cm
##   0.45        2.01 cm          0.76 cm          19.61 cm
##
## Raising the pivot pushes the head 2.1 cm FORWARD on average -- visible, and
## the owner spotted it immediately -- to buy 0.4 cm off a sideways travel, and
## does nothing at all for the head-against-shoulders shimmy that is the thing
## the eye actually reads. That number is unmoved by the pivot because the head
## and the shoulders now hang off the same bone and turn together, which is
## what `adopted_bones` bought and this dial cannot add to.
##
## So it stays a dial, and it stays at 0. A rig whose proportions differ, or
## one whose clips lean on the upper chest harder, may want it raised -- look
## at the body, not at the anatomy chart.
@export_range(0.0, 1.0) var splice_at: float = 0.0

func _ready() -> void:
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null:
		push_warning("%s: not a child of a Skeleton3D, so there is nothing to splice."
			% name)
		return
	if skeleton.find_bone(bone_name) >= 0:
		return
	var parent_index: int = skeleton.find_bone(parent_bone)
	if parent_index < 0:
		push_warning("%s: no bone named %s to splice %s under."
			% [name, parent_bone, bone_name])
		return
	var adopted: Array[int] = []
	for candidate in adopted_bones:
		var index: int = skeleton.find_bone(candidate)
		if index < 0:
			push_warning("%s: no bone named %s to adopt." % [name, candidate])
			continue
		if skeleton.get_bone_parent(index) != parent_index:
			push_warning("%s: %s does not hang off %s, so it is left where it is."
				% [name, candidate, parent_bone])
			continue
		adopted.append(index)
	if adopted.is_empty():
		push_warning("%s: nothing to adopt, so %s would be a leaf and change nothing."
			% [name, bone_name])
		return

	# The gap is measured to the FIRST adopted bone, which is the chain this
	# splice is really about -- the others are siblings that came along.
	var offset: Vector3 = skeleton.get_bone_rest(adopted[0]).origin * splice_at
	# APPENDED, so every existing index still means what it meant and no skin
	# weight moves. Godot orders the hierarchy itself, so the new bone sitting
	# at a higher index than the children it now parents is not a problem.
	var inserted: int = skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(inserted, parent_index)
	skeleton.set_bone_rest(inserted, Transform3D(Basis.IDENTITY, offset))
	skeleton.reset_bone_pose(inserted)
	for index in adopted:
		var rest: Transform3D = skeleton.get_bone_rest(index)
		# The same offset back off, so the bone's GLOBAL rest is untouched: it
		# ends up exactly where it was, hanging off a new joint. Anything else
		# would shift the head, and every mount offset tuned against the old
		# chain with it.
		skeleton.set_bone_rest(index, Transform3D(rest.basis, rest.origin - offset))
		skeleton.set_bone_parent(index, inserted)
		skeleton.reset_bone_pose(index)

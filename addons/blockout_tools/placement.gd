@tool
extends RefCounted

# Where a newly drawn node goes in the tree. Kept out of the editor plugin so
# the rule can be tested against real nodes without an editor.

## The node a new one should be added under.
##
## A collision shape drawn onto something that can hold one becomes its CHILD:
## that is the whole point of drawing it there, and it is how this project's
## volumes are built -- Checkpoint, DeathVolume and ModifierVolume are all
## Area3D asking for whatever CollisionShape3D children the spot needs.
##
## Everything else becomes a SIBLING of the selection. Not a child: every drag
## selects what it just made, so parenting to the selection would thread each
## new node through the last one and build a chain nobody asked for.
static func parent_for(selected: Node, root: Node, collision: bool) -> Node:
	if selected == null or selected == root:
		return root
	if collision and selected is CollisionObject3D:
		return selected
	var parent: Node = selected.get_parent()
	return parent if parent != null else root

## Where among the parent's children the new node belongs.
##
## Directly after the node it is a sibling of, rather than at the end of the
## list where add_child() leaves it -- a scene tree of thirty solids is no
## place to go hunting for the one just drawn. Returns -1 when there is nothing
## to sit after, which means "leave it where add_child() put it".
static func insert_index(parent: Node, selected: Node) -> int:
	if selected == null or parent == null:
		return -1
	if selected.get_parent() != parent:
		return -1
	return selected.get_index() + 1

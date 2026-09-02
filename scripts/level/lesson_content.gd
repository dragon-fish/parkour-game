class_name LessonContent
extends RefCounted

# Takes one lesson's geometry out of a scene that is ALSO a playable level.
#
# A lesson inherits templates/base_level.tscn so the author can open it and
# run around in it while shaping the geometry. That gives every lesson a Sun,
# a WorldEnvironment, a SpawnPoint, a Floor, a Player, a DebugHud and a
# TuningPanel -- scaffolding for editing, none of which belongs in the
# tutorial. Only the Content subtree does.

## The node a lesson puts its own geometry under. Everything else in the file
## is there so the lesson can be played on its own.
const CONTENT := &"Content"

## Returns the lesson's Content subtree, detached and ready to be reparented,
## or null if the scene has none.
##
## INSTANTIATED BUT NEVER ADDED TO THE TREE. _ready() runs on entering a scene
## tree, so nothing in the discarded half ever wakes up: no second Player, no
## second TuningPanel fighting over F1, no several hundred milliseconds of
## body loading. Adding the whole scene and then deleting the extra nodes
## looks equivalent and is not -- by then every _ready() has already run.
static func take(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var whole: Node = scene.instantiate()
	var content: Node = whole.get_node_or_null(NodePath(CONTENT))
	if content == null:
		whole.free()
		return null
	whole.remove_child(content)
	whole.free()
	return content as Node3D

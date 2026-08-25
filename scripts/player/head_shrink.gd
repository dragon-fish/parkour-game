class_name HeadShrink
extends SkeletonModifier3D

# First-person head hiding for bodies that are ONE mesh: collapses the head
# bone (and with it every head-anchored child chain -- hair, horns, halo) to
# nothing while the owning Player's camera is first-person. The VRM pipeline
# gets this for free as a generated headless variant on its own render layer
# (see CameraRig._apply_body_layers); an FBX body carries no such variant,
# and its face shares a surface with the rest of the skin, so render layers
# cannot cut the head off. Scaling the bone can.
#
# Finds the Player by walking up the tree, so the same wrapper scene stays
# headful anywhere else it is instanced (the main menu silhouette, a gallery).

const SHRINK := Vector3(0.0001, 0.0001, 0.0001)

@export var head_bone_name: String = "Head"

var _player: Node = null
var _searched: bool = false

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if not _searched:
		_searched = true
		var walker: Node = get_parent()
		while walker != null:
			if walker is Player:
				_player = walker
				break
			walker = walker.get_parent()
	if _player == null:
		return
	var rig = _player.camera_rig
	if rig == null or rig.third_person:
		return
	var head := skeleton.find_bone(head_bone_name)
	if head >= 0:
		skeleton.set_bone_pose_scale(head, SHRINK)

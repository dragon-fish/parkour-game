class_name BonePoseOffset
extends ClipScopedModifier

# Turns named bones by fixed angles on top of what a clip is doing -- a
# corrective pose for a clip that is nearly right. Lying on the back is the
# case it was written for: the pack's knock-down ends flat on the floor, and a
# little flex at the waist and chest with the arms propped behind reads as a
# body that went down and is holding itself up, not one laid out.
#
# ADDITIVE, AND ONLY WHILE ITS CLIPS PLAY -- see ClipScopedModifier for when
# and how much. Angles, not IK: nothing here knows where the floor is, so a
# hand is put near the ground by its angles, not planted on it.
#
# Sits BEFORE the spring simulators, so cloth and hair react to the corrected
# pose rather than to the animation's.

## Degrees each bone is turned, as Euler angles about the SKELETON's own axes
## (X across the body, Y up, Z forward in the rest pose), turned about the
## bone's own origin. Applied parents first, so a turn at the waist carries the
## chest, the arms and the head with it before the chest's own turn is added.
@export var rotations: Dictionary[String, Vector3] = {}

func _apply(skeleton: Skeleton3D, weight: float) -> void:
	var order: Array[int] = []
	for bone_name in rotations:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			order.append(bone)
	# A parent's index is always lower than its children's in a Skeleton3D.
	order.sort()
	for bone in order:
		var degrees: Vector3 = rotations[skeleton.get_bone_name(bone)]
		var turn := Basis.from_euler(degrees * (weight * PI / 180.0))
		var pose := skeleton.get_bone_global_pose(bone)
		skeleton.set_bone_global_pose(bone, Transform3D(turn * pose.basis, pose.origin))

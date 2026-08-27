class_name BoneRotationDamp
extends SkeletonModifier3D

# Scales back a bone's ANIMATED rotation -- its deviation from rest -- by a
# constant factor, leaving translation and everything below untouched. The
# use case is a clip whose motion is right for one body and too loud on
# another: beriul's wrapper halves the head's sway so the sprint cycle
# stops reading as head-shaking on a large-headed model. Runs BEFORE the
# spring simulators so hair reacts to the damped head, and before Player's
# HeadLook, whose own look-at lands on top at full strength.

@export var bone_name: String = "Head"
## 1.0 keeps the animation as authored; 0.5 halves the sway; 0 pins the
## bone at rest.
@export_range(0.0, 1.0) var keep: float = 0.5

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var pose := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, rest.slerp(pose, keep))

class_name BoneScaleTweak
extends SkeletonModifier3D

# A standing per-bone scale, for cheating a model's proportions -- the classic
# use being a chibi body whose head reads too large against this project's
# shared eye height: shrink the head bone and the silhouette ages up, no mesh
# edits involved. Multiplies the animated pose scale rather than replacing
# it, so clips that scale the bone still read through. Place BEFORE any
# spring simulators on the same skeleton, so their chains anchor to the
# scaled bone.

@export var bone_name: String = "Head"
@export var bone_scale: Vector3 = Vector3.ONE

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var bone := skeleton.find_bone(bone_name)
	if bone >= 0:
		skeleton.set_bone_pose_scale(bone, skeleton.get_bone_pose_scale(bone) * bone_scale)

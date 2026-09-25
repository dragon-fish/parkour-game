class_name BoneSplay
extends ClipScopedModifier

# Swings named bones OUTWARD from the body's median plane, on top of whatever
# the animation is doing. The corrective additive pose that a retarget cannot
# supply: humanoid retargeting copies bone ROTATIONS, so a hand that grazed a
# slim body's hip follows the same rotation into a wider one and clips
# through it -- observed on beriul, in Idle and Walk.
#
# Measured on this pair of models: the animations were authored on a body
# whose shoulders are 15% WIDER than its hips; hers are 7% narrower, so every
# arm's whole path starts inboard. Her arm is 0.295 m and the hands sit about
# 0.018 m inside the surface, which is 3.5 degrees of splay -- so single
# digits here, not tens.
#
# Sits BEFORE the spring simulators, so cloth and hair react to the corrected
# arms rather than to the animation's.
#
# Scoped to named clips, because the need is not uniform: at a run the arms
# swing clear on their own, and only the small-amplitude cycles keep the
# hands against the body. Keep the list to Idle and Walk. When, and how much,
# is ClipScopedModifier's: the angle fades in and out over `blend_time`, so
# leaving a listed clip does not snap the arms back.

## The bones to swing. Each one's side is read from its own rest position, so
## a left/right pair takes one angle and moves apart, not together.
@export var bones: Array[String] = ["LeftUpperArm", "RightUpperArm"]
## Degrees away from the body. Positive opens the arms; negative closes them.
@export_range(-30.0, 30.0) var degrees: float = 5.0
## The axis the swing turns about, in skeleton space: the model's forward,
## so a hanging arm moves sideways rather than forward or back.
@export var axis: Vector3 = Vector3(0.0, 0.0, 1.0)

## The angle actually applied right now, chasing 0 or `degrees`.
var _applied: float = 0.0

func _apply(skeleton: Skeleton3D, weight: float) -> void:
	_applied = degrees * weight
	var turn_axis := axis.normalized()
	if turn_axis.is_zero_approx():
		return
	for bone_name in bones:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		# Which side of the median plane this bone lives on. Rotating about
		# +Z carries a hanging limb toward +X, so a bone resting at +x wants
		# the positive angle and its mirror wants the negative one.
		var side := signf(skeleton.get_bone_global_rest(bone).origin.x)
		if is_zero_approx(side):
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var turn := Basis(turn_axis, deg_to_rad(_applied) * side)
		skeleton.set_bone_global_pose(bone, Transform3D(turn * pose.basis, pose.origin))

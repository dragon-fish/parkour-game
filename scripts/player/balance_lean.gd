class_name BalanceLean
extends SkeletonModifier3D

# Shows a balance wobble as a body leaning, not as a whole model tipping over.
#
# THE FEET MUST STAY ON THE BEAM. Rolling the model's root would swing the
# feet off the pipe it is standing on, which is the one thing the pose has to
# sell. This project has no leg IK, so the stand-in is where the lean
# ORIGINATES: the hips take a token share and the spine chain takes the rest,
# so the displacement that reaches the feet is only what the hips' few
# degrees carry down. That is the design, not a compromise to fix.
#
# Built on HeadLook's arithmetic, one axis over. Everything that file says
# about set_bone_global_pose applies here unchanged: a humanoid bone's local
# axes are whatever its rest pose made them, so a local rotation bends the
# body somewhere unrelated -- which this project cannot see, only measure.
#
# DO NOT reach for the packs' lean clips (Jog_Fwd_LeanL/R) instead. They are
# authored for leaning into a full-speed run, and the owner ruled them out
# here. On a beam the body is simply walking at 8.81 km/h; Walk is the clip.

## Takes the share named by the caller. Same chain, same reasoning as
## HeadLook.SPINE_CHAIN: Spine's origin sits just above the hips, which is
## where a person bends from. Starting at Chest reads as a shrug.
const SPINE_CHAIN: Array[StringName] = [&"Spine", &"Chest", &"UpperChest"]
## Everything below the waist hangs off this one bone.
const HIPS_CHAIN: Array[StringName] = [&"Hips"]

var _lean: float = 0.0
var _max_lean: float = 0.0
var _hips_lean: float = 0.0

## Signed -1..1, plus the two limits in radians. Fed every tick by Player while
## BalanceMove is active, and zeroed the moment it is not.
func request_lean(signed: float, max_lean: float, hips_lean: float) -> void:
	_lean = clampf(signed, -1.0, 1.0)
	_max_lean = max_lean
	_hips_lean = hips_lean

# THE 4.7 SIGNATURE IS _with_delta. head_look.gd uses the same one; a plain
# _process_modification() is never called and the lean silently does nothing.
func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if is_zero_approx(_lean):
		return
	var total: float = _lean * _max_lean
	var hips: float = _lean * _hips_lean
	_roll_chain(skeleton, HIPS_CHAIN, hips)
	# Parent to child, poses accumulate: the spine chain must carry only what
	# the hips did not, or the torso overshoots by exactly the hips' share.
	_roll_chain(skeleton, SPINE_CHAIN, total - hips)

## Splits `radians` evenly across whichever of `chain`'s bones this skeleton
## actually has. A missing bone is skipped, never assumed: body_scene is
## optional and the whole suite runs with nothing attached.
func _roll_chain(skeleton: Skeleton3D, chain: Array[StringName], radians: float) -> void:
	var present: Array[int] = []
	for name in chain:
		var idx: int = skeleton.find_bone(name)
		if idx >= 0:
			present.append(idx)
	if present.is_empty():
		return
	var each: float = radians / float(present.size())
	var axis: Vector3 = _lean_axis(skeleton)
	for idx in present:
		var pose: Transform3D = skeleton.get_bone_global_pose(idx)
		# READ-MODIFY-WRITE, never an absolute pose. HeadLook runs in the same
		# modifier chain and multiplies onto whatever it reads; writing an
		# absolute pose here would erase its work for the frame. This is what
		# makes the two compose.
		var turn := Basis(axis, each)
		skeleton.set_bone_global_pose(idx, Transform3D(turn * pose.basis, pose.origin))

## The axis a sideways lean turns about: the character's own FORWARD.
##
## DO NOT use Vector3.FORWARD as anything but a last-resort fallback, and DO
## NOT take it from a bone's own -Z. head_look.gd's _pitch_axis() carries the
## warning this copies: a VRM faces +Z by specification, so a bone's -Z points
## out of the back of it, and a check written against that same -Z agrees with
## itself -- the mistake survives every headless verification and only shows
## up in play. Derive it from the SHOULDERS, which do not care which way the
## format decided forward is.
##
## SAME SUBTRACTION ORDER AS _pitch_axis() (right minus left), not the
## reverse. Swap it and every lean tips the wrong way: verified by flipping
## this order and watching the direction test fail (see the task report).
func _lean_axis(skeleton: Skeleton3D) -> Vector3:
	var left: int = skeleton.find_bone(&"LeftUpperArm")
	var right: int = skeleton.find_bone(&"RightUpperArm")
	if left < 0 or right < 0:
		return Vector3.FORWARD
	var across: Vector3 = skeleton.get_bone_global_pose(right).origin \
		- skeleton.get_bone_global_pose(left).origin
	across.y = 0.0
	if across.length_squared() < 0.000001:
		return Vector3.FORWARD
	return Vector3.UP.cross(across.normalized()).normalized()

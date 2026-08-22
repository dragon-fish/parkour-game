class_name HeadLook
extends SkeletonModifier3D

# Turns the head toward where the CAMERA is pointing, with the chest following
# a little.
#
# It composes with the body holding its heading while idle (see
# Player._drive_body_yaw): the divergence that produces IS what this looks
# along. Standing still and turning the camera used to swing the whole
# character; then it stopped moving at all, which reads as a mannequin. This is
# the half in between -- the body stays put and the head follows, which is what
# a person does.
#
# THE HEAD GETS THE WHOLE ANGLE, the spine only a share of it. Both are applied
# in skeleton space parent-to-child, so each bone's rotation accumulates onto
# everything below it: the spine's share plus the neck's plus the head's is what
# the head ends up at. Rotating the head by the full amount on top of a turned
# chest would overshoot by exactly the chest's contribution.
#
# Worked through set_bone_global_pose rather than by composing local rotations,
# for the reason TorsoTwist gives: a humanoid bone's local axes are whatever its
# rest pose made them, and getting that wrong bends the body somewhere
# unrelated -- which this project cannot see, only measure.

## Takes the share of the yaw named by SPINE_SHARE_DEG, split evenly.
##
## STARTS AT Spine, not Chest, and the owner is the reason: "the head's pitch
## should pivot at the joint with the NECK, and the upper body around the
## PELVIS -- not around their own centres."
##
## Each bone here is rotated about its OWN origin, which for a bone is its
## joint, so the lowest one in the chain decides where the lean originates.
## Chest alone would hinge the torso at the chest, which reads as a shrug.
## Spine's origin sits just above the hips, which is where a person actually
## bends from.
const SPINE_CHAIN: Array[StringName] = [&"Spine", &"Chest", &"UpperChest"]
## Takes the remainder, split evenly, so the head arrives at the full angle.
## Neck and Head both pivot at their own joints, which puts the head's own
## tilt at the base of the skull rather than somewhere inside it.
const HEAD_CHAIN: Array[StringName] = [&"Neck", &"Head"]

## How much of the yaw the upper body is allowed to contribute, in degrees. The
## owner's number: enough that the shoulders read as following, not enough to
## look like the whole torso turned.
const SPINE_SHARE_DEG := 15.0
## And of the pitch, which is ASYMMETRIC. Looking up wants very little: a chest
## that tips back with every glance upward reads as a bow. Looking down wants a
## lot more, and the owner found out why by watching it -- with too little the
## head rotates down INTO its own chest instead of the body folding out of the
## way. A neck alone cannot look at your own feet.
const SPINE_PITCH_UP_DEG := 8.0
const SPINE_PITCH_DOWN_DEG := 22.0

## How far the head will turn at all. Past this it holds, because a neck does
## not go further.
const YAW_LIMIT_DEG := 90.0

## And where it gives up entirely and faces forward again.
##
## The owner's shape, and the HOLD between the two is the point: the head
## reaches its limit at 90 and STAYS there while the camera carries on to 110,
## which is what looking over your shoulder is. Only past that does it decide
## the angle is not worth keeping and unwind.
const RELEASE_START_DEG := 110.0
const RELEASE_END_DEG := 120.0

## How fast the head follows, in radians per second. Fast enough to feel
## attached to the camera, slow enough that a flick does not snap it.
const RATE := 10.0

var _wanted_yaw: float = 0.0
var _wanted_pitch: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0

## Asks the head to look `yaw` from the body's own heading and `pitch` up or
## down, both in radians. Driven by Player every physics tick; see
## Player._drive_head_look().
func request(yaw: float, pitch: float) -> void:
	# RELEASED PAST A QUARTER TURN, and eased out rather than cut: at exactly
	# the limit a hard cutoff would drop the head from fully turned to forward
	# in one frame, every time the player swept past it.
	var away: float = absf(yaw)
	var weight: float = 1.0 - smoothstep( \
		deg_to_rad(RELEASE_START_DEG), deg_to_rad(RELEASE_END_DEG), away)
	# CLAMPED FIRST, then released. The clamp is what makes the head hold at
	# its limit while the camera keeps going, rather than following all the
	# way round and only then letting go.
	var limit: float = deg_to_rad(YAW_LIMIT_DEG)
	_wanted_yaw = clampf(yaw, -limit, limit) * weight
	_wanted_pitch = pitch * weight

## What is actually applied right now, for tests and the debug HUD.
func applied() -> Vector2:
	return Vector2(_yaw, _pitch)

func _process_modification_with_delta(delta: float) -> void:
	# NOT scaled by influence here: Skeleton3D applies that itself to every pose
	# a modifier sets. The class reference says so outright.
	var step: float = RATE * delta
	_yaw = move_toward(_yaw, _wanted_yaw, step)
	_pitch = move_toward(_pitch, _wanted_pitch, step)
	if is_zero_approx(_yaw) and is_zero_approx(_pitch):
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var spine_yaw: float = clampf(_yaw, \
		-deg_to_rad(SPINE_SHARE_DEG), deg_to_rad(SPINE_SHARE_DEG))
	# Looking DOWN is where the body has to get out of the way; looking up it
	# only has to not lean back. See SPINE_PITCH_DOWN_DEG.
	var pitch_share: float = deg_to_rad( \
		SPINE_PITCH_DOWN_DEG if _pitch < 0.0 else SPINE_PITCH_UP_DEG)
	var spine_pitch: float = clampf(_pitch, -pitch_share, pitch_share)
	_apply(skeleton, SPINE_CHAIN, spine_yaw, spine_pitch)
	# The remainder, so the head lands on the full angle rather than on the
	# angle plus whatever the spine already contributed.
	_apply(skeleton, HEAD_CHAIN, _yaw - spine_yaw, _pitch - spine_pitch)

## Spreads `yaw` and `pitch` evenly across `chain`, parent to child.
func _apply(skeleton: Skeleton3D, chain: Array[StringName], yaw: float, pitch: float) -> void:
	var present: Array[int] = []
	for name in chain:
		var index: int = skeleton.find_bone(name)
		if index >= 0:
			present.append(index)
	if present.is_empty():
		return
	var share: float = 1.0 / float(present.size())
	# Yaw about UP is the same rotation whatever the rest pose is. Pitch is
	# about the model's own right, taken from the bone being turned rather than
	# assumed, so a body mounted facing either way tips the correct way.
	var axis: Vector3 = _pitch_axis(skeleton)
	for index in present:
		var pose: Transform3D = skeleton.get_bone_global_pose(index)
		var turn := Basis(Vector3.UP, yaw * share) * Basis(axis, pitch * share)
		skeleton.set_bone_global_pose(index, Transform3D(turn * pose.basis, pose.origin))

## The character's own left-to-right axis, taken from the SHOULDERS.
##
## Not from a bone's -Z, which is what a first attempt used and got backwards:
## a VRM faces +Z by specification, so a head bone's -Z points out of the BACK
## of the skull, and pitching about a vector derived from it tips the face the
## wrong way. Worse, the check that was supposed to catch this read the same -Z
## and therefore agreed with itself -- it took the owner playing it to notice.
##
## The shoulders do not care which way the format decided forward is.
func _pitch_axis(skeleton: Skeleton3D) -> Vector3:
	var left: int = skeleton.find_bone(&"LeftUpperArm")
	var right: int = skeleton.find_bone(&"RightUpperArm")
	if left < 0 or right < 0:
		return Vector3.RIGHT
	var across: Vector3 = skeleton.get_bone_global_pose(right).origin 		- skeleton.get_bone_global_pose(left).origin
	across.y = 0.0
	if across.length_squared() < 0.0001:
		return Vector3.RIGHT
	return across.normalized()

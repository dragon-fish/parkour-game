class_name TorsoTwist
extends SkeletonModifier3D

# Lets the legs point where the body is GOING while the torso keeps facing where
# it is LOOKING.
#
# In this project the body's facing is the view's, so holding forward-and-left
# moves the character diagonally with the legs still aimed straight ahead. The
# owner asked for the obvious correction: turn the lower half toward the travel
# direction and leave the upper half alone.
#
# The honest version of this is eight-directional locomotion clips, where the
# feet really do step sideways -- those live in the animation pack's paid tier.
# This is the free half of the effect: the hips rotate and the spine unwinds the
# same amount back, so the shoulders end up where they started. Nothing steps
# sideways, but nothing points the wrong way either.
#
# WORKED IN SKELETON SPACE, via set_bone_global_pose, rather than by composing
# local bone rotations. A humanoid bone's local axes are whatever its rest pose
# made them, and getting that wrong produces a body bent in some unrelated
# direction -- which is not something this project can see, only measure. A
# global-space twist about UP is the same rotation whatever the rest pose is,
# and test_torso_twist.gd checks it by reading the resulting global bases.

## Rotated toward the travel direction.
const HIPS := &"Hips"

## Unwound, in order, so the twist fades out up the spine instead of happening
## at one joint. Each takes an equal share, and because each inherits its
## parent's correction the shares accumulate to exactly the hips' rotation --
## leaving the topmost bone facing where it began.
const COUNTER_CHAIN: Array[StringName] = [&"Spine", &"Chest", &"UpperChest"]

## How fast the twist follows a change of direction, in radians per second.
## Slow enough that a flick of the stick does not snap the hips, fast enough to
## have arrived within a step.
const RATE := 6.0

var _wanted: float = 0.0
var _twist: float = 0.0

## Asks for `radians` of twist, positive turning the hips to the character's
## left. Driven by Player every physics tick; see Player._drive_torso_twist().
func request(radians: float) -> void:
	_wanted = radians

## How much twist is actually applied right now, for tests and the debug HUD.
func applied() -> float:
	return _twist

func _process_modification_with_delta(delta: float) -> void:
	# NOT scaled by influence here: Skeleton3D applies that itself to every pose
	# a modifier sets, and doing it twice would halve at half influence and
	# quarter it at a quarter. The class reference says so outright.
	_twist = move_toward(_twist, _wanted, RATE * delta)
	if is_zero_approx(_twist):
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var hips: int = skeleton.find_bone(HIPS)
	if hips < 0:
		return

	var spin := Basis(Vector3.UP, _twist)
	var hips_pose: Transform3D = skeleton.get_bone_global_pose(hips)
	skeleton.set_bone_global_pose(hips, Transform3D(spin * hips_pose.basis, hips_pose.origin))

	# Walked parent-to-child on purpose: each bone's global pose already carries
	# every correction above it, so an equal share each is what adds up.
	var present: Array[int] = []
	for name in COUNTER_CHAIN:
		var index: int = skeleton.find_bone(name)
		if index >= 0:
			present.append(index)
	if present.is_empty():
		return
	var share := Basis(Vector3.UP, -_twist / float(present.size()))
	for index in present:
		var pose: Transform3D = skeleton.get_bone_global_pose(index)
		skeleton.set_bone_global_pose(index, Transform3D(share * pose.basis, pose.origin))

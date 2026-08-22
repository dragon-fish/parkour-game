class_name Ragdoll
extends RefCounted

# Turns the visible body over to the physics engine, once, on the way out.
#
# ✅ The owner: "make a ragdoll mode, let's have some fun -- making games is
# supposed to be fun, who cares if it makes you sick." And on the awkward part,
# which is that a ragdoll is a one-way door: "we can black the screen for a
# moment on respawn. Games and film are the art of deception; if you cannot do
# it well, cover it up."
#
# So this does not try to blend back. It hands the skeleton to the solver, lets
# it fall over, and the respawn hides the return behind a cut.
#
# WHY IT IS BUILT AT RUNTIME rather than authored into the model: no character
# model is tracked in this repository (see NOTICE.md), so there is nothing to
# author it into. The rig is read for what it has and the bodies are generated
# from the rest pose, which also means a different model needs no work.
#
# ⚠️ A CURATED TWELVE, not every bone. Godot's own "create physical skeleton"
# gives one body per bone, and a VRM has 65 -- including every finger joint and
# every strand of hair. Twelve is a person: torso, head, and two segments per
# limb.

## The bones that get a body, and the bone each one measures itself against.
## A capsule needs a length, and a bone's length is the distance to its child.
const SEGMENTS: Array = [
	[&"Hips", &"Spine", 12.0],
	[&"Spine", &"Chest", 10.0],
	[&"Chest", &"Neck", 12.0],
	[&"Head", &"", 4.0],
	[&"LeftUpperArm", &"LeftLowerArm", 3.0],
	[&"LeftLowerArm", &"LeftHand", 2.0],
	[&"RightUpperArm", &"RightLowerArm", 3.0],
	[&"RightLowerArm", &"RightHand", 2.0],
	[&"LeftUpperLeg", &"LeftLowerLeg", 6.0],
	[&"LeftLowerLeg", &"LeftFoot", 4.0],
	[&"RightUpperLeg", &"RightLowerLeg", 6.0],
	[&"RightLowerLeg", &"RightFoot", 4.0],
]

## A bone with no child to measure against -- the head -- gets this, in metres
## of the model's own scale.
const STUB_LENGTH := 0.18
## Capsule radius as a fraction of the segment's length, so an arm is thinner
## than a thigh without a table of radii to maintain.
const RADIUS_RATIO := 0.28
const RADIUS_MIN := 0.04
const RADIUS_MAX := 0.14

var _skeleton: Skeleton3D = null
var _built := false
var _simulating := false

func is_simulating() -> bool:
	return _simulating

## Generates the bodies. Safe to call more than once; only the first does work.
##
## Returns false for a body this cannot be built on -- no skeleton, or one whose
## bones are not named like a humanoid -- which every non-VRM body in this
## project is, including the Blockbench one whose bones are named after cubes.
func build(skeleton: Skeleton3D) -> bool:
	if _built:
		return _skeleton != null
	_built = true
	if skeleton == null or skeleton.find_bone(&"Hips") < 0:
		return false
	_skeleton = skeleton
	for segment in SEGMENTS:
		_add_segment(segment[0], segment[1], float(segment[2]))
	return true

## Hands the skeleton to the solver and shoves it, so a death has some direction
## to it rather than folding straight down.
##
## `exclude` is the player's own collision body: without it the ragdoll spawns
## inside the capsule that is still standing there and is fired across the level.
func start(impulse: Vector3, exclude: RID) -> void:
	if _skeleton == null or _simulating:
		return
	_simulating = true
	_skeleton.physical_bones_add_collision_exception(exclude)
	_skeleton.physical_bones_start_simulation()
	# Applied to the HIPS alone. Shoving every bone gives an explosion rather
	# than a fall -- the joints are what should carry it to the limbs.
	var hips := _bone_node(&"Hips")
	if hips != null:
		hips.apply_central_impulse(impulse)

## Gives the skeleton back to the animation. The pose it is left in is whatever
## physics chose, which is the part the respawn's black screen covers.
func stop() -> void:
	if _skeleton == null or not _simulating:
		return
	_simulating = false
	_skeleton.physical_bones_stop_simulation()

# --- building ------------------------------------------------------------------

func _add_segment(bone: StringName, child: StringName, mass: float) -> void:
	var index: int = _skeleton.find_bone(bone)
	if index < 0:
		return
	var rest: Transform3D = _skeleton.get_bone_global_rest(index)
	# The segment runs from this bone to its child. Measured in the BONE's own
	# space, because that is where the collision shape is placed.
	var along := Vector3(0.0, STUB_LENGTH, 0.0)
	var child_index: int = _skeleton.find_bone(child) if child != &"" else -1
	if child_index >= 0:
		var child_rest: Transform3D = _skeleton.get_bone_global_rest(child_index)
		along = rest.basis.inverse() * (child_rest.origin - rest.origin)
	var length: float = maxf(along.length(), 0.02)

	var body := PhysicalBone3D.new()
	body.name = String(bone) + "Physical"
	body.bone_name = String(bone)
	body.transform = rest
	body.mass = mass
	# CONE everywhere except the root, which is what holds a body together
	# without letting an elbow bend backwards through the arm. The hips have
	# nothing above them to be jointed TO.
	body.joint_type = PhysicalBone3D.JOINT_TYPE_NONE if bone == &"Hips" \
			else PhysicalBone3D.JOINT_TYPE_CONE
	# A little damping, or a dead body keeps twitching on the floor forever.
	body.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.2
	body.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	body.angular_damp = 1.0

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = clampf(length * RADIUS_RATIO, RADIUS_MIN, RADIUS_MAX)
	# height is the WHOLE capsule, caps included, so a segment shorter than two
	# radii would be an invalid shape rather than a short one.
	capsule.height = maxf(length, capsule.radius * 2.0 + 0.01)
	shape.shape = capsule
	# Halfway down the segment, with the capsule's own Y axis turned to lie
	# along it.
	shape.transform = Transform3D(_basis_along(along), along * 0.5)
	body.add_child(shape)
	_skeleton.add_child(body)

## A basis whose Y axis points along `direction`. A capsule is built along Y, so
## this is what lays it down the bone instead of standing it up in the middle.
func _basis_along(direction: Vector3) -> Basis:
	var y: Vector3 = direction.normalized()
	if y.length_squared() < 0.5:
		return Basis.IDENTITY
	var x: Vector3 = y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y))

func _bone_node(bone: StringName) -> PhysicalBone3D:
	if _skeleton == null:
		return null
	return _skeleton.get_node_or_null(String(bone) + "Physical") as PhysicalBone3D

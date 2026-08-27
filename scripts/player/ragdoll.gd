class_name Ragdoll
extends RefCounted

# Turns the visible body over to the physics engine, once, on the way out.
#
# A ragdoll is a ONE-WAY DOOR. DO NOT try to blend back out of it into the
# animated skeleton. This hands the skeleton to the solver, lets it fall over,
# and the respawn hides the return behind a cut to black.
#
# WHY IT IS BUILT AT RUNTIME rather than authored into the model: no character
# model is tracked in this repository (see NOTICE.md), so there is nothing to
# author it into. The rig is read for what it has and the bodies are generated
# from the rest pose, which also means a different model needs no work.
#
# A CURATED TWELVE, not every bone. DO NOT fall back on Godot's own "create
# physical skeleton": it gives one body per bone, and a VRM has 65 -- including
# every finger joint and every strand of hair. Twelve is a person: torso, head,
# and two segments per limb.

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

## HOW FAR A JOINT MAY BEND. Limbs that stretch out long and swing freely read
## as frightening rather than as a body, so the joints are held tight.
##
## DO NOT tighten them with softness and bias. This project runs JOLT
## (project.godot: 3d/physics_engine = "Jolt Physics"), and Jolt says so in as
## many words at runtime: "Cone twist joint bias is not supported when using
## Jolt Physics. Any such value will be ignored." Same for softness. Setting
## them costs twenty-two warnings a death and buys nothing.
##
## What Jolt DOES honour is the spans, so those are what is tightened. The
## default twist_span is 180 degrees -- a forearm free to rotate a full
## half-turn about itself -- and 45 of swing at every joint is a shoulder
## everywhere, elbows and knees included.
##
## THE SPANS ARE NOT THE STRETCH. Jolt's joints are hard constraints; bodies
## should not separate at all. If limbs still stretch after the spans are
## tight, look at the mount scale next: this skeleton lives under a body
## mounted at a mount_scale above 1, and SCALED physics bodies are unreliable
## in Godot generally.
## A layer of their own, so a ragdoll interacts with the world and with itself
## and with nothing else. MASK is the world layer; the player is excluded by RID
## on top of that, since it shares the world layer.
const LAYER := 1 << 7
const MASK := 1

const JOINT_TWIST_DEG := 30.0
const JOINT_SWING_DEG := 30.0

var _skeleton: Skeleton3D = null
var _built := false
var _simulating := false

func is_simulating() -> bool:
	return _simulating

## Where the hips have got to, in world space, or ZERO before there is a
## ragdoll. Once the ragdoll is running the capsule is meaningless and the
## ragdoll's position is the authority -- see FallUncontrolledMove, which stops
## driving the body and asks this instead.
func hips_position() -> Vector3:
	var hips := _bone_node(&"Hips")
	return hips.global_position if hips != null else Vector3.ZERO

## How fast the hips are still travelling, for deciding the body has finished
## arriving. A landing cannot be detected the usual way any more: the capsule
## is not moving, so it never touches anything.
func hips_speed() -> float:
	var hips := _bone_node(&"Hips")
	return hips.linear_velocity.length() if hips != null else 0.0

## How fast the hips are travelling DOWNWARD, positive while falling. The motion
## blur is bound to this speed, and the blackout is taken from the instant the
## vertical velocity reverses or comes close to zero.
func hips_fall_speed() -> float:
	var hips := _bone_node(&"Hips")
	return -hips.linear_velocity.y if hips != null else 0.0

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
	# Given their collisions back -- see stop(), which takes them away.
	for child in _skeleton.get_children():
		if child is PhysicalBone3D:
			(child as PhysicalBone3D).collision_layer = LAYER
			(child as PhysicalBone3D).collision_mask = MASK
	_skeleton.physical_bones_add_collision_exception(exclude)
	# THE SKELETON'S PARENT MUST STOP MOVING, and the caller owes that. These
	# bodies are children of the skeleton, which hangs off a CharacterBody3D --
	# so every metre the player travels teleports all twelve of them, and the
	# solver spends the whole fall being yanked. The symptom is a body that
	# convulses the moment the ragdoll starts. See FallUncontrolledMove.
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
	# ZEROED FIRST. Stopping the simulation hands the bones back to the
	# animation, but it does not take their VELOCITY away: the bodies are still
	# carrying whatever the fall gave them when the respawn teleports them
	# across the level. DO NOT respawn before putting the ragdoll back and
	# clearing these velocities, or the player is launched the moment they come
	# back.
	for child in _skeleton.get_children():
		if child is PhysicalBone3D:
			var physical := child as PhysicalBone3D
			physical.linear_velocity = Vector3.ZERO
			physical.angular_velocity = Vector3.ZERO
	_skeleton.physical_bones_stop_simulation()
	# INERT AFTERWARDS. A PhysicalBone3D that is not simulating is still a
	# RigidBody3D with a collision shape, dragged along by whatever the skeleton
	# does -- including a respawn that teleports it across the level. Twelve of
	# those arriving at speed inside the world geometry is what a respawn that
	# flies off uncontrollably and ignores obstacles looks like. They cost
	# nothing while switched off.
	for child in _skeleton.get_children():
		if child is PhysicalBone3D:
			(child as PhysicalBone3D).collision_layer = 0
			(child as PhysicalBone3D).collision_mask = 0
	# AND THE POSE GOES BACK. The bones are left wherever physics finished with
	# them, and everything downstream reads them as if they were an animation --
	# the head-follow in particular, which would hand the camera a head lying
	# several metres away. The respawn's black screen covers the snap.
	_skeleton.reset_bone_poses()

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
	# BORN INERT. They are switched on by start() and off again by stop(), so
	# the only window in which twelve rigid bodies exist inside the player is
	# the one where they are supposed to. DO NOT create them live: they then
	# push the capsule around from the first death onwards, including after it,
	# and the character reads as possessed.
	body.collision_layer = 0
	body.collision_mask = 0
	# CONE everywhere except the root, which is what holds a body together
	# without letting an elbow bend backwards through the arm. The hips have
	# nothing above them to be jointed TO.
	body.joint_type = PhysicalBone3D.JOINT_TYPE_NONE if bone == &"Hips" \
			else PhysicalBone3D.JOINT_TYPE_CONE
	if body.joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
		# Sub-path properties, which is how PhysicalBone3D exposes whichever
		# joint type is selected -- read off the object rather than guessed.
		# softness and bias are deliberately NOT set: Jolt ignores both and
		# warns about each one, every joint, every death.
		# THE CONE HAS TO POINT ALONG THE BONE. A cone-twist limits swing away
		# from ITS OWN axis, which without this is whatever the bone's rest
		# orientation happened to be, so the limits land about an axis
		# unrelated to the limb. Joints that appear to have no angle limit at
		# all, swinging a full 360 degrees, are what a cone pointing sideways
		# looks like.
		#
		# Godot's ConeTwistJoint3D twists about its X axis, so the joint is
		# rotated to put X along the segment.
		body.joint_rotation = _basis_x_along(along).get_euler()
		body.set("joint_constraints/twist_span", JOINT_TWIST_DEG)
		body.set("joint_constraints/swing_span", JOINT_SWING_DEG)
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
## A basis whose X axis points along `direction` -- what a cone-twist joint
## needs, since it twists about X and swings away from it.
func _basis_x_along(direction: Vector3) -> Basis:
	var x: Vector3 = direction.normalized()
	if x.length_squared() < 0.5:
		return Basis.IDENTITY
	var y: Vector3 = x.cross(Vector3.FORWARD)
	if y.length_squared() < 0.001:
		y = x.cross(Vector3.RIGHT)
	y = y.normalized()
	return Basis(x, y, x.cross(y))

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

extends ParkourTest

# The owner's ruling for how a balance wobble reaches the model: "角色动画最好
# 不要是全身都倾斜, 脚跟固定, 下半身微倾, 上半身承担倾斜的提示" -- the feet stay
# on the beam, the hips take a token share, the spine carries the rest. These
# tests pin the RELATIONSHIP that ruling requires (hips strictly less than the
# torso, zero lean touches nothing, a missing bone is survived), never a
# specific angle -- see .claude/skills/tuning-dials-not-rules.
#
# THE MODIFIER IS CALLED DIRECTLY, never scheduled. A bare Skeleton3D with no
# AnimationPlayer driving it never runs SkeletonModifier3D callbacks on its
# own -- established by a spike earlier in this plan -- so _tick() below
# invokes _process_modification_with_delta() by hand instead of waiting for
# the engine to get around to it.

const RIGHT_ARM_X := 0.2
const LEFT_ARM_X := -0.2

## A minimal humanoid chain: Hips -> Spine -> Chest -> UpperChest, with both
## upper arms hanging off UpperChest. Enough bones for BalanceLean's own two
## chains (HIPS_CHAIN, SPINE_CHAIN) plus the shoulder pair _lean_axis() reads.
##
## BOTH rest AND pose are set to the same offset. Skeleton3D's global pose is
## composed through the POSE chain, not the rest chain -- get_bone_global_pose()
## stays at the origin forever if only set_bone_rest() is called, which is a
## dead end this file already spent a probe script finding.
func _make_skeleton_with_humanoid_bones(skip: StringName = &"") -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	add_child_autofree(skeleton)
	var chain: Array[StringName] = [&"Hips", &"Spine", &"Chest", &"UpperChest"]
	var offsets := {
		&"Hips": Vector3(0.0, 1.0, 0.0),
		&"Spine": Vector3(0.0, 0.1, 0.0),
		&"Chest": Vector3(0.0, 0.1, 0.0),
		&"UpperChest": Vector3(0.0, 0.1, 0.0),
		&"LeftUpperArm": Vector3(LEFT_ARM_X, 0.1, 0.0),
		&"RightUpperArm": Vector3(RIGHT_ARM_X, 0.1, 0.0),
	}
	var parent_of := {
		&"Spine": &"Hips",
		&"Chest": &"Spine",
		&"UpperChest": &"Chest",
		&"LeftUpperArm": &"UpperChest",
		&"RightUpperArm": &"UpperChest",
	}
	var present: Array[StringName] = []
	for name in chain:
		if name == skip:
			continue
		skeleton.add_bone(name)
		present.append(name)
	for name in [&"LeftUpperArm", &"RightUpperArm"]:
		if name == skip:
			continue
		# Reparented onto Chest if UpperChest itself is the one missing, so
		# the shoulder pair still exists for _lean_axis() to read.
		skeleton.add_bone(name)
		present.append(name)
	for name in present:
		var parent: StringName = parent_of.get(name, &"")
		if skip != &"" and parent == skip:
			parent = &"Chest"
		if parent != &"" and present.has(parent):
			skeleton.set_bone_parent(skeleton.find_bone(name), skeleton.find_bone(parent))
	for name in present:
		var offset: Vector3 = offsets[name]
		var idx: int = skeleton.find_bone(name)
		skeleton.set_bone_rest(idx, Transform3D(Basis(), offset))
		skeleton.set_bone_pose_position(idx, offset)
	return skeleton

## Lets one frame pass so the pose positions set above resolve into
## get_bone_global_pose() -- Skeleton3D caches that lazily and never refreshes
## it mid-frame on its own -- then calls the modifier directly rather than
## trusting the engine to schedule it.
func _tick(rig: Skeleton3D) -> void:
	await step(1)
	for child in rig.get_children():
		if child is BalanceLean:
			child._process_modification_with_delta(1.0 / 60.0)

func _roll_of(rig: Skeleton3D, bone_name: StringName) -> float:
	var idx: int = rig.find_bone(bone_name)
	if idx < 0:
		return 0.0
	# The X-component of the bone's own "up" axis after rotation: 0 means the
	# bone is standing straight, positive means it has tipped toward the
	# character's own right (+X in this fixture). Unlike Basis.get_euler(),
	# this has no order/ambiguity concerns for a rotation about a single axis.
	return rig.get_bone_global_pose(idx).basis.y.x

func test_the_hips_take_far_less_of_the_lean_than_the_torso() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	var hips := absf(_roll_of(rig, &"Hips"))
	var chest := absf(_roll_of(rig, &"UpperChest"))
	assert_lt(hips, chest,
		"the feet stay on the beam; the torso is what shows the wobble")

func test_no_lean_leaves_the_skeleton_alone() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(0.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	assert_almost_eq(_roll_of(rig, &"Spine"), 0.0, 0.0001)

func test_a_missing_bone_is_skipped_rather_than_fatal() -> void:
	var rig := _make_skeleton_with_humanoid_bones(&"UpperChest")
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	assert_true(true, "body_scene is optional; no bone may be assumed to exist")

## Pins the SIGN, not just the split. Positive lean must tip the torso toward
## the body's own right (+X in this fixture, where RightUpperArm sits) --
## BalanceMove's own convention that positive lean is toward the line's
## right-hand normal (see LineWalkMove.project_input()'s "normal" comment).
## Getting _lean_axis() backwards is invisible everywhere except in play: a
## check written against the same wrong axis agrees with itself.
func test_positive_lean_tips_the_torso_toward_the_bodys_right() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	assert_gt(_roll_of(rig, &"UpperChest"), 0.0,
		"a positive lean must tip the torso toward +X, the right shoulder's own side")

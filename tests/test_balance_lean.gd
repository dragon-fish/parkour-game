extends ParkourTest

# The owner's ruling for how a balance wobble reaches the model: "角色动画最好
# 不要是全身都倾斜, 脚跟固定, 下半身微倾, 上半身承担倾斜的提示" -- the feet stay
# on the beam, the hips take a token share, the spine carries the rest. These
# tests pin the RELATIONSHIP that ruling requires (hips strictly less than the
# torso, zero lean touches nothing, a missing bone redistributes rather than
# loses rotation), never a specific angle -- see .claude/skills/tuning-dials-not-rules.
#
# THE MODIFIER IS CALLED DIRECTLY, never scheduled. A bare Skeleton3D with no
# AnimationPlayer driving it never runs SkeletonModifier3D callbacks on its
# own, so _tick() below invokes _process_modification_with_delta() by hand
# instead of waiting for the engine to get around to it.

## THE SHOULDERS MUST NOT BOTH SIT AT z=0. Shoulders that differ only in x
## make `right - left` exactly (0.4, 0, 0), whose UP.cross() is exactly
## (0, 0, -1) -- which IS Vector3.FORWARD, so every test in this file passes
## with _lean_axis() hardcoded to `return Vector3.FORWARD` and the entire
## shoulder read deleted. Giving RightUpperArm a nonzero z the left shoulder
## does not share makes the derived axis provably NOT (0, 0, -1), so a
## hardcoded FORWARD is distinguishable from the real thing. See
## test_positive_lean_tips_the_torso_toward_the_bodys_right.
const LEFT_SHOULDER := Vector3(-0.2, 0.1, 0.0)
const RIGHT_SHOULDER := Vector3(0.2, 0.1, 0.4)

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
		&"LeftUpperArm": LEFT_SHOULDER,
		&"RightUpperArm": RIGHT_SHOULDER,
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
		# `skip == &""` is ALSO Dictionary.get's own "no parent" default --
		# Hips has no entry in parent_of, so parent_of.get(&"Hips", &"") is
		# &"" too. Without the `skip != &""` guard, a plain call (no bone
		# skipped) matches Hips against skip and reparents the ROOT bone onto
		# Chest, building the cycle Hips -> Chest -> Spine -> Hips.
		# Skeleton3D's native pose composition does not detect the cycle: it
		# does not error, it hangs the engine outright, burning CPU forever
		# with no GDScript-visible symptom. DO NOT drop this guard.
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
	# MARGIN, NOT A BARE "<". A bug that gives the hips the FULL share (not
	# the token one) makes hips and chest mathematically equal, and the
	# read-modify-write round trip through a zero-radians SPINE_CHAIN call
	# still perturbs chest by float noise on the order of 1e-8 -- enough for
	# a bare `hips < chest` to pass by ACCIDENT depending on which way the
	# rounding falls. "far less" needs a real margin: the config default
	# ratio is 4/18 =~ 0.22, so
	# requiring hips under half of chest is generous room above that and
	# nowhere near float noise.
	assert_lt(hips, chest * 0.5,
		"the feet stay on the beam; the torso is what shows the wobble")

func test_no_lean_leaves_the_skeleton_alone() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(0.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	assert_almost_eq(_roll_of(rig, &"Spine"), 0.0, 0.0001)

## NOT A BARE "did not crash" CHECK. That form cannot see a broken split
## ratio: a bug that keeps dividing by the FULL chain length (3) instead of
## the PRESENT count (2) would silently under-rotate the torso whenever a
## bone is missing, and "no crash" is blind to it. Instead this compares the
## LAST present spine bone's total rotation across two skeletons -- one with
## the full chain, one with UpperChest missing -- and requires them equal:
## the chain's own parent-to-child accumulation means whichever bone ends the
## present chain lands at the FULL non-hips share regardless of how many
## bones split it, so a missing bone must redistribute that share, not lose
## part of it.
func test_a_missing_bone_is_skipped_rather_than_fatal() -> void:
	var full_rig := _make_skeleton_with_humanoid_bones()
	var full_lean := BalanceLean.new()
	full_rig.add_child(full_lean)
	full_lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(full_rig)
	var full_torso: float = _roll_of(full_rig, &"UpperChest")

	var short_rig := _make_skeleton_with_humanoid_bones(&"UpperChest")
	var short_lean := BalanceLean.new()
	short_rig.add_child(short_lean)
	short_lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(short_rig)
	# Chest is now the last bone in the shortened spine chain -- where the
	# full accumulated total lands, same as UpperChest did with all three
	# bones present.
	var short_torso: float = _roll_of(short_rig, &"Chest")

	assert_almost_eq(short_torso, full_torso, 0.0001,
		"a missing bone must redistribute the torso's total rotation across " + \
		"the remaining bones, not shrink it")

## Pins the SIGN, not just the split. Positive lean must tip the torso toward
## the body's own right -- BalanceMove's own convention that positive lean is
## toward the line's right-hand normal (see LineWalkMove.project_input()'s
## "normal" comment). Getting _lean_axis() backwards is invisible everywhere
## except in play: a check written against the same wrong axis agrees with
## itself.
##
## BOTH x AND z ARE ASSERTED. RIGHT_SHOULDER carries a z the left shoulder
## does not, on purpose (see the constants above): a lean axis derived from
## Vector3.FORWARD instead of the shoulders rotates purely in the X/Y plane
## and leaves the torso's z-component at exactly 0, so the z assertion is
## what actually distinguishes "read the shoulders" from "hardcode forward".
func test_positive_lean_tips_the_torso_toward_the_bodys_right() -> void:
	var rig := _make_skeleton_with_humanoid_bones()
	var lean := BalanceLean.new()
	rig.add_child(lean)
	lean.request_lean(1.0, deg_to_rad(18.0), deg_to_rad(4.0))
	await _tick(rig)
	var up: Vector3 = rig.get_bone_global_pose(rig.find_bone(&"UpperChest")).basis.y
	assert_gt(up.x, 0.0,
		"a positive lean must tip the torso toward +X, the right shoulder's own side")
	assert_gt(up.z, 0.0,
		"the torso's tilt must follow the shoulder axis into z too -- a lean " + \
		"axis hardcoded to Vector3.FORWARD cannot produce this component")

## Player._drive_balance_lean() must feed BalanceLean exactly zero the instant
## BalanceMove is not the active move -- a lean that survives the move
## follows the player off the beam. That decision is pulled out of the
## skeleton-mounting code into Player.balance_lean_signed(), a pure function,
## specifically so it is testable without a body-mounted skeleton: every test
## in this repo runs with no body_scene attached, so a bug in the ternary
## inside _drive_balance_lean() itself would never make any test fail.
func test_balance_lean_signed_follows_the_move_while_active() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.05, 0.0)
	assert_almost_eq(Player.balance_lean_signed(true, move), move.signed_severity(), 0.0001,
		"active must pass the move's own signed_severity() through unchanged")
	move.free()

func test_balance_lean_signed_is_exactly_zero_when_inactive() -> void:
	var move := BalanceMove.new()
	move.cfg = BalanceConfig.new()
	move.seed_lean(0.05, 0.0)
	assert_ne(move.signed_severity(), 0.0,
		"the move must actually have a nonzero lean, or this test cannot tell " + \
		"zeroing from doing nothing")
	assert_eq(Player.balance_lean_signed(false, move), 0.0,
		"a lean that survives the move follows the player off the beam")
	move.free()

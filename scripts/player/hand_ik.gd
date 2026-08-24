class_name HandIK
extends Node

# LIVE, AND THE SOLVER WAS INNOCENT ALL ALONG. This spent two sessions written
# off -- first as "does not move the bones, 0.0000 m" (get_bone_global_pose()
# reads the pose from BEFORE the deferred modifier pass; the final one needs
# the modification_processed signal), then as "overshoots by 1.32 m" (a probe
# whose lambda captured its sample variable BY VALUE, reading back a zero that
# sat |target| from every target, with targets on the wrong side of the body
# besides). Measured correctly, TwoBoneIK3D lands the hand on the target to
# the millimetre -- see test_hand_ik.gd's own history note.
#
# The first caller is the wall touch: Player._drive_wall_touch() rests a palm
# on walls walked past. See docs/feel-backlog.md 47/54 for the archaeology.

# Puts the hands ON the thing the body is climbing over.
#
# WHY THIS EXISTS AT ALL is the owner's own principle, already written down in
# docs/contact-drives-movement.md: every direction change in the original reads
# as a hand or a foot touching something. This project honours that in the
# MOVEMENT -- nothing moves until contact -- but the body's animation knows
# nothing about it. A vault clip authored against one obstacle plays identically
# against every other, so the hands pass through the ledge, or wave above it.
#
# NOTHING HAPPENS UNTIL A MOVE ASKS. influence starts at zero and the modifier
# is inactive, so a body with this attached animates exactly as it would
# without. reach() is the only thing that turns it on, release() the only thing
# that turns it off, and both ramp rather than cut -- a hand that snaps onto a
# ledge is a worse artefact than one that misses it.
#
# ONE CHAIN PER ARM, both in a single TwoBoneIK3D: the class takes an index per
# setting precisely so related chains share a modifier and therefore a solve
# order.

## Godot's humanoid profile names, which is what the skeleton carries after the
## import-time retarget (see tools/build_ual_bone_map.gd). A body whose skeleton
## does not have them simply gets no IK -- see attach().
const CHAINS := [
	{"root": "LeftUpperArm", "middle": "LeftLowerArm", "end": "LeftHand"},
	{"root": "RightUpperArm", "middle": "RightLowerArm", "end": "RightHand"},
]
const LEFT := 0
const RIGHT := 1

## How fast influence travels between 0 and 1, in units per second. Fast enough
## to have arrived by the time a vault's hands would be planted, slow enough
## that the arm is never seen to jump.
const BLEND_SPEED := 6.0

## The elbow hint, in metres from the target: down and back, which is where an
## elbow goes when a hand reaches forward and takes weight. Away from the body's
## centre line on each side, so the arms do not fold into the chest.
const POLE_OFFSET := Vector3(0.35, -0.45, 0.35)

var _modifier: TwoBoneIK3D = null
var _skeleton: Skeleton3D = null
var _targets: Array[Node3D] = []
var _poles: Array[Node3D] = []
var _wanted: Array[float] = [0.0, 0.0]
var _influence: Array[float] = [0.0, 0.0]

## Builds the chains on `skeleton`, or does nothing at all if it is not a
## humanoid this can drive.
##
## Returns true only if the IK is live. A caller does not have to check: every
## other method here is safe on a HandIK that found nothing, which is the same
## stance the rest of the body pipeline takes -- a model that cannot be
## animated stands still rather than crashing.
func attach(skeleton: Skeleton3D) -> bool:
	if skeleton == null:
		return false
	for chain in CHAINS:
		for role in ["root", "middle", "end"]:
			if skeleton.find_bone(chain[role]) < 0:
				return false

	# PHYSICS, not the IDLE this defaults to -- and this project has been caught
	# by the identical default once already, on AnimationTree (see
	# Player._wire_body_animation, which sets its process_callback for the same
	# reason). Everything here runs on physics ticks, and the headless test loop
	# has nothing else, so a modifier left on idle solves for a pose nobody
	# looks at. The symptom is not an error: the solver reports active with full
	# influence and the hand simply never moves, measured at exactly 0.0000 m.
	skeleton.modifier_callback_mode_process = 		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

	_modifier = TwoBoneIK3D.new()
	_modifier.name = "HandIK"
	skeleton.add_child(_modifier)
	_modifier.setting_count = CHAINS.size()

	for i in CHAINS.size():
		var target := Node3D.new()
		target.name = "HandTarget%d" % i
		var pole := Node3D.new()
		pole.name = "HandPole%d" % i
		_modifier.add_child(target)
		_modifier.add_child(pole)
		_targets.append(target)
		_poles.append(pole)

		_modifier.set_root_bone_name(i, CHAINS[i]["root"])
		_modifier.set_middle_bone_name(i, CHAINS[i]["middle"])
		_modifier.set_end_bone_name(i, CHAINS[i]["end"])
		_modifier.set_target_node(i, _modifier.get_path_to(target))
		_modifier.set_pole_node(i, _modifier.get_path_to(pole))

	# Off until asked. Both of these, not just one: influence 0 with the
	# modifier active still costs a solve every frame for a result that is
	# thrown away.
	_modifier.influence = 0.0
	_modifier.active = false
	_skeleton = skeleton
	_arm_length = (skeleton.get_bone_global_rest(
			skeleton.find_bone(CHAINS[RIGHT]["end"])).origin
		- skeleton.get_bone_global_rest(
			skeleton.find_bone(CHAINS[RIGHT]["root"])).origin).length()
	_shoulder_half = 0.5 * (skeleton.get_bone_global_rest(
			skeleton.find_bone(CHAINS[RIGHT]["root"])).origin
		- skeleton.get_bone_global_rest(
			skeleton.find_bone(CHAINS[LEFT]["root"])).origin).length()
	return true

## True when there are chains to drive.
func is_live() -> bool:
	return _modifier != null

## Upper-arm-to-hand rest length, in SKELETON space (multiply by the mount
## scale for metres of world). Measured off the rig rather than configured:
## "how far can the arm reach" is a fact about the body, the same stance
## Move.CONTACT_MARGIN takes about arm-length knobs.
var _arm_length: float = 0.0

func arm_length() -> float:
	return _arm_length

## Half the distance between the two upper-arm roots, in SKELETON space --
## where each arm actually hangs from. Measured off the rig, same stance as
## arm_length(): ✅ THE OWNER, on rays cast from the capsule's axis: "你忽略了
## 肩宽，你把两个手臂从模型中轴伸了出来."
var _shoulder_half: float = 0.0

func shoulder_half() -> float:
	return _shoulder_half

## Sends a hand to `world_point` and blends the IK in.
##
## `side` is LEFT or RIGHT. The point is in WORLD space on purpose: every caller
## has one from a probe -- the obstacle top, the ledge, the wall face -- and
## none of them naturally has anything in the body's local space.
func reach(side: int, world_point: Vector3) -> void:
	if _modifier == null or side < 0 or side >= _targets.size():
		return
	_targets[side].global_position = world_point
	# The elbow hint, in SKELETON space so it turns with the body -- a
	# world-frame offset only pointed outward at one particular yaw. VRM model
	# space has +x on the character's own LEFT (T-pose, authored facing +z),
	# so LEFT keeps POLE_OFFSET.x and RIGHT mirrors it; the first cut had the
	# sign backwards AND unrotated, which folded both elbows across the torso
	# -- the owner's "右手扭曲".
	var mirrored := POLE_OFFSET
	if side == RIGHT:
		mirrored.x = -mirrored.x
	_poles[side].global_position = world_point \
		+ _skeleton.global_transform.basis * mirrored
	_wanted[side] = 1.0
	_modifier.active = true

## Hands the arm back to the animation. Ramps, so the arm eases off the ledge
## rather than being dropped from it.
func release(side: int = -1) -> void:
	if side < 0:
		_wanted[LEFT] = 0.0
		_wanted[RIGHT] = 0.0
		return
	if side < _wanted.size():
		_wanted[side] = 0.0

## Advances the blend. Driven by Player every physics tick.
##
## TwoBoneIK3D carries ONE influence for the whole modifier, while the two arms
## are asked for independently, so what is applied is the stronger of the two.
## An arm that was not asked for still has its target sitting wherever it was
## last put -- which is why the modifier is switched off entirely once both have
## faded, rather than left running at zero.
func update(delta: float) -> void:
	if _modifier == null:
		return
	var step: float = BLEND_SPEED * delta
	for i in _influence.size():
		_influence[i] = move_toward(_influence[i], _wanted[i], step)
	var strongest: float = maxf(_influence[LEFT], _influence[RIGHT])
	# ⚠️ THE SHARED INFLUENCE DRIVES BOTH CHAINS, so an arm nobody asked for is
	# still solved at full strength toward wherever its target happens to sit
	# -- unset, that is the modifier's own origin, and the idle arm wrenches
	# across the torso (the owner: "右手扭曲到了身体左侧"). Pinning the idle
	# side's target to the hand's OWN pre-modifier (animated) position makes a
	# full-strength solve a no-op: the solver puts the hand exactly where the
	# animation already had it.
	for i in _influence.size():
		if _wanted[i] <= 0.0 and _influence[i] <= 0.0:
			var hand: int = _skeleton.find_bone(CHAINS[i]["end"])
			_targets[i].global_position = _skeleton.global_transform \
				* _skeleton.get_bone_global_pose(hand).origin
	_modifier.influence = strongest
	if is_zero_approx(strongest):
		_modifier.active = false

## Diagnostics for tests and the debug HUD.
func debug() -> Dictionary:
	return {
		"live": _modifier != null,
		"active": _modifier != null and _modifier.active,
		"influence": 0.0 if _modifier == null else _modifier.influence,
		"left": _influence[LEFT],
		"right": _influence[RIGHT],
	}

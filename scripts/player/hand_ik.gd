class_name HandIK
extends Node

# UNFINISHED, AND DELIBERATELY INERT. The chains build, the blend ramps, and
# the modifier switches itself on and off correctly. The solver runs -- and
# sends the hand about 1.32 m from where it was aimed, roughly three arm
# lengths.
#
# DO NOT measure a modifier's effect with Skeleton3D.get_bone_global_pose():
# it returns the pose from BEFORE the deferred modifier pass, so a working
# modifier reads as moving the bones exactly 0.0000 m and looks dead. Reading
# the final pose needs the modification_processed signal.
#
# First suspect for the overshoot is POLE_OFFSET: it places the elbow hint
# relative to the TARGET, which for a target close to the body lands inside the
# torso, and a two-bone solver given a degenerate pole can flip its whole
# solution plane. Nothing calls reach(), so this costs nothing until someone
# picks it up. See docs/feel-backlog.md 47.

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
	return true

## True when there are chains to drive.
func is_live() -> bool:
	return _modifier != null

## Sends a hand to `world_point` and blends the IK in.
##
## `side` is LEFT or RIGHT. The point is in WORLD space on purpose: every caller
## has one from a probe -- the obstacle top, the ledge, the wall face -- and
## none of them naturally has anything in the body's local space.
func reach(side: int, world_point: Vector3) -> void:
	if _modifier == null or side < 0 or side >= _targets.size():
		return
	_targets[side].global_position = world_point
	# The elbow hint mirrors on the left so both arms bend outward rather than
	# both toward the same shoulder.
	var mirrored := POLE_OFFSET
	if side == LEFT:
		mirrored.x = -mirrored.x
	_poles[side].global_position = world_point + mirrored
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

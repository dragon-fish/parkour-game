class_name BoneSplay
extends SkeletonModifier3D

# Swings named bones OUTWARD from the body's median plane, on top of whatever
# the animation is doing. The corrective additive pose that a retarget cannot
# supply: humanoid retargeting copies bone ROTATIONS, so a hand that grazed a
# slim body's hip follows the same rotation into a wider one and clips
# through it (✅ the owner, on beriul in Idle and Walk: 手太贴身体).
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
# hands against the body (✅ the owner: 先只应用于 idle 和 walk). The angle
# fades in and out over `blend_time`, so leaving a listed clip does not snap
# the arms back.

## The bones to swing. Each one's side is read from its own rest position, so
## a left/right pair takes one angle and moves apart, not together.
@export var bones: Array[String] = ["LeftUpperArm", "RightUpperArm"]
## Degrees away from the body. Positive opens the arms; negative closes them.
@export_range(-30.0, 30.0) var degrees: float = 5.0
## The axis the swing turns about, in skeleton space: the model's forward,
## so a hanging arm moves sideways rather than forward or back.
@export var axis: Vector3 = Vector3(0.0, 0.0, 1.0)
## The clips this correction applies to. Empty means every clip.
@export var clips: Array[String] = []
## Seconds to fade the angle in or out as clips change.
@export var blend_time: float = 0.2

## The angle actually applied right now, chasing 0 or `degrees`.
var _applied: float = 0.0
## The thing that knows which clip is playing: an AnimationTree if the body
## has one (the game), else an AnimationPlayer (the menu and the viewer).
var _driver: Node = null
var _searched: bool = false

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var wanted: float = degrees if _clip_is_listed() else 0.0
	if blend_time > 0.0:
		_applied = move_toward(_applied, wanted, absf(degrees) * delta / blend_time)
	else:
		_applied = wanted
	if is_zero_approx(_applied):
		return
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

## Whether the clip on screen is one this correction is for. An unnamed list
## means all of them; a body whose driver cannot be found is left alone.
func _clip_is_listed() -> bool:
	if clips.is_empty():
		return true
	if not _searched:
		_searched = true
		_driver = _find_driver()
	if _driver is AnimationTree:
		# The state machine's own name is the project's, not Godot's default
		# -- CharacterAnimator.GRAPH_STATES; see its parameters/<name>/playback.
		var playback = (_driver as AnimationTree).get(
			"parameters/%s/playback" % CharacterAnimator.GRAPH_STATES)
		if playback != null:
			return clips.has(String(playback.get_current_node()))
		return false
	if _driver is AnimationPlayer:
		return clips.has(String((_driver as AnimationPlayer).current_animation))
	return false

## Walks up from the skeleton looking for whoever drives it. An AnimationTree
## outranks an AnimationPlayer: where both exist (in the game) the tree is
## the one actually playing, and the player is only its clip library.
func _find_driver() -> Node:
	var walker: Node = get_parent()
	while walker != null:
		for child in walker.get_children():
			if child is AnimationTree:
				return child
		walker = walker.get_parent()
	walker = get_parent()
	while walker != null:
		for child in walker.get_children():
			if child is AnimationPlayer:
				return child
		walker = walker.get_parent()
	return null

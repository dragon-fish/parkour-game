class_name ClipScopedModifier
extends SkeletonModifier3D

# A corrective pose applied only while named clips play, faded in and out so
# leaving one does not snap the bones back. The shared half of BoneSplay and
# BonePoseOffset: WHEN to apply, and how much of it. What to apply is the
# subclass's _apply().

## The clips this correction applies to. Empty means every clip.
@export var clips: Array[String] = []
## Seconds to fade in or out as clips change.
@export var blend_time: float = 0.2

## How much of the correction is on right now, 0 to 1, chasing 1 inside a
## listed clip and 0 outside one.
var _weight: float = 0.0
## The thing that knows which clip is playing: an AnimationTree if the body
## has one (the game), else an AnimationPlayer (the menu and the viewer).
##
## DO NOT cache an AnimationPlayer answer as final. CharacterAnimator builds
## the AnimationTree at RUNTIME, so the first search from a modifier that
## ticks before it exists finds only the imported model's own AnimationPlayer
## -- and that player is the tree's clip LIBRARY, not its driver: in game its
## current_animation is the empty string, so no clip ever matches and the
## correction never comes on. This bug is invisible in the character
## showcase, where no AnimationTree exists at all, so the wrong answer happens
## to be the right one there.
var _driver: Node = null

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var wanted: float = 1.0 if _clip_is_listed() else 0.0
	if blend_time > 0.0:
		_weight = move_toward(_weight, wanted, delta / blend_time)
	else:
		_weight = wanted
	if is_zero_approx(_weight):
		return
	_apply(skeleton, _weight)

## Puts `weight` (0 to 1) of the correction on the skeleton's current pose.
func _apply(_skeleton: Skeleton3D, _weight_now: float) -> void:
	pass

## Whether the clip on screen is one this correction is for. An unnamed list
## means all of them; a body whose driver cannot be found is left alone.
func _clip_is_listed() -> bool:
	if clips.is_empty():
		return true
	# Re-searched while the answer is still provisional -- see _driver. A tree
	# once found is final and never looked for again; an AnimationPlayer keeps
	# being re-checked in case a tree turns up later, which is a walk of a few
	# ancestors and only happens where no tree will ever exist.
	if not (_driver is AnimationTree) or not is_instance_valid(_driver):
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

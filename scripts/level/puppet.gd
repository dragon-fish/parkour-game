class_name Puppet
extends Node3D

# One of the original's animated characters, stood in the level: its own mesh
# on its own skeleton, under this node, with the AnimSequences a cutscene plays
# on it (tools/me_level, from skeletal_glb.py). It does nothing by itself. A
# Matinee that animates it says where its sequence is every tick, and this
# puts the body in the pose that moment has.
#
# POSED, NOT PLAYED. The sequence owns the clock -- it is paused with the
# game, runs at the rate Kismet sets, can be sought and reversed -- and an
# AnimationPlayer left to run beside it would agree with it only by luck.

## This is the body a first-person cutscene is SEEN FROM: the original plays
## it on the player's own pawn, whose view rides a bone of it. While a sequence
## poses this puppet the view is that bone's and the player's input is
## silenced; when the sequence lets go (rest()), both go back.
@export var first_person: bool = false

## What it stands in when no sequence is posing it: the first frame of the
## first animation anything plays on it. The original shows and hides these
## actors from Kismet, and one shown a moment before its sequence starts --
## the Escape's Kate, waiting in the office -- stood in its bind pose, arms out.
@export var rest_animation: StringName = &""

## The bone the view rides. [ME:CONFIRMED] Faith's first-person skeleton
## (CH_TKY_Crim_Fixer_1P) ends Head -> EyeJoint -> CameraJoint.
const CAMERA_BONE := &"CameraJoint"
## The camera in that bone's frame. The bone looks along its own +Y with -Z
## up: found by rendering the Escape's office scene both ways round -- this
## way Faith's own hand reaches into the bottom of the frame as she crawls
## out of the vent, and Kate sits in the chair ahead of her.
const CAMERA_IN_BONE := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, -1.0, 0.0))

## The body's AnimationPlayer, found once.
var _player: AnimationPlayer = null
var _camera: Camera3D = null
## Whose view was taken, while it is: null says nothing is held.
var _viewer: Node = null
## The one puppet the view is with, of all of them. Two first-person scenes
## can overlap -- a chapter's opening still running when the next is begun --
## and the one that ends first handed back a view the other was still using.
static var _holding: Node = null


func _ready() -> void:
	var found := find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		_player = found[0] as AnimationPlayer
		_player.speed_scale = 0.0
		if rest_animation != &"" and _player.has_animation(rest_animation):
			_player.play(rest_animation)
			_player.seek(0.0, true)


## `plays`: [{animation, start, offset, rate, loops}] sorted by start, as the
## original's InterpTrackAnimControl has them; `time` is the sequence's own.
## What plays at `time` is the last entry begun by then -- before the first one
## begins, the first, held at its start.
func pose(plays: Array, time: float) -> void:
	if _player == null or plays.is_empty():
		return
	var play: Dictionary = plays[0]
	for candidate: Dictionary in plays:
		if float(candidate["start"]) <= time:
			play = candidate
	var animation := StringName(str(play["animation"]))
	if not _player.has_animation(animation):
		return
	var seconds: float = _player.get_animation(animation).length
	var into: float = maxf(time - float(play["start"]), 0.0) * float(play["rate"]) + float(play["offset"])
	into = fposmod(into, seconds) if bool(play["loops"]) and seconds > 0.0 else clampf(into, 0.0, seconds)
	if _player.current_animation != animation:
		_player.play(animation)
	_player.seek(into, true)
	if first_person and _viewer == null:
		_take_the_view()


## The sequence has let go: stopped, finished, or been reset.
func rest() -> void:
	if _viewer == null:
		return
	var viewer := _viewer
	_viewer = null
	# The view is hidden with the rest of this body once it is not looked from.
	visible = _shown_before
	if _holding != self:
		return
	_holding = null
	if _camera != null:
		_camera.current = false
	if is_instance_valid(viewer):
		if viewer is Node3D:
			(viewer as Node3D).visible = _viewer_shown_before
		if viewer.get("camera_rig") != null and viewer.camera_rig.camera != null:
			(viewer.camera_rig.camera as Camera3D).make_current()
		if viewer.has_method("unlock_input"):
			viewer.unlock_input()


## Whether any puppet is lending its view: a first-person cutscene is playing.
## The level's opening curtain asks -- with the view on a scene's own body,
## waiting for the PLAYER's body to land is waiting for nothing, and the
## chapter's opening is seconds long with all of it behind the curtain.
static func showing_a_scene() -> bool:
	return _holding != null and is_instance_valid(_holding)


## Where the view this puppet lent ended up, as somewhere to stand, or null
## while it lent none. The camera bone carries the scene's whole displacement:
## the puppet node itself never moves, the walking is in the animation.
func view_transform() -> Variant:
	if _camera == null or not is_instance_valid(_camera):
		return null
	# FROM THE POSE, NOT FROM THE ATTACHMENT. A BoneAttachment3D catches up
	# with its skeleton on the skeleton's own update, which a seek made in the
	# same frame has not reached yet -- and a SKIP is exactly that seek, the
	# whole scene at once. Read off the node, skipping the Edge's opening put
	# the body 130 m back, where the view had got to the frame before.
	var mount := _camera.get_parent() as BoneAttachment3D
	var skeleton := mount.get_parent() as Skeleton3D if mount != null else null
	if skeleton == null:
		return _camera.global_transform
	var bone := skeleton.find_bone(mount.bone_name)
	if bone < 0:
		return _camera.global_transform
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) 			* Transform3D(CAMERA_IN_BONE, Vector3.ZERO)


func _exit_tree() -> void:
	# A section unloaded mid-scene must not keep the player's input.
	rest()


func _notification(what: int) -> void:
	# Nor one whose package was streamed out: PackagePresence disables what is
	# absent, and a disabled sequence never reaches its end to let go.
	if what == NOTIFICATION_DISABLED:
		rest()


var _shown_before: bool = true
var _viewer_shown_before: bool = true


func _take_the_view() -> void:
	var viewer := _find_viewer()
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if viewer == null or skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone(CAMERA_BONE) < 0:
		return
	if _camera == null:
		var mount := BoneAttachment3D.new()
		mount.bone_name = CAMERA_BONE
		skeleton.add_child(mount)
		_camera = Camera3D.new()
		_camera.transform = Transform3D(CAMERA_IN_BONE, Vector3.ZERO)
		_camera.near = 0.05
		mount.add_child(_camera)
	var own: Camera3D = viewer.camera_rig.camera if viewer.get("camera_rig") != null else null
	if own != null:
		_camera.fov = own.fov
		_camera.cull_mask = own.cull_mask
	if _holding != null and _holding != self and is_instance_valid(_holding):
		_holding.call("rest")
	_holding = self
	_viewer = viewer
	# The player's own body stands wherever the level last put it -- often in
	# shot -- and this camera sees what theirs sees.
	if viewer is Node3D:
		_viewer_shown_before = (viewer as Node3D).visible
		(viewer as Node3D).visible = false
	_shown_before = visible
	visible = true
	_camera.make_current()
	if viewer.has_method("lock_input"):
		viewer.lock_input()


func _find_viewer() -> Node:
	# The level's root, by what it has: see Matinee._apply() on class names.
	var node := get_parent()
	while node != null and node.get("player") == null:
		node = node.get_parent()
	return node.get("player") if node != null else null

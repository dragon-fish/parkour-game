class_name SilhouetteBody
extends Node3D

# A body with NOTHING driving it but its own AnimationPlayer.
#
# ONE WRITER PER SKELETON, and that is the whole reason this class exists. A
# Player's body carries an AnimationTree fed by the move machine, a HeadLook
# modifier that turns the neck toward the camera every frame, clip-offset
# drivers and spring bones -- every one of them a writer on the same bones.
# Posing THAT for a title shot means silencing each writer and waking each one
# again, and missing one produces its own deformity: a neck twisted toward a
# side-on lens, or a body held in the crouch clip through every move the
# player makes afterwards. Both of those have been on screen.
#
# So a title shot does not pose the player. It films a stand-in that carries
# none of it, and hands over on a frame where the stand-in and the real body
# are the same red silhouette standing in the same spot. DO NOT give this
# class an AnimationTree, a skeleton modifier or a Player: the moment a second
# writer exists the deformity is back.
#
# ITS ORIGIN IS THE FIGURE'S FEET. The mount offset and rotation the profile
# carries are applied to the model INSIDE this node, so a host places this node
# where the ground under the figure is and nothing else.
#
# NO MODEL, NO PROBLEM: build() returns null on a machine with no body profile
# linked, and every caller treats that as "there is no figure in this shot"
# rather than as an error.

## Where the body binding lives on THIS machine. The same three-stage lookup
## Arena uses (see arena.gd's own pair): the local config wins, the constant is
## the fallback, and absent means no body at all. Untracked by design -- a
## release must not ship whichever model a machine happened to be testing.
const BODY_PROFILE := "res://scenes/player/local/profiles/beriul.tres"
const LOCAL_PROFILE_CONFIG := "res://scenes/player/local/profiles/local.cfg"

## The clips a title shot asks for by name, in the tiers the free asset set
## actually ships. Crouch_Exit is a real stand-up -- weight shifts, a hand
## leaves the floor -- and ships only in the paid tier; the Idle blend is what
## a checkout without it gets, and it reads as the body inflating rather than
## pushing off.
const CROUCH_CLIP := &"Crouch_Idle"
const STAND_UP_CLIP := &"Crouch_Exit"
const STANDING_CLIP := &"Idle"
const WALK_CLIP := &"Walk"

## The instanced model, carrying the profile's mount transform.
var body: Node3D
## The one thing allowed to write this skeleton.
var anim_player: AnimationPlayer

## Builds a painted, animatable stand-in, or null when this machine has no body
## to build it from.
static func build() -> SilhouetteBody:
	var profile := resolve_profile()
	if profile == null or profile.scene == null:
		return null
	# The real pipeline never mounts a profile's raw fields -- BodyProfile.apply()
	# runs them through BodyTuning first (scenes/player/tuning/*.json, keyed by
	# the model's own filename). Only these two calls are reused rather than
	# apply() itself: that method also writes a dozen Player-only fields, and
	# there is no Player anywhere near this.
	BodyTuning.apply_to(profile, BodyTuning.load_for(profile.scene.resource_path))
	var instance := profile.scene.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return null
	var figure := SilhouetteBody.new()
	figure.name = "Silhouette"
	figure.body = instance as Node3D
	figure.add_child(figure.body)
	figure.body.transform = Transform3D(
		Basis.from_euler(profile.mount_rotation_degrees * (PI / 180.0)) \
			.scaled(Vector3.ONE * maxf(profile.mount_scale, 0.001)),
		profile.mount_offset)
	figure._merge_animation_library(profile.animation_libraries)
	figure.paint(figure.body)
	figure.anim_player = find_animation_player(figure.body)
	figure._ensure_clip_loops(STANDING_CLIP)
	figure._ensure_clip_loops(WALK_CLIP)
	return figure

static func resolve_profile() -> BodyProfile:
	var path: String = BODY_PROFILE
	var local := ConfigFile.new()
	if local.load(LOCAL_PROFILE_CONFIG) == OK:
		path = str(local.get_value("body", "profile", BODY_PROFILE))
	if not ResourceLoader.exists(path):
		return null
	return load(path) as BodyProfile

## Every MeshInstance3D under `node` gets an unshaded brand-red override,
## turning whatever model is attached into the flat figure the front door
## holds, regardless of the model's own materials.
##
## THE COLOUR IS NOT A DIAL. Being the SAME red as every other screen is the
## whole point; a shot free to pick its own is free to disagree with the one
## the player was looking at a second ago.
static func paint(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = MeTheme.BRAND_RED
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		paint(child)

static func find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child in node.get_children():
			queue.append(child)
	return null

## The held pose a title shot opens on.
func hold_crouch() -> void:
	if anim_player == null:
		return
	if anim_player.has_animation(CROUCH_CLIP):
		anim_player.play(CROUCH_CLIP)
	elif anim_player.has_animation(STANDING_CLIP):
		anim_player.play(STANDING_CLIP)

## When to START standing so the body finishes WITH the camera that is moving
## over the same window. A real Crouch_Exit is shorter than the window, so it
## begins late -- stretching it to fill the window instead plays a 0.83 s
## motion at 0.55x and reads as wading through treacle.
func stand_up_delay(window: float) -> float:
	if anim_player != null and anim_player.has_animation(STAND_UP_CLIP):
		return maxf(window - anim_player.get_animation(STAND_UP_CLIP).length, 0.0)
	return 0.0

func start_stand_up(blend: float) -> void:
	if anim_player == null:
		return
	if anim_player.has_animation(STAND_UP_CLIP):
		anim_player.play(STAND_UP_CLIP)
		# Its last frame IS the standing pose, so Idle follows with no blend.
		anim_player.queue(STANDING_CLIP)
		return
	if anim_player.has_animation(STANDING_CLIP):
		anim_player.play(STANDING_CLIP, blend)

## Same shape as Player._merge_animation_library, and it cannot share that one:
## this runs against a bare instanced body with no Player around it at all.
## Existing clips win; a library only fills gaps.
func _merge_animation_library(libraries: Array[PackedScene]) -> void:
	if libraries.is_empty():
		return
	var target := find_animation_player(body)
	if target == null:
		return
	# has_ probed first: get_animation_library() on a missing name logs an
	# engine error, and a fresh AnimationPlayer (an FBX body's wrapper scene,
	# unlike a VRM's) starts with no "" library at all.
	var library: AnimationLibrary
	if target.has_animation_library(""):
		library = target.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		target.add_animation_library("", library)
	for packed in libraries:
		if packed == null:
			continue
		var source_scene := packed.instantiate()
		if source_scene == null:
			continue
		var source := find_animation_player(source_scene)
		if source == null:
			source_scene.free()
			continue
		for clip_name in source.get_animation_list():
			if library.has_animation(clip_name):
				continue
			library.add_animation(clip_name, source.get_animation(clip_name).duplicate())
		source_scene.free()

## Same fix as Player._ensure_clip_loops: glTF/VRM imports carry no "this clip
## loops" flag, so a merged Walk/Idle clip comes in as LOOP_NONE and freezes on
## its last frame instead of cycling.
func _ensure_clip_loops(clip_name: StringName) -> void:
	if anim_player == null:
		return
	var original_library := anim_player.get_animation_library("")
	if original_library == null or not original_library.has_animation(clip_name):
		return
	var library := original_library.duplicate(true) as AnimationLibrary
	library.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	anim_player.remove_animation_library("")
	anim_player.add_animation_library("", library)

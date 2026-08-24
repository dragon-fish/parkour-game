class_name BodyProfile
extends Resource

# Everything about ONE attachable body, in one file.
#
# The values here are per-MODEL, not per-level: how tall it is against this
# project's capsule, which way it faces, where its head bone lives, which
# animation packs it borrows from. Kept on the Player as individual exports,
# they had to be repeated on every level's Player instance -- and the owner had
# already been caught by that once, unable to remember where a mount offset had
# been set after finding it right in one level and wrong in another.
#
# A level now points at one of these instead. Changing how a body sits is one
# edit, in the place that describes the body.
#
# Player still carries the same properties and still reads them; apply() just
# fills them in first. Nothing downstream knows this exists, which is what
# keeps a body configured entirely by hand working exactly as before.

## The model. Everything else here describes how THIS scene is mounted, so a
## profile with no scene set is not useful for anything.
@export var scene: PackedScene

@export_group("Mounting")
## Per-model placement against the capsule -- see Player.body_mount_offset,
## body_mount_rotation_degrees and body_mount_scale, which these become.
@export var mount_offset: Vector3 = Vector3.ZERO
## ⚠️ Every VRM wants Vector3(0, 180, 0): the format has models face +Z and
## Godot's forward is -Z.
@export var mount_rotation_degrees: Vector3 = Vector3.ZERO
@export var mount_scale: float = 1.0
## Path to the node the head-follow camera tracks, relative to the model's root.
## ⚠️ A VRM needs this set explicitly -- the name search finds a mesh called
## Head sitting at the model's origin, down at the feet.
@export var head_path: NodePath

@export_group("Animation")
## Packs whose clips are merged into the body's own, first name winning.
@export var animation_libraries: Array[PackedScene] = []
## The travel speed at which this body's locomotion clips read as natural.
## Per-CLIP correction to where the body sits, as
## {clip_name: [position: Vector3, rotation_degrees: Vector3]}.
##
## The mount above places the body against the capsule for a STANDING pose, and
## that is the only pose it can be right for. A pack's clips are authored around
## their own idea of where the ground, the wall or the ledge is, and the
## mismatch shows: the owner's report on SafetyVault was "the hands are
## completely in mid-air".
##
## ⚠️ A constant offset can only align ONE instant of a moving clip. It is the
## whole answer for a pose that holds still -- a ledge hang, a wall run, a
## crouch -- and a compromise for a vault, where the body travels past the thing
## its hands are supposed to be on. The real answer there is IK onto the edge
## the probe already returns.
##
## Applied in BodyRoot's space, so it is NOT multiplied by mount_scale: nudging
## by 0.1 moves the body 0.1 m whatever size the model is. Rotation pivots on
## the model's own origin, which the mount has already put at its feet.
##
## Tuned in play rather than by hand -- see scripts/debug/clip_offset_tuner.gd,
## which freezes the game on the frame you are looking at and prints a line to
## paste back here.
@export var clip_offsets: Dictionary = {}

## Which PART of a clip to play, as {clip_name: [start_seconds, length_seconds]}.
## A length of 0 means "to the end of the clip".
##
## ✅ The owner: "the vault and grab animations play far too late -- the
## character has nearly landed before the frame where the hand plants." The
## packs author whole actions, run-up included, and this project starts them at
## the moment of contact -- so the approach plays while the body is already
## going over, and the plant arrives after the move has ended.
##
## `start` skips the run-up. `length` is what the kept part is STRETCHED to
## last, which is how a 1.5 s clip fits a 0.65 s vault without a time scale
## anyone has to keep in step by hand.
##
## ⚠️ Applied when the graph is BUILT, so a change needs the body re-attached.
@export var clip_timings: Dictionary = {}

@export var run_reference_speed: float = 7.2
@export var blend_time: float = 0.15

## See Player.body_gate_hold_time.
@export var gate_hold_time: float = 0.05
@export var slide_exit_blend_time: float = 0.5
@export var slide_to_crouch_blend_time: float = 0.3

@export_group("Camera")
## Raises the eye during a slide, for bodies whose chest reaches it.
@export var slide_eye_lift: float = 0.0

## Copies this profile onto `player`. Called by Player before it attaches
## anything; see Player.body_profile.
func apply(player: Player) -> void:
	# ⚠️ TRACKED TUNING WINS OVER THIS RESOURCE'S OWN. ✅ THE OWNER: "总不能我换台
	# 电脑东西就丢了."
	#
	# 📌 This resource cannot be tracked -- it names a model and two animation
	# packs that are not, and .gitignore says so. But it was carrying two
	# unrelated things: the BINDING, which is machine-local, and the TUNING,
	# which is knowledge about a shape of model and true anywhere. Only the
	# first was ever the problem. See BodyTuning.
	BodyTuning.apply_to(self,
		BodyTuning.load_for(scene.resource_path if scene != null else ""))
	player.body_scene = scene
	player.body_mount_offset = mount_offset
	player.body_mount_rotation_degrees = mount_rotation_degrees
	player.body_mount_scale = mount_scale
	player.body_head_path = head_path
	player.body_animation_libraries = animation_libraries
	player.body_clip_offsets = clip_offsets
	player.body_clip_timings = clip_timings
	player.body_run_reference_speed = run_reference_speed
	player.body_animation_blend_time = blend_time
	player.body_gate_hold_time = gate_hold_time
	player.body_slide_exit_blend_time = slide_exit_blend_time
	player.body_slide_to_crouch_blend_time = slide_to_crouch_blend_time
	player.body_slide_eye_lift = slide_eye_lift

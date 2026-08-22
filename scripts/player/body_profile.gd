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
@export var run_reference_speed: float = 7.2
@export var blend_time: float = 0.15
@export var slide_exit_blend_time: float = 0.5
@export var slide_to_crouch_blend_time: float = 0.3

@export_group("Camera")
## Raises the eye during a slide, for bodies whose chest reaches it.
@export var slide_eye_lift: float = 0.0

## Copies this profile onto `player`. Called by Player before it attaches
## anything; see Player.body_profile.
func apply(player: Player) -> void:
	player.body_scene = scene
	player.body_mount_offset = mount_offset
	player.body_mount_rotation_degrees = mount_rotation_degrees
	player.body_mount_scale = mount_scale
	player.body_head_path = head_path
	player.body_animation_libraries = animation_libraries
	player.body_run_reference_speed = run_reference_speed
	player.body_animation_blend_time = blend_time
	player.body_slide_exit_blend_time = slide_exit_blend_time
	player.body_slide_to_crouch_blend_time = slide_to_crouch_blend_time
	player.body_slide_eye_lift = slide_eye_lift

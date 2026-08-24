class_name BodyTuning
extends RefCounted

# How a body is mounted and corrected, kept in git rather than in the model's
# own resource.
#
# THE OWNER, after six hours of tuning that lived only on one machine: "总不能我换
# 台电脑东西就丢了." And the shape of the answer, theirs: "能不能采用约定式配置文件，就
# 是我们默认所有开发者都会使用与我们相同眼高的模型、相同的UAL动画库，然后将我们配好的东西
# 保存为default...如果其他人想覆写这份，就复制一份然后命名为与模型名字一样的json文件."
#
# WHY THE PROFILE COULD NOT JUST BE TRACKED. BodyProfile names the model and the
# animation packs by path, and those are untracked -- see .gitignore, which says
# so in as many words: "Body profiles that name untracked models, so they cannot
# be tracked either." But that resource was carrying two unrelated things at
# once:
#
#   BINDING   which .vrm, which .glb          -- machine-local, unshareable
#   TUNING    where the model sits on the      -- knowledge about a SHAPE of
#             capsule, which clips are off        model, true on any machine
#             and by how much
#
# Only the first was ever the problem. Splitting them puts ten numbers that cost
# an evening each into version control, and leaves behind a .tres holding two
# file references that take thirty seconds to recreate.
#
# THE CONVENTION, and what it assumes: a model of roughly the same eye height,
# retargeted to the same humanoid profile, driven by the same UAL packs. Under
# those assumptions default.json is right for everybody. A model that breaks
# them gets its own file named after it, and overrides only what it needs.

## Where the files live. Tracked, unlike the profiles beside them.
const DIRECTORY := "res://scenes/player/tuning/"
const DEFAULT_NAME := "default"

## Reads the tuning for `model_path`, falling back to the default.
##
## The name is the model's own filename without its extension, so
## `res://assets/models/test.vrm` looks for `test.json` -- no registry to keep in
## step, and adding an override is copying a file and renaming it.
##
## Returns an empty dictionary when there is nothing to read, which every caller
## treats as "leave the profile's own values alone". A project with no tuning
## directory at all behaves exactly as it did before this existed.
static func load_for(model_path: String) -> Dictionary:
	var named := ""
	if model_path != "":
		named = model_path.get_file().get_basename()
	for candidate in [named, DEFAULT_NAME]:
		if candidate == "":
			continue
		var found: Dictionary = _read(DIRECTORY + candidate + ".json")
		if not found.is_empty():
			return found
	return {}

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("body tuning at %s is not a JSON object" % path)
		return {}
	return parsed

## Puts `tuning` onto `profile`, leaving anything it does not mention alone.
##
## ⚠️ EVERY KEY IS OPTIONAL, and that is what makes an override worth writing. A
## model that only needs a different mount scale writes one line; it does not
## have to restate the clip offsets to keep them.
static func apply_to(profile: BodyProfile, tuning: Dictionary) -> void:
	if profile == null or tuning.is_empty():
		return
	if tuning.has("mount_offset"):
		profile.mount_offset = _vector(tuning["mount_offset"], profile.mount_offset)
	if tuning.has("mount_rotation_degrees"):
		profile.mount_rotation_degrees = _vector(tuning["mount_rotation_degrees"],
			profile.mount_rotation_degrees)
	if tuning.has("mount_scale"):
		profile.mount_scale = float(tuning["mount_scale"])
	if tuning.has("head_path"):
		profile.head_path = NodePath(String(tuning["head_path"]))
	if tuning.has("clip_offsets"):
		profile.clip_offsets = _offsets(tuning["clip_offsets"])
	if tuning.has("clip_timings"):
		profile.clip_timings = _timings(tuning["clip_timings"])
	for key in ["run_reference_speed", "blend_time", "gate_hold_time",
			"slide_exit_blend_time", "slide_to_crouch_blend_time",
			"slide_eye_lift"]:
		if tuning.has(key):
			profile.set(key, float(tuning[key]))

## `[x, y, z]`, or the fallback when it is anything else.
static func _vector(from, fallback: Vector3) -> Vector3:
	if from is Array and (from as Array).size() >= 3:
		return Vector3(float(from[0]), float(from[1]), float(from[2]))
	return fallback

## `{"ClipName": [[x, y, z], [pitch, yaw, roll]]}` -- position then rotation in
## degrees, the same pair BodyProfile.clip_offsets already holds.
static func _offsets(from) -> Dictionary:
	var out := {}
	if not (from is Dictionary):
		return out
	for clip in from:
		var pair = from[clip]
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		out[StringName(clip)] = [
			_vector(pair[0], Vector3.ZERO), _vector(pair[1], Vector3.ZERO)]
	return out

## `{"ClipName": [start_seconds, length_seconds]}`, a length of 0 meaning "to the
## end of the clip" -- see Player.apply_clip_timing().
static func _timings(from) -> Dictionary:
	var out := {}
	if not (from is Dictionary):
		return out
	for clip in from:
		var pair = from[clip]
		if not (pair is Array) or (pair as Array).size() < 2:
			continue
		out[StringName(clip)] = [float(pair[0]), float(pair[1])]
	return out

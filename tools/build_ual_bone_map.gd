extends SceneTree

# Generates the BoneMap that lets Godot's importer retarget the Quaternius
# Universal Animation Library onto this project's humanoid rig.
#
# WHY A SCRIPT rather than a hand-written .tres: BoneMap stores its entries
# under generated property names against a profile that has to exist first.
# Guessing that format and finding out at import time costs more than the
# thirty lines here, and this file also doubles as the readable record of what
# maps to what.
#
# The pack ships an Unreal-mannequin skeleton (pelvis / spine_01 / clavicle_l /
# thigh_l ...). The project's own VRM body is already named exactly like
# SkeletonProfileHumanoid (Hips / Spine / LeftShoulder / LeftUpperLeg ...), so
# only one side needs mapping at all.
#
#   godot --headless --script res://tools/build_ual_bone_map.gd

const OUTPUT := "res://assets/animations/ual2_bone_map.tres"

## profile bone name -> the pack's own bone name.
const MAPPING := {
	"Root": "root",
	"Hips": "pelvis",
	"Spine": "spine_01",
	"Chest": "spine_02",
	"UpperChest": "spine_03",
	"Neck": "neck_01",
	"Head": "Head",
}

## Suffixed pairs, expanded for both sides below: profile stem -> pack stem.
const SIDED := {
	"Shoulder": "clavicle",
	"UpperArm": "upperarm",
	"LowerArm": "lowerarm",
	"Hand": "hand",
	"UpperLeg": "thigh",
	"LowerLeg": "calf",
	"Foot": "foot",
	"Toes": "ball",
}

## Fingers are three joints on each side, and the two skeletons disagree on
## BOTH the joint names and the digit names -- the profile says
## Proximal/Intermediate/Distal where the pack says 01/02/03, and the profile
## says Little where the pack says pinky.
##
## The thumb is the exception and is handled separately: the profile's thumb
## starts at Metacarpal, one joint further out than the other digits.
const DIGITS := {
	"Index": "index",
	"Middle": "middle",
	"Ring": "ring",
	"Little": "pinky",
}
const JOINTS := ["Proximal", "Intermediate", "Distal"]
const THUMB_JOINTS := ["Metacarpal", "Proximal", "Distal"]

func _init() -> void:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()

	var pairs := {}
	for profile_bone in MAPPING:
		pairs[profile_bone] = MAPPING[profile_bone]
	for side in ["Left", "Right"]:
		var suffix: String = "_l" if side == "Left" else "_r"
		for stem in SIDED:
			pairs[side + stem] = SIDED[stem] + suffix
		for digit in DIGITS:
			for i in JOINTS.size():
				pairs["%s%s%s" % [side, digit, JOINTS[i]]] = \
					"%s_0%d%s" % [DIGITS[digit], i + 1, suffix]
		for i in THUMB_JOINTS.size():
			pairs["%sThumb%s" % [side, THUMB_JOINTS[i]]] = "thumb_0%d%s" % [i + 1, suffix]

	var set_count := 0
	var unknown: Array[String] = []
	for profile_bone in pairs:
		# set_skeleton_bone_name() silently does nothing for a name the profile does
		# not have, so anything invented here would vanish without a word.
		if map.profile.find_bone(profile_bone) < 0:
			unknown.append(profile_bone)
			continue
		map.set_skeleton_bone_name(profile_bone, StringName(pairs[profile_bone]))
		set_count += 1

	if not unknown.is_empty():
		push_warning("not in SkeletonProfileHumanoid, skipped: %s" % ", ".join(unknown))
	var err := ResourceSaver.save(map, OUTPUT)
	print("mapped %d of %d bones -> %s (err %d)" % \
		[set_count, pairs.size(), OUTPUT, err])
	quit(0 if err == OK else 1)

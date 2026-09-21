extends SceneTree

# Generates the BoneMap that lets Godot's importer retarget the original
# Mirror's Edge character rigs onto SkeletonProfileHumanoid.
#
# WHY IT MATTERS: the importer does not only RENAME bones with this, it also
# normalises the rest pose to the profile's. The original's rigs rest in an
# A-pose and everything this project retargets onto rests in the profile's
# T-pose; without that normalisation a retarget reads every animation against
# the wrong baseline and the arms come out lifted. Hand-writing the fix was
# tried three ways and each produced a different wrong body -- the importer's
# own rest fixer is the answer, and this file is its input.
#
#   <engine> --headless --script res://tools/build_me_bone_map.gd
#
# The original ships a 3ds Max Biped rig (Hips / Spine / Spine1 / LeftUpLeg /
# LeftArm / LeftForeArm / LeftHandMiddle1 ...), so only one side needs naming.

const OUTPUT := "res://assets/animations/me_bone_map.tres"

## profile bone name -> the original's own bone name.
const MAPPING := {
	"Hips": "Hips",
	"Spine": "Spine",
	# SpineX, not Spine1, and NOTHING mapped to UpperChest.
	#
	# Chest means "what the neck and the shoulders hang off", and in the
	# original that is SpineX. Mapping Spine1 there instead drops the whole
	# Spine1 -> SpineX turn and everything above the chest comes out 22.7
	# degrees short (measured); mapping SpineX brings that down to under 4.
	#
	# DO NOT then hang UpperChest off SpineX as a third joint, however much the
	# bone ORDER in the file suggests a Spine -> Spine1 -> SpineX chain.
	# Measured, SpineX sits about as high as the head -- it is a helper, not a
	# vertebra -- and driving a real UpperChest from it folds the body up: the
	# neck lands BELOW the upper chest and the head ends up at hip height.
	# What is lost by leaving it unmapped is one joint's share of the turn.
	"Chest": "SpineX",
	"Neck": "Neck",
	"Head": "Head",
}

## Suffixed pairs, expanded for both sides below: profile stem -> its stem.
## The original prefixes the side, where the profile does too but spells the
## limbs differently: Arm is the UPPER arm, ForeArm the lower, UpLeg the thigh.
const SIDED := {
	"Shoulder": "Shoulder",
	"UpperArm": "Arm",
	"LowerArm": "ForeArm",
	"Hand": "Hand",
	"UpperLeg": "UpLeg",
	"LowerLeg": "Leg",
	"Foot": "Foot",
	"Toes": "ToeBase",
}

## The original numbers a digit's joints from 1 and has a 0 joint besides --
## the metacarpal, which the profile carries for the thumb alone.
const DIGITS := {
	"Index": "Index",
	"Middle": "Middle",
	"Ring": "Ring",
	"Little": "Pinky",
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
		for stem in SIDED:
			pairs[side + stem] = side + SIDED[stem]
		for digit in DIGITS:
			for i in JOINTS.size():
				pairs["%s%s%s" % [side, digit, JOINTS[i]]] = \
					"%sHand%s%d" % [side, DIGITS[digit], i + 1]
		for i in THUMB_JOINTS.size():
			pairs["%sThumb%s" % [side, THUMB_JOINTS[i]]] = "%sHandThumb%d" % [side, i + 1]

	var set_count := 0
	var unknown: Array[String] = []
	for profile_bone in pairs:
		if map.profile.find_bone(profile_bone) < 0:
			unknown.append(profile_bone)
			continue
		map.set_skeleton_bone_name(profile_bone, StringName(pairs[profile_bone]))
		set_count += 1

	if not unknown.is_empty():
		push_warning("not in SkeletonProfileHumanoid, skipped: %s" % ", ".join(unknown))
	var err := ResourceSaver.save(map, OUTPUT)
	print("mapped %d of %d bones -> %s (err %d)" % [set_count, pairs.size(), OUTPUT, err])
	quit(0 if err == OK else 1)

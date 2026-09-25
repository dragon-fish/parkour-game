extends ParkourTest

# BonePoseOffset turns named bones on top of the pose, only while its clips
# play. Built on a two-bone skeleton of its own so it needs no private body.

var _tip: Vector3 = Vector3.ZERO

## A root bone with a child 1 m up it, a player that knows two clips, and the
## offset under test turning the root 90 degrees about X while `clip` plays.
func _rig(listed: String) -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	root.add_child(skeleton)
	skeleton.add_bone("Root")
	skeleton.add_bone("Tip")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 1, 0)))
	skeleton.reset_bone_poses()
	var player := AnimationPlayer.new()
	root.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation("Listed", Animation.new())
	library.add_animation("Other", Animation.new())
	player.add_animation_library("", library)
	var offset := BonePoseOffset.new()
	offset.clips = [listed]
	offset.blend_time = 0.0
	var turns: Dictionary[String, Vector3] = {"Root": Vector3(90, 0, 0)}
	offset.rotations = turns
	skeleton.add_child(offset)
	skeleton.skeleton_updated.connect(func() -> void:
		_tip = skeleton.get_bone_global_pose(1).origin)
	return [player]

func test_a_listed_clip_turns_the_bone_and_carries_its_child() -> void:
	var rig: Array = _rig("Listed")
	(rig[0] as AnimationPlayer).play("Listed")
	await step(3)
	# Turned 90 degrees about X, the tip 1 m up the root swings onto Z.
	assert_almost_eq(_tip.y, 0.0, 0.01, "the root was not turned, or the tip did not follow it")
	assert_almost_eq(absf(_tip.z), 1.0, 0.01, "the tip did not swing round with its parent")

func test_another_clip_leaves_the_pose_alone() -> void:
	var rig: Array = _rig("Listed")
	(rig[0] as AnimationPlayer).play("Other")
	await step(3)
	assert_almost_eq(_tip.y, 1.0, 0.01, "an unlisted clip was turned")

extends ParkourTest

# The wrapper splices back the UpperChest bone VRM let the model leave out.
#
# STRUCTURE ONLY. That the bone exists, hangs where it should, and moves
# nothing by existing -- never how the animation ends up looking, which is for
# eyes. Tolerant of a clone without the private asset, which is most of them.

const WRAPPER := "res://assets/models/local/beriul/beriul_body.tscn"

func _skeleton_of(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _skeleton_of(c)
		if r != null:
			return r
	return null

func test_the_wrapper_splices_upper_chest_between_chest_and_neck() -> void:
	if not ResourceLoader.exists(WRAPPER):
		pass_test("no local body wrapper to check")
		return
	var body: Node3D = (load(WRAPPER) as PackedScene).instantiate()
	add_child_autofree(body)
	await step(2)
	var skeleton := _skeleton_of(body)
	assert_not_null(skeleton, "the wrapper has no skeleton")
	var spliced: int = skeleton.find_bone("UpperChest")
	assert_gt(spliced, -1, "UpperChest was not spliced in")
	var chest: int = skeleton.find_bone("Chest")
	var neck: int = skeleton.find_bone("Neck")
	assert_eq(skeleton.get_bone_parent(spliced), chest, "UpperChest must hang off Chest")
	assert_eq(skeleton.get_bone_parent(neck), spliced, "Neck must hang off UpperChest")

func test_the_spliced_bone_moves_nothing_by_existing() -> void:
	# A zero-length identity bone is what lets this be safe on any rig: the
	# child keeps the rest it had. If this drifts, every mount offset tuned
	# against the old chain is silently wrong.
	if not ResourceLoader.exists(WRAPPER):
		pass_test("no local body wrapper to check")
		return
	var body: Node3D = (load(WRAPPER) as PackedScene).instantiate()
	add_child_autofree(body)
	await step(2)
	var skeleton := _skeleton_of(body)
	var spliced: int = skeleton.find_bone("UpperChest")
	var rest: Transform3D = skeleton.get_bone_rest(spliced)
	assert_almost_eq(rest.origin.length(), 0.0, 0.000001, "the splice must be zero-length")
	assert_almost_eq(rest.basis.get_euler().length(), 0.0, 0.000001, "and unrotated")

func test_a_rig_that_already_has_the_bone_is_left_alone() -> void:
	var skeleton := Skeleton3D.new()
	add_child_autofree(skeleton)
	for b in ["Chest", "UpperChest", "Neck"]:
		skeleton.add_bone(b)
	skeleton.set_bone_parent(skeleton.find_bone("UpperChest"), skeleton.find_bone("Chest"))
	skeleton.set_bone_parent(skeleton.find_bone("Neck"), skeleton.find_bone("UpperChest"))
	var before: int = skeleton.get_bone_count()
	var splice := BoneSplice.new()
	skeleton.add_child(splice)
	await step(2)
	assert_eq(skeleton.get_bone_count(), before, "nothing should have been added")

func test_an_unrelated_chain_is_refused() -> void:
	# Neck hanging off something other than Chest is a different rig, not this
	# one with a gap. Splicing anyway would move the head rather than steady it.
	var skeleton := Skeleton3D.new()
	add_child_autofree(skeleton)
	for b in ["Chest", "Spine", "Neck"]:
		skeleton.add_bone(b)
	skeleton.set_bone_parent(skeleton.find_bone("Neck"), skeleton.find_bone("Spine"))
	var before: int = skeleton.get_bone_count()
	var splice := BoneSplice.new()
	skeleton.add_child(splice)
	await step(2)
	assert_eq(skeleton.get_bone_count(), before, "an unrelated chain must be left alone")

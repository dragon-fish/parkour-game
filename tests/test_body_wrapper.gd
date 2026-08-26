extends ParkourTest

# A licence-bound model's wrapper scene is untracked (see .gitignore), so
# this suite verifies whatever wrapper is present on THIS machine and skips
# when there is none -- a clone without the model still runs green.
#
# It exists because the failure it catches is silent and total: the Godot
# editor, re-saving the wrapper after a value was tweaked in the inspector,
# dropped every SpringChains prefix list, and the model lost all secondary
# motion with nothing in the log to say so (✅ the owner: 改完 weight 之后全身
# 都没有骨骼效果了). Structure, not tuning -- the spring values themselves
# stay free to change.

const WRAPPER := "res://assets/models/beriul/beriul_body.tscn"

func test_every_spring_group_finds_chains() -> void:
	if not ResourceLoader.exists(WRAPPER):
		pass_test("no local body wrapper to check")
		return
	var body: Node3D = (load(WRAPPER) as PackedScene).instantiate()
	add_child_autofree(body)
	# SpringChains builds on a deferred call, once its skeleton resolves.
	await step(2)

	var skeleton := body.find_child("GeneralSkeleton", true, false) as Skeleton3D
	assert_not_null(skeleton, "the wrapper has no GeneralSkeleton -- retarget lost?")
	if skeleton == null:
		return
	var groups := 0
	for child in skeleton.get_children():
		if not (child is SpringBoneSimulator3D):
			continue
		groups += 1
		var sim := child as SpringBoneSimulator3D
		assert_gt(sim.setting_count, 0, \
			"%s built no chains -- its prefix list is empty or matches nothing" % sim.name)
	assert_gt(groups, 0, "the wrapper carries no spring groups at all")

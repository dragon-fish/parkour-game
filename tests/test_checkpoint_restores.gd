extends ParkourTest

# A respawn point can stand on something that is only there part of the time:
# a girder halfway up its rise, a train already rolling. The blanket reset
# every respawn does puts that thing back to its start, which is exactly what
# must NOT happen for the one point being respawned into.
#
# The original stages these by SWAPPING ACTORS -- hide the ordinary one,
# un-hide a twin that was standing there all along, play the twin's own
# animation -- so that is the shape tested here. Structural only: what is
# drawn, what is solid, what is playing.

func _rig() -> Dictionary:
	var root := Node3D.new()
	var ordinary := StaticBody3D.new()
	ordinary.name = "Ordinary"
	var ordinary_shape := CollisionShape3D.new()
	ordinary_shape.shape = BoxShape3D.new()
	ordinary.add_child(ordinary_shape)
	root.add_child(ordinary)

	var twin := StaticBody3D.new()
	twin.name = "Twin"
	twin.visible = false
	var twin_shape := CollisionShape3D.new()
	twin_shape.shape = BoxShape3D.new()
	twin_shape.disabled = true
	twin.add_child(twin_shape)
	root.add_child(twin)

	var sequence := Matinee.new()
	sequence.name = "TwinRise"
	sequence.length = 0.1
	sequence.tracks = [{
		targets = [NodePath("../Twin")],
		local = false,
		pos_times = PackedFloat32Array([0.0, 0.1]),
		pos_values = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 3.0, 0.0)]),
		pos_arrive = PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		pos_leave = PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		pos_modes = PackedByteArray([1, 1]),
		rot_times = PackedFloat32Array(), rot_values = PackedVector3Array(),
		rot_arrive = PackedVector3Array(), rot_leave = PackedVector3Array(),
		rot_modes = PackedByteArray(),
		scl_times = PackedFloat32Array(), scl_values = PackedVector3Array(),
		scl_arrive = PackedVector3Array(), scl_leave = PackedVector3Array(),
		scl_modes = PackedByteArray(),
	}]
	root.add_child(sequence)

	var point := Checkpoint.new()
	point.name = "Construction"
	point.restores = {
		hide = [NodePath("../Ordinary")] as Array[NodePath],
		show = [NodePath("../Twin")] as Array[NodePath],
		play = [NodePath("../TwinRise")] as Array[NodePath],
	}
	root.add_child(point)
	get_tree().root.add_child(root)
	return {root = root, ordinary = ordinary, twin = twin,
		sequence = sequence, point = point,
		ordinary_shape = ordinary_shape, twin_shape = twin_shape}

func test_the_point_swaps_the_ordinary_actor_for_its_twin_and_runs_it() -> void:
	var rig := _rig()
	await step(1)
	# Before: the ordinary one is the real one.
	assert_true(rig.ordinary.visible, "the ordinary actor should start present")
	assert_false(rig.twin.visible, "the twin should start hidden")

	rig.point.restore_level()
	await step(1)

	assert_false(rig.ordinary.visible, "the ordinary actor was not hidden")
	assert_true(rig.twin.visible, "the twin was not shown")
	# DRAWN AND SOLID TOGETHER. A twin that is visible but not solid drops the
	# player through it; one that is solid but invisible is worse.
	assert_true(rig.ordinary_shape.disabled, "the ordinary actor is still solid")
	assert_false(rig.twin_shape.disabled, "the twin was shown but left non-solid")
	assert_true(rig.sequence.is_running(), "the twin's own sequence was not played")
	rig.root.queue_free()
	await step(1)

func test_a_point_that_restores_nothing_leaves_the_level_alone() -> void:
	var rig := _rig()
	rig.point.restores = {}
	await step(1)
	rig.point.restore_level()
	await step(1)
	assert_true(rig.ordinary.visible, "an empty restore hid something")
	assert_false(rig.twin.visible, "an empty restore revealed something")
	assert_false(rig.sequence.is_running(), "an empty restore started a sequence")
	rig.root.queue_free()
	await step(1)

func test_a_path_that_resolves_to_nothing_is_ignored() -> void:
	# A checkpoint belongs to a section, and a section can be opened on its
	# own, without the chapter that holds the thing it names.
	var rig := _rig()
	rig.point.restores = {
		show = [NodePath("../NotHere"), NodePath("../Twin")] as Array[NodePath],
		play = [NodePath("../AlsoNotHere")] as Array[NodePath],
	}
	await step(1)
	rig.point.restore_level()
	await step(1)
	assert_true(rig.twin.visible, "a missing path stopped the rest of the list")
	rig.root.queue_free()
	await step(1)

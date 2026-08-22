extends ParkourTest

# A model authored at its own natural height sits on this project's capsule
# without being rebuilt.
#
# The capsule is 1.8 m with the eye 1.66 m above the feet, both measured from
# the original, and every threshold in the game hangs off them -- they do not
# move to suit a model. But the model does not have to BE 1.8 m for its eyes to
# land at 1.66: an anime character built at a normal height and scaled up a few
# percent reads as itself, while one actually modelled at 1.8 m reads, in the
# owner's words, as Attack on Titan.

const TestWorld = preload("res://tests/world_fixture.gd")

const CAPSULE := 1.8

func test_the_default_scale_changes_nothing() -> void:
	# Every body attached before this existed must be placed identically.
	var plain := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3.ZERO)
	var explicit := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3.ZERO, 1.0)
	assert_eq(plain, explicit, "the default scale is not a no-op")

func test_the_feet_stay_on_the_capsule_bottom_at_any_scale() -> void:
	# THE THING THAT MUST NOT BREAK. A feet-origin model scales about its own
	# origin, which is exactly where the mount already puts it -- so changing
	# the scale must never lift the body off the floor or sink it into one.
	for scale in [0.5, 1.0, 1.081, 2.0]:
		var mount := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3.ZERO, scale)
		# The model's own origin, i.e. its feet.
		var feet: Vector3 = mount * Vector3.ZERO
		assert_almost_eq(feet.y, -CAPSULE * 0.5, 0.0001, \
			"at scale %.3f the feet sat %.3f m from the capsule bottom" \
			% [scale, feet.y + CAPSULE * 0.5])

func test_a_point_up_the_body_moves_by_the_scale() -> void:
	# The whole purpose: the owner's VRoid export reads 1.535 m to the eye
	# bones against the 1.660 the camera sits at, so 1.081 is what closes it.
	const EYE_IN_MODEL := 1.535
	var mount := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3.ZERO, 1.081)
	var eye: Vector3 = mount * Vector3(0.0, EYE_IN_MODEL, 0.0)
	var above_feet: float = eye.y + CAPSULE * 0.5
	assert_almost_eq(above_feet, 1.660, 0.005, \
		"the eyes landed %.3f m above the feet instead of on the camera" % above_feet)

func test_scaling_survives_a_mount_offset() -> void:
	# body_mount_offset is a per-model correction applied AFTER placement, so it
	# must shift the body without being multiplied by the scale itself.
	const OFFSET := Vector3(0.0, 0.1, 0.2)
	var mount := Player.compute_mount_transform(CAPSULE, OFFSET, Vector3.ZERO, 2.0)
	var feet: Vector3 = mount * Vector3.ZERO
	assert_almost_eq(feet.y, -CAPSULE * 0.5 + OFFSET.y, 0.0001, \
		"the offset was scaled along with the body")
	assert_almost_eq(feet.z, OFFSET.z, 0.0001, "the offset was scaled along with the body")

func test_a_zero_or_negative_scale_cannot_collapse_the_body() -> void:
	# Neither is anything anyone means by "how tall": zero flattens the body to
	# a point and a negative mirrors it inside out.
	for bad in [0.0, -1.0]:
		var mount := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3.ZERO, bad)
		var up: Vector3 = mount * Vector3(0.0, 1.0, 0.0)
		assert_gt(up.y + CAPSULE * 0.5, 0.0, \
			"a scale of %.1f did not leave the body pointing upward" % bad)

func test_a_half_turn_actually_faces_the_body_the_other_way() -> void:
	# ⚠️ EVERY VRM NEEDS THIS. The VRM specification has models face +Z; Godot's
	# forward is -Z; godot-vrm does not reconcile them. The body is therefore
	# mounted looking backwards, and the symptom is not a backwards body -- it
	# reads as the third-person camera being on the wrong side, with the
	# character apparently running in reverse.
	#
	# Measured on the owner's export before the correction: the eye bones sat
	# +0.023 behind the head bone and the toes +0.106 behind the foot, both
	# positive, i.e. facing +Z. With Vector3(0, 180, 0) both signs flip.
	var mount := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3(0.0, 180.0, 0.0))
	# A point out in front of the MODEL should end up behind the player.
	var nose: Vector3 = mount * Vector3(0.0, 0.0, 1.0)
	assert_lt(nose.z, -0.9, "a half turn left the body still facing +Z")
	# And the feet stay put, because the rotation is about the mount origin.
	var feet: Vector3 = mount * Vector3.ZERO
	assert_almost_eq(feet.y, -CAPSULE * 0.5, 0.0001, "the half turn moved the feet")

func test_rotation_and_scale_compose_without_moving_the_feet() -> void:
	var mount := Player.compute_mount_transform(CAPSULE, Vector3.ZERO, Vector3(0.0, 180.0, 0.0), 1.081)
	var feet: Vector3 = mount * Vector3.ZERO
	assert_almost_eq(feet.y, -CAPSULE * 0.5, 0.0001, "the feet left the capsule bottom")
	var head: Vector3 = mount * Vector3(0.0, 1.535, 0.0)
	assert_almost_eq(head.y + CAPSULE * 0.5, 1.535 * 1.081, 0.001, \
		"the scale stopped applying once a rotation was present")

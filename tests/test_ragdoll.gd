extends ParkourTest

# The body is handed to the physics solver on the way out.
#
# ✅ The owner: "make a ragdoll mode, let's have some fun -- making games is
# supposed to be fun, who cares if it makes you sick." And on the awkward part,
# which is that a ragdoll is a one-way door and the body is left in whatever
# pose physics chose: "we can black the screen for a moment on respawn. Games
# and film are the art of deception; if you cannot do it well, cover it up."

## A humanoid skeleton, built by hand so this depends on no untracked model.
## Only the bones Ragdoll.SEGMENTS names, in a rough standing arrangement.
func _humanoid() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	var layout := {
		"Hips": Vector3(0.0, 0.95, 0.0),
		"Spine": Vector3(0.0, 1.10, 0.0),
		"Chest": Vector3(0.0, 1.25, 0.0),
		"Neck": Vector3(0.0, 1.45, 0.0),
		"Head": Vector3(0.0, 1.55, 0.0),
		"LeftUpperArm": Vector3(-0.18, 1.40, 0.0),
		"LeftLowerArm": Vector3(-0.45, 1.40, 0.0),
		"LeftHand": Vector3(-0.70, 1.40, 0.0),
		"RightUpperArm": Vector3(0.18, 1.40, 0.0),
		"RightLowerArm": Vector3(0.45, 1.40, 0.0),
		"RightHand": Vector3(0.70, 1.40, 0.0),
		"LeftUpperLeg": Vector3(-0.10, 0.90, 0.0),
		"LeftLowerLeg": Vector3(-0.10, 0.50, 0.0),
		"LeftFoot": Vector3(-0.10, 0.05, 0.0),
		"RightUpperLeg": Vector3(0.10, 0.90, 0.0),
		"RightLowerLeg": Vector3(0.10, 0.50, 0.0),
		"RightFoot": Vector3(0.10, 0.05, 0.0),
	}
	for name in layout:
		var i: int = skeleton.add_bone(name)
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, layout[name]))
	add_child(skeleton)
	return skeleton

func test_a_humanoid_gets_one_body_per_segment() -> void:
	# ⚠️ TWELVE, not one per bone. Godot's own "create physical skeleton" gives
	# a body to everything, and the owner's VRM has 146 bones -- every finger
	# joint and every strand of hair carries a spring bone. Twelve is a person.
	var skeleton := _humanoid()
	var ragdoll := Ragdoll.new()
	assert_true(ragdoll.build(skeleton), "a humanoid rig was refused")
	var bodies := 0
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			bodies += 1
	assert_eq(bodies, Ragdoll.SEGMENTS.size(),
		"built %d bodies for %d segments" % [bodies, Ragdoll.SEGMENTS.size()])
	skeleton.queue_free()

func test_every_capsule_is_a_valid_shape() -> void:
	# A capsule's height includes both caps, so a segment shorter than two radii
	# is an INVALID shape rather than a short one -- and two of these segments
	# are genuinely stubby (the hips to the spine is 0.15 m).
	var skeleton := _humanoid()
	Ragdoll.new().build(skeleton)
	for child in skeleton.get_children():
		if not (child is PhysicalBone3D):
			continue
		var shape := child.get_child(0) as CollisionShape3D
		var capsule := shape.shape as CapsuleShape3D
		assert_gt(capsule.height, capsule.radius * 2.0,
			"%s has a capsule %.3f tall with radius %.3f"
			% [child.name, capsule.height, capsule.radius])
	skeleton.queue_free()

func test_a_non_humanoid_rig_is_refused_rather_than_half_built() -> void:
	# THE CASE THAT MATTERS FOR EVERY OTHER BODY. This project's own Blockbench
	# rig names its bones after cubes, and a partial ragdoll -- a floating shin
	# and nothing else -- is worse than none.
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("cube_1")
	skeleton.add_bone("cube_2")
	add_child(skeleton)
	var ragdoll := Ragdoll.new()
	assert_false(ragdoll.build(skeleton), "a rig of cubes was accepted as a person")
	for child in skeleton.get_children():
		assert_false(child is PhysicalBone3D, "it built a body anyway")
	skeleton.queue_free()

func test_simulation_starts_and_stops() -> void:
	var skeleton := _humanoid()
	var ragdoll := Ragdoll.new()
	ragdoll.build(skeleton)
	assert_false(ragdoll.is_simulating(), "it started out simulating")
	ragdoll.start(Vector3(0.0, 4.0, 0.0), RID())
	assert_true(ragdoll.is_simulating(), "it did not take the body over")
	ragdoll.stop()
	assert_false(ragdoll.is_simulating(), "it never gave the body back")
	skeleton.queue_free()

func test_building_twice_does_not_double_the_bodies() -> void:
	# build() is called on every death, and the bodies outlive the first one.
	var skeleton := _humanoid()
	var ragdoll := Ragdoll.new()
	ragdoll.build(skeleton)
	ragdoll.build(skeleton)
	var bodies := 0
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			bodies += 1
	assert_eq(bodies, Ragdoll.SEGMENTS.size(),
		"a second build left %d bodies" % bodies)
	skeleton.queue_free()

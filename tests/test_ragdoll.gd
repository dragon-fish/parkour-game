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

func test_the_joints_are_tightened_from_the_defaults() -> void:
	# ⚠️ NOT WITH softness AND bias, which is where this went first. This
	# project runs JOLT, and Jolt says so at runtime: "Cone twist joint bias is
	# not supported when using Jolt Physics. Any such value will be ignored."
	# Same for softness. Setting them bought twenty-two warnings a death and
	# nothing else. The SPANS are what Jolt honours.
	var skeleton := _humanoid()
	Ragdoll.new().build(skeleton)
	var checked := 0
	for child in skeleton.get_children():
		if not (child is PhysicalBone3D):
			continue
		var bone := child as PhysicalBone3D
		if bone.joint_type != PhysicalBone3D.JOINT_TYPE_CONE:
			continue
		checked += 1
		assert_almost_eq(float(bone.get("joint_constraints/twist_span")),
			Ragdoll.JOINT_TWIST_DEG, 0.01,
			"%s can twist %.0f degrees" % [bone.name,
			float(bone.get("joint_constraints/twist_span"))])
		assert_almost_eq(float(bone.get("joint_constraints/swing_span")),
			Ragdoll.JOINT_SWING_DEG, 0.01,
			"%s can swing %.0f degrees" % [bone.name,
			float(bone.get("joint_constraints/swing_span"))])
	assert_gt(checked, 0, "no jointed bones to check -- the fixture is wrong")
	skeleton.queue_free()

func test_stopping_leaves_nothing_moving() -> void:
	# ✅ THE OWNER: "the order is wrong -- put the ragdoll back before
	# respawning, or the player gets launched the moment they come back."
	# Stopping the simulation hands the bones back to the animation; it does NOT
	# take their velocity away, and the respawn then teleports bodies that are
	# still moving.
	var skeleton := _humanoid()
	var ragdoll := Ragdoll.new()
	ragdoll.build(skeleton)
	ragdoll.start(Vector3(0.0, 4.0, 0.0), RID())
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			(child as PhysicalBone3D).linear_velocity = Vector3(9.0, 9.0, 9.0)
	ragdoll.stop()
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			var bone := child as PhysicalBone3D
			assert_almost_eq(bone.linear_velocity.length(), 0.0, 0.001,
				"%s was left travelling at %.1f m/s"
				% [bone.name, bone.linear_velocity.length()])
	skeleton.queue_free()

# --- the ragdoll owns the body while it runs -----------------------------------

const TestWorld = preload("res://tests/world_fixture.gd")

func test_the_capsule_stops_dead_while_the_ragdoll_runs() -> void:
	# ✅ THE OWNER: "once the ragdoll is running the capsule is meaningless,
	# surely the ragdoll's position is the authority? Otherwise the timing does
	# not line up and the blackout comes early or late."
	#
	# It is worse than a timing problem. The twelve bodies are children of the
	# skeleton, which hangs off the CharacterBody3D -- so every metre the
	# capsule travels TELEPORTS all of them, and the solver spends the whole
	# fall being yanked. That is "the body convulses the moment the ragdoll
	# starts", and two bodies in two different places at the end is the launch
	# on respawn.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	var move := player.move_manager.move_for(Move.FALL_UNCONTROLLED) as AirborneMove
	# A ragdoll this fixture's bodiless player cannot actually build, so stand
	# one in: what is under test is the gate, not the solver.
	player.ragdoll = Ragdoll.new()
	player.ragdoll.build(_humanoid())
	player.ragdoll.start(Vector3.ZERO, RID())
	player.velocity = Vector3(0.0, -20.0, 0.0)
	var before: Vector3 = player.global_position
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	await step(10)
	assert_almost_eq(player.global_position.distance_to(before), 0.0, 0.001,
		"the capsule travelled %.2f m under the ragdoll"
		% player.global_position.distance_to(before))
	player.ragdoll.stop()
	TestWorld.teardown(world)

func test_an_ordinary_uncontrolled_fall_still_falls() -> void:
	# The pair, and the one that stops the gate above from freezing every fall.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	assert_null(player.ragdoll, "the fixture built a ragdoll after all")
	# Lifted off the floor first: a body standing on the ground cannot fall, and
	# the first draft of this asserted that it did.
	player.global_position += Vector3(0.0, 3.0, 0.0)
	await step(1)
	var before: Vector3 = player.global_position
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	await step(10)
	assert_gt(before.y - player.global_position.y, 0.05,
		"a bodiless uncontrolled fall did not fall")
	TestWorld.teardown(world)

func test_the_bodies_go_inert_when_the_ragdoll_stops() -> void:
	# ✅ THE OWNER: "after respawning the character moves in a very strange way
	# -- WASD does something, but it is as if it has been possessed, and it
	# randomly moves at high speed."
	#
	# ⚠️ A PhysicalBone3D THAT IS NOT SIMULATING IS STILL A RigidBody3D, with a
	# collision shape, dragged along by whatever the skeleton does -- including
	# a respawn that teleports it across the level. Twelve of those arriving
	# inside the world geometry at teleport speed will shove anything they can
	# reach, and the capsule is standing right in the middle of them.
	var skeleton := _humanoid()
	var ragdoll := Ragdoll.new()
	ragdoll.build(skeleton)
	ragdoll.start(Vector3.ZERO, RID())
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			assert_ne((child as PhysicalBone3D).collision_layer, 0,
				"%s could not collide while simulating" % child.name)
	ragdoll.stop()
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			var bone := child as PhysicalBone3D
			assert_eq(bone.collision_layer, 0,
				"%s is still on a collision layer after the ragdoll stopped" % bone.name)
			assert_eq(bone.collision_mask, 0,
				"%s can still be collided with after the ragdoll stopped" % bone.name)
	skeleton.queue_free()

func test_the_ragdoll_keeps_off_the_player_s_own_layer() -> void:
	# It shares the world's mask, so the player is excluded by RID on top --
	# but it must not be ON the world layer, or every wall probe in the game
	# starts finding a dead body.
	var skeleton := _humanoid()
	var ragdoll := Ragdoll.new()
	ragdoll.build(skeleton)
	ragdoll.start(Vector3.ZERO, RID())
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			assert_eq((child as PhysicalBone3D).collision_layer & 1, 0,
				"%s is on the world layer" % child.name)
	ragdoll.stop()
	skeleton.queue_free()

func test_the_bodies_are_born_inert() -> void:
	# ⚠️ The window in which twelve rigid bodies exist inside the player must be
	# exactly the window in which they are supposed to. Built live, they push
	# the capsule around from the first death onwards -- and from BEFORE it,
	# since build() runs a frame ahead of start().
	var skeleton := _humanoid()
	Ragdoll.new().build(skeleton)
	for child in skeleton.get_children():
		if child is PhysicalBone3D:
			assert_eq((child as PhysicalBone3D).collision_layer, 0,
				"%s was built able to collide" % child.name)
	skeleton.queue_free()

# --- the uncontrolled fall is terminal --------------------------------------------

func test_a_declared_death_does_not_hand_back_to_walking() -> void:
	# ✅ THE OWNER, with a transitions log showing the loop:
	#
	#   FallUncontrolled -> Walking / Walking -> Falling / Falling ->
	#   FallUncontrolled / FallUncontrolled -> Walking / ...
	#
	# "Isn't the uncontrolled fall terminal? Why does it turn back into an
	# ordinary fall?" It is, and it was returning WALKING -- which, with the
	# capsule frozen in mid-air, fell straight back into another uncontrolled
	# fall, declared another death, and cycled forever.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	player.ragdoll = Ragdoll.new()
	player.ragdoll.build(_humanoid())
	player.ragdoll.start(Vector3.ZERO, RID())
	var deaths := [0]
	player.died_from_fall.connect(func(): deaths[0] += 1)
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	# Long enough for the drift rule to fire and then for a loop to show up.
	await step(180)
	assert_eq(player.move_manager.current_name, Move.FALL_UNCONTROLLED,
		"the fall handed off to %s" % player.move_manager.current_name)
	assert_eq(deaths[0], 1, "the death was declared %d times" % deaths[0])
	player.ragdoll.stop()
	TestWorld.teardown(world)

func test_leaving_the_state_stops_the_ragdoll() -> void:
	# ✅ THE OWNER: "debug noclip is the one thing that can force the state
	# machine to Walking -- I am not sure whether the ragdoll breaks that."
	#
	# It would have. noclip exits this state with no respawn behind it, and the
	# ragdoll would have gone on simulating underneath a player flying around.
	# Whoever starts one owns stopping it.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	player.ragdoll = Ragdoll.new()
	player.ragdoll.build(_humanoid())
	player.move_manager.start(Move.FALL_UNCONTROLLED)
	player.ragdoll.start(Vector3.ZERO, RID())
	assert_true(player.ragdoll.is_simulating(), "the fixture never started one")
	# What noclip does.
	player.move_manager.start(Move.WALKING)
	assert_false(player.ragdoll.is_simulating(),
		"the ragdoll went on simulating under a walking player")
	TestWorld.teardown(world)

func test_noclip_hands_back_a_body_with_nothing_left_on_it() -> void:
	# ✅ THE OWNER: "pressing T also has to reset the model and the camera, or
	# the view ends up misaligned."
	#
	# A death borrows presentation channels the ordinary rules do not take back
	# on their own -- the eye lifted out of a floor, a screen part-way into a
	# blackout that is no longer coming. Every other way out of a death clears
	# them; noclip is a way out that skips the respawn entirely.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(world)
	await step(20)
	var player: Player = world["player"]
	player.camera_rig.set_death_lift(0.3)
	player.screen_effects.set_tint(Color.BLACK, 1.0)
	player.screen_effects.set_blur(1.0)
	player.toggle_noclip()
	await step(2)
	assert_almost_eq(player.camera_rig.position.y,
		player.config.camera.eye_height, 0.05,
		"the eye was left lifted out of a floor it is no longer on")
	assert_almost_eq(player.screen_effects.tint_amount, 0.0, 0.001,
		"the screen was left part-way to black")
	assert_almost_eq(player.screen_effects.blur, 0.0, 0.001,
		"the screen was left blurred")
	player.toggle_noclip()
	TestWorld.teardown(world)

func test_every_cone_points_along_its_own_bone() -> void:
	# ⚠️ MISSING ENTIRELY AT FIRST, and ✅ the owner named the symptom without
	# knowing the cause: "the joints have no angle limit, they can swing 360
	# degrees." A cone-twist limits swing away from ITS OWN axis, and with no
	# joint_rotation that axis is whatever the bone's rest orientation happened
	# to be -- so a 30 degree cone was being applied about an axis unrelated to
	# the limb, which constrains nothing anybody can see.
	var skeleton := _humanoid()
	Ragdoll.new().build(skeleton)
	var checked := 0
	for child in skeleton.get_children():
		if not (child is PhysicalBone3D):
			continue
		var bone := child as PhysicalBone3D
		if bone.joint_type != PhysicalBone3D.JOINT_TYPE_CONE:
			continue
		var index: int = skeleton.find_bone(bone.bone_name)
		# The segment this body spans, the same way Ragdoll measured it.
		var shape := bone.get_child(0) as CollisionShape3D
		var along: Vector3 = shape.position * 2.0
		if along.length() < 0.01:
			continue
		checked += 1
		var cone_axis: Vector3 = Basis.from_euler(bone.joint_rotation).x
		assert_gt(cone_axis.dot(along.normalized()), 0.99,
			"%s's cone points %.2f off its own bone"
			% [bone.name, cone_axis.dot(along.normalized())])
	assert_gt(checked, 0, "no cones to check -- the fixture is wrong")
	skeleton.queue_free()

extends ParkourTest

# The legs point where the body is GOING while the torso keeps facing where it
# is LOOKING.
#
# Verified by reading the resulting GLOBAL bases rather than by looking at it,
# which is the only check available here and happens to be the strict one: the
# hips must have turned by the requested angle about world up, and the shoulders
# must not have turned at all. A twist applied about the wrong axis -- the risk
# in composing local bone rotations, since a humanoid bone's axes are whatever
# its rest pose made them -- fails both halves at once.

const TestWorld = preload("res://tests/world_fixture.gd")
const BODY_PATH := "res://assets/models/test.vrm"

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player_with_body() -> Player:
	if not ResourceLoader.exists(BODY_PATH):
		return null
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	player.body_mount_rotation_degrees = Vector3(0.0, 180.0, 0.0)
	player.body_mount_scale = 1.13
	player.body_head_path = NodePath("GeneralSkeleton/Head")
	player._attach_body(load(BODY_PATH))
	await step(3)
	return player

## Samples bone poses AFTER the modifiers have run.
##
## get_bone_global_pose() alone returns the pose as it was BEFORE the deferred
## modifier pass -- the class reference says so outright: "the final global pose
## can get overridden by modifiers in the deferred process, if you want to
## access the final global pose, use SkeletonModifier3D.modification_processed".
##
## Measuring without this is why a first attempt read exactly zero movement from
## a modifier that was demonstrably running, and it is worth stating loudly:
## the same mistake made the hand IK in feel-backlog 47 look broken.
var _sampled: Dictionary = {}

func _sample_after_modifiers(modifier: SkeletonModifier3D, skeleton: Skeleton3D, 		names: Array[StringName]) -> void:
	_sampled.clear()
	var grab := func() -> void:
		for name in names:
			var index: int = skeleton.find_bone(name)
			if index >= 0:
				_sampled[name] = skeleton.get_bone_global_pose(index)
	modifier.modification_processed.connect(grab, CONNECT_ONE_SHOT)
	await step(1)

func _sampled_yaw(name: StringName) -> float:
	if not _sampled.has(name):
		return 0.0
	var pose: Transform3D = _sampled[name]
	var forward: Vector3 = -pose.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = pose.basis.x
		forward.y = 0.0
	# SIGN MATCHES Basis(Vector3.UP, angle). Rotating a forward of (0,0,-1) by
	# +angle about UP gives (-sin, 0, -cos), so the x term is negated to read
	# back the same +angle. The naive atan2(x, -z) returns its negation, and a
	# first version measured a correct twist as exactly wrong.
	return atan2(-forward.x, -forward.z)

## Yaw of a bone's global basis about world up, in radians.
func _bone_yaw(skeleton: Skeleton3D, name: StringName) -> float:
	var index: int = skeleton.find_bone(name)
	if index < 0:
		return 0.0
	var forward: Vector3 = -skeleton.get_bone_global_pose(index).basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		# A bone whose local -Z is vertical says nothing about yaw; use its X.
		forward = skeleton.get_bone_global_pose(index).basis.x
		forward.y = 0.0
	return atan2(-forward.x, -forward.z)

func test_a_humanoid_body_gets_a_twist() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	assert_not_null(player.torso_twist, "no TorsoTwist was built for a humanoid body")

func test_the_hips_turn_and_the_shoulders_do_not() -> void:
	# THE WHOLE CLAIM, and both halves matter: turning the hips without
	# unwinding the spine turns the entire body, which is not a twist, it is
	# just facing another way.
	#
	# Driven through VELOCITY, because Player._drive_torso_twist() recomputes
	# the request every tick from the travel direction and a value poked in by
	# hand is gone by the next frame. And SAMPLED THROUGH THE SIGNAL, because
	# get_bone_global_pose() on its own returns the pose from before the
	# modifier pass -- see _sample_after_modifiers().
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	var skeleton: Skeleton3D = player._find_skeleton(player.body)
	var bones: Array[StringName] = [TorsoTwist.HIPS, &"UpperChest"]
	player.rotation.y = 0.0

	for i in 10:
		player.velocity = Vector3(0.0, 0.0, -6.0)
		await step(1)
	await _sample_after_modifiers(player.torso_twist, skeleton, bones)
	var hips_before: float = _sampled_yaw(TorsoTwist.HIPS)
	var top_before: float = _sampled_yaw(&"UpperChest")

	# A 45 degree strafe, which the cap trims to torso_twist_max_deg.
	for i in 50:
		player.velocity = Vector3(-4.0, 0.0, -4.0)
		await step(1)
	var wanted: float = player.torso_twist._wanted
	assert_gt(absf(wanted), 0.1, "the strafe asked for no twist")
	assert_almost_eq(player.torso_twist.applied(), wanted, 0.01, "the twist never blended in")

	player.velocity = Vector3(-4.0, 0.0, -4.0)
	await _sample_after_modifiers(player.torso_twist, skeleton, bones)
	var hips_turned: float = wrapf(_sampled_yaw(TorsoTwist.HIPS) - hips_before, -PI, PI)
	var top_turned: float = wrapf(_sampled_yaw(&"UpperChest") - top_before, -PI, PI)
	assert_almost_eq(hips_turned, wanted, 0.10, 		"the hips turned %.3f rad, not the %.3f asked for" % [hips_turned, wanted])
	assert_lt(absf(top_turned), 0.15, 		"the shoulders turned %.3f rad too -- the spine did not unwind it" % top_turned)

func test_releasing_it_untwists() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	player.rotation.y = 0.0
	for i in 50:
		player.velocity = Vector3(-4.0, 0.0, -4.0)
		await step(1)
	assert_gt(absf(player.torso_twist.applied()), 0.1, "the strafe never twisted anything")
	for i in 50:
		player.velocity = Vector3.ZERO
		await step(1)
	assert_almost_eq(player.torso_twist.applied(), 0.0, 0.001, "the body stayed twisted")

func test_strafing_is_what_drives_it() -> void:
	# The angle comes from velocity against facing, so anything carrying the
	# body sideways turns the legs -- not only the strafe keys.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	player.rotation.y = 0.0

	player.velocity = Vector3(0.0, 0.0, -6.0)
	player._drive_torso_twist()
	assert_almost_eq(player.torso_twist._wanted, 0.0, 0.01, \
		"running straight ahead asked for a twist")

	player.velocity = Vector3(-4.0, 0.0, -4.0)
	player._drive_torso_twist()
	assert_gt(absf(player.torso_twist._wanted), 0.1, "a diagonal asked for no twist at all")

	# And the two diagonals must ask for OPPOSITE twists, not the same one.
	var left: float = player.torso_twist._wanted
	player.velocity = Vector3(4.0, 0.0, -4.0)
	player._drive_torso_twist()
	assert_lt(left * player.torso_twist._wanted, 0.0, \
		"both diagonals twisted the same way, so the sign is unsigned")

func test_the_cap_holds() -> void:
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	player.rotation.y = 0.0
	# Straight sideways is 90 degrees, well past any sane cap.
	player.velocity = Vector3(6.0, 0.0, 0.0)
	player._drive_torso_twist()
	var cap: float = deg_to_rad(player.config.pawn.torso_twist_max_deg)
	assert_almost_eq(absf(player.torso_twist._wanted), cap, 0.001, \
		"a sideways strafe asked for %.1f degrees" % rad_to_deg(player.torso_twist._wanted))

func test_walking_straight_backwards_does_not_twist() -> void:
	# THE TWITCH. Straight back is +-180 degrees from the facing, and the SIGN
	# of that is numerically unstable -- the hips flipped between hard left and
	# hard right on float noise. There is no sideways component to follow, so
	# the answer is zero.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	player.rotation.y = 0.0
	for sway in [0.0, 0.0001, -0.0001]:
		player.velocity = Vector3(sway, 0.0, 6.0)
		player._drive_torso_twist()
		assert_almost_eq(player.torso_twist._wanted, 0.0, 0.01, \
			"reversing straight asked for %.3f rad of twist" % player.torso_twist._wanted)

func test_a_backward_diagonal_twists_opposite_to_the_forward_one() -> void:
	# The owner, from watching it: the twist during a backward diagonal came out
	# visually reversed. The plain angle between facing and travel is about 135
	# degrees there, which clamps to the cap with the SAME sign as the matching
	# forward diagonal.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	player.rotation.y = 0.0

	player.velocity = Vector3(-4.0, 0.0, -4.0)
	player._drive_torso_twist()
	var forward_left: float = player.torso_twist._wanted

	player.velocity = Vector3(-4.0, 0.0, 4.0)
	player._drive_torso_twist()
	var backward_left: float = player.torso_twist._wanted

	assert_gt(absf(forward_left), 0.1, "the forward diagonal asked for no twist")
	assert_lt(forward_left * backward_left, 0.0, \
		"forward-left and backward-left twisted the same way (%.3f and %.3f)" \
		% [forward_left, backward_left])

func test_a_wall_run_turns_the_legs_into_the_wall() -> void:
	# Along a wall the travel direction IS the facing, so the ordinary rule asks
	# for nothing. What is wanted is the opposite: the legs turned toward the
	# surface they are supposed to be pushing off.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	player.velocity = Vector3(0.0, 0.0, -6.0)
	player.move_manager.start(Move.WALL_RUN)

	player.wall_side = 1
	player._drive_torso_twist()
	var right_wall: float = player.torso_twist._wanted
	player.wall_side = -1
	player._drive_torso_twist()
	var left_wall: float = player.torso_twist._wanted

	assert_gt(absf(right_wall), 0.01, "a wall run asked for no twist at all")
	assert_lt(right_wall * left_wall, 0.0, "both walls turned the legs the same way")

# --- head look ---------------------------------------------------------------

func _sample_bones(modifier: SkeletonModifier3D, skeleton: Skeleton3D, \
		names: Array[StringName]) -> void:
	_sampled.clear()
	var grab := func() -> void:
		for name in names:
			var index: int = skeleton.find_bone(name)
			if index >= 0:
				_sampled[name] = skeleton.get_bone_global_pose(index)
	modifier.modification_processed.connect(grab, CONNECT_ONE_SHOT)
	await step(1)

func _sampled_pitch(name: StringName) -> float:
	if not _sampled.has(name):
		return 0.0
	var forward: Vector3 = -(_sampled[name] as Transform3D).basis.z
	return asin(clampf(forward.y, -1.0, 1.0))

## Turns the body without movement input, which is what opens the gap the head
## looks along -- _drive_body_yaw holds the model's heading while idle. Poking
## HeadLook.request() directly is pointless: _drive_head_look recomputes it from
## that gap every tick.
func _look_away(player: Player, yaw_deg: float, pitch_deg: float) -> void:
	# SETTLED AT THE CURRENT HEADING FIRST. _drive_body_yaw seeds _visual_yaw
	# from rotation.y the first tick it runs in third person, so setting the new
	# yaw before that tick seeds it to the new value and the gap never opens.
	# An earlier version did exactly that and measured a head that never turned.
	for i in 5:
		await step(1)
	for i in 60:
		player.rotation.y = deg_to_rad(yaw_deg)
		player.camera_rig.set_pitch(deg_to_rad(pitch_deg))
		await step(1)


func test_the_head_reaches_the_camera_and_the_hips_do_not_move() -> void:
	# The shape the owner asked for: the head takes the whole angle, the upper
	# body only a share of it, and the hips are not part of it at all.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	if not player.camera_rig.third_person:
		player.camera_rig.toggle_third_person()
	var skeleton: Skeleton3D = player._find_skeleton(player.body)
	var bones: Array[StringName] = [&"Head", &"UpperChest", &"Hips"]
	await _look_away(player, 60.0, 0.0)
	await _sample_bones(player.head_look, skeleton, bones)

	assert_almost_eq(_sampled_yaw(&"Head"), deg_to_rad(60.0), 0.05, \
		"the head reached %.1f degrees, not the 60 the camera was at" % rad_to_deg(_sampled_yaw(&"Head")))
	var chest: float = rad_to_deg(_sampled_yaw(&"UpperChest"))
	assert_gt(chest, 1.0, "the upper body did not follow at all")
	assert_lt(chest, 25.0, "the upper body followed %.1f degrees -- the whole torso turned" % chest)
	assert_almost_eq(_sampled_yaw(&"Hips"), 0.0, 0.02, "the hips turned with the head")

func test_looking_up_raises_the_face_rather_than_lowering_it() -> void:
	# MEASURED AS EYES MINUS HEAD, which is where the face points, and not from
	# any bone's own -Z. That is the whole lesson: the axis was backwards once --
	# a VRM faces +Z by specification, so a head bone's -Z comes out of the BACK
	# of the skull -- and the check written to catch it read that same -Z and
	# therefore agreed with the bug. It took the owner playing it to notice.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	if not player.camera_rig.third_person:
		player.camera_rig.toggle_third_person()
	var skeleton: Skeleton3D = player._find_skeleton(player.body)
	var bones: Array[StringName] = [&"Head", &"LeftEye", &"RightEye"]

	await _look_away(player, 0.0, 0.0)
	await _sample_bones(player.head_look, skeleton, bones)
	var _level_unused: float = _face_rise()
	await _look_away(player, 0.0, 45.0)
	await _sample_bones(player.head_look, skeleton, bones)
	var looking_up: float = _face_rise()
	await _look_away(player, 0.0, -45.0)
	await _sample_bones(player.head_look, skeleton, bones)
	var looking_down: float = _face_rise()

	# COMPARED AGAINST EACH OTHER, not against level. In the rest pose the
	# eye-to-head vector is very nearly vertical, so tipping it either way
	# shortens its rise -- both ±45 come out BELOW level and a comparison
	# against it says nothing. Up versus down is the claim anyway.
	assert_gt(looking_up, looking_down, 		"looking up left the face lower than looking down (%.4f against %.4f)" 		% [looking_up, looking_down])
	assert_gt(absf(looking_up - looking_down), 0.005, 		"the pitch barely moved the face at all (%.4f vs %.4f)" % [looking_up, looking_down])

## How far the eyes sit above the head bone. Rises when the face tips up.
func _face_rise() -> float:
	if not (_sampled.has(&"LeftEye") and _sampled.has(&"Head")):
		return 0.0
	var eyes: Vector3 = ((_sampled[&"LeftEye"] as Transform3D).origin 		+ (_sampled[&"RightEye"] as Transform3D).origin) * 0.5
	return eyes.y - (_sampled[&"Head"] as Transform3D).origin.y

func test_past_a_quarter_turn_the_model_faces_forward_again() -> void:
	# The owner's rule: past about 90 degrees a person turns their body instead,
	# so the model stops following rather than cranking its neck round.
	var player: Player = await _player_with_body()
	if player == null:
		return pending("no humanoid body at %s" % BODY_PATH)
	if not player.camera_rig.third_person:
		player.camera_rig.toggle_third_person()
	var skeleton: Skeleton3D = player._find_skeleton(player.body)
	await _look_away(player, 120.0, 0.0)
	await _sample_bones(player.head_look, skeleton, [&"Head"])
	assert_almost_eq(_sampled_yaw(&"Head"), 0.0, 0.05, \
		"at 120 degrees the head was still turned %.1f" % rad_to_deg(_sampled_yaw(&"Head")))

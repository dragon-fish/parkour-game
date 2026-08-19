class_name TestCameraConstraints
extends TestCase

func _rig() -> CameraRig:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = scene.instantiate()
	tree.root.add_child(player)
	var config := MovementConfig.new()
	player.setup(config, ScriptedInputSource.new())
	player.camera_rig.setup(config)
	return player.camera_rig

func test_an_unconstrained_move_uses_the_default_pitch_limit() -> void:
	var rig := _rig()
	await step(1)
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	check(rig.rotation.x <= deg_to_rad(89.1), "pitch escaped the default limit")
	check_greater(rig.rotation.x, deg_to_rad(88.0), "pitch did not reach the default limit")
	rig.get_parent().queue_free()
	await step(1)

func test_a_constrained_move_clamps_pitch_harder() -> void:
	# WallRun clamps to +-71.4 degrees, which is where "you cannot look back
	# while on a wall" comes from -- an input constraint, not an animation.
	var rig := _rig()
	await step(1)
	rig.set_look_constraint(Vector3(-deg_to_rad(71.4), -PI, -PI), \
		Vector3(deg_to_rad(71.4), PI, PI), false)
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	check(rig.rotation.x <= deg_to_rad(71.5), "pitch escaped the move's own limit")
	check_greater(rig.rotation.x, deg_to_rad(70.0), "pitch did not reach the move's own limit")
	rig.get_parent().queue_free()
	await step(1)

func test_leaving_a_constrained_move_restores_the_default_limit() -> void:
	var rig := _rig()
	await step(1)
	rig.set_look_constraint(Vector3(-deg_to_rad(20.0), -PI, -PI), \
		Vector3(deg_to_rad(20.0), PI, PI), false)
	for i in 100:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, -100.0), rig.get_parent())
	check_greater(rig.rotation.x, deg_to_rad(80.0), "the clamp stayed applied after clearing")
	rig.get_parent().queue_free()
	await step(1)

func test_a_left_wall_rolls_the_camera_clockwise() -> void:
	# OWNER-REPORTED, and the reason this changes: the previous code
	# deliberately rolled the view TOWARD the wall (its own comment and its
	# archived test both said so), which reads as backwards in play.
	# Clockwise from the player's own viewpoint is a NEGATIVE rotation.z --
	# positive z takes +X toward +Y, i.e. counter-clockwise when viewed from
	# behind the camera.
	var rig := _rig()
	await step(1)
	rig.set_wall_side(-1)
	for i in 60:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	check(rig.rotation.z < -0.01, "a left wall did not roll the camera clockwise")
	rig.get_parent().queue_free()
	await step(1)

func test_the_two_wall_sides_roll_opposite_ways() -> void:
	var rig := _rig()
	await step(1)
	rig.set_wall_side(-1)
	for i in 60:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	var left := rig.rotation.z
	rig.set_wall_side(1)
	for i in 120:
		rig.update_effects(1.0 / 60.0, 5.0, false)
	var right := rig.rotation.z
	check(left * right < 0.0, "the two wall sides rolled the same way")
	rig.get_parent().queue_free()
	await step(1)

func test_entering_the_landing_lockout_does_not_snap_the_pitch() -> void:
	# B2 REGRESSION. LandingConfig used to clamp PITCH to +-0.2 as well as yaw,
	# and unlike yaw the pitch half of a look constraint is genuinely absolute
	# (apply_look() folds it into the global limit with maxf/minf) while
	# CameraRig._pitch is never eased into a new range on entry. A player
	# looking down the drop they are about to land badly from -- exactly the
	# player this move exists for -- had the view SNAP up to -0.2 rad on the
	# lockout's first tick, and LandingMove's own downward sink then played out
	# from that jumped-to position instead of from where they were looking.
	#
	# Reads the SHIPPED LandingConfig rather than literals, so it is the real
	# constraint under test. Verified to go red with min/max_look_constraint.x
	# put back to -+0.2: the pitch jumps by ~1.35 rad on the first call.
	var rig := _rig()
	await step(1)
	var landing: LandingConfig = MovementConfig.new().landing

	# Look steeply down first, with no constraint in force -- the fall this
	# lockout follows.
	rig.clear_look_constraint()
	for i in 200:
		rig.apply_look(Vector2(0.0, 100.0), rig.get_parent())
	var before: float = rig.rotation.x
	check(before < -deg_to_rad(80.0), \
		"test setup is wrong: the view is not steeply enough down (%f rad)" % before)

	rig.set_look_constraint(landing.min_look_constraint, landing.max_look_constraint, \
		landing.absolute_yaw_constraint)
	# A single tick with NO further look input: any movement at all here is the
	# constraint itself yanking the view, not the player.
	rig.apply_look(Vector2.ZERO, rig.get_parent())
	check_approx(rig.rotation.x, before, 0.0001, \
		"entering the landing lockout snapped the view pitch")

	rig.get_parent().queue_free()
	await step(1)

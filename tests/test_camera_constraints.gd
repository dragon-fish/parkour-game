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

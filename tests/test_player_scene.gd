extends TestCase

const SCENE := "res://scenes/player/player.tscn"

func test_player_scene_has_the_expected_structure() -> void:
	await step(1)
	check(ResourceLoader.exists(SCENE), "player.tscn was not generated")
	var packed: PackedScene = ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	var player = packed.instantiate()
	tree.root.add_child(player)
	await step(1)

	check(player is CharacterBody3D, "root is not a CharacterBody3D")
	check(player.get_node_or_null("CollisionShape3D") != null, "CollisionShape3D missing")
	check(player.get_node_or_null("CameraRig") != null, "CameraRig missing")
	check(player.get_node_or_null("CameraRig/Camera3D") != null, "Camera3D missing")
	check(player.get_node_or_null("BodyRoot") != null, "BodyRoot (P5 reservation) missing")
	# Fails open otherwise: Player.has_headroom() treats an absent probe as
	# "always clear" (so hand-built test players without one still work), so
	# a generator regression that silently dropped this node would make every
	# slide ignore ceilings with no test catching it.
	check(player.get_node_or_null("StandClearance") != null, "StandClearance (headroom probe) missing")

	# The exported reference must survive serialisation, or the camera silently
	# does nothing at runtime.
	check(player.camera_rig != null, "camera_rig export was not wired")
	check(player.camera_rig == player.get_node("CameraRig"), "camera_rig points at the wrong node")

	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	check(capsule != null, "collision shape is not a capsule")
	check_approx(capsule.height, 1.8, 0.001, "capsule height wrong")
	check_approx(capsule.radius, 0.4, 0.001, "capsule radius wrong")

	# The probe is built from capsule.duplicate() in the generator specifically
	# so it cannot drift from the body's actual standing size — assert that
	# relationship rather than re-pinning the probe to its own 1.8/0.4 literal.
	var probe := player.get_node_or_null("StandClearance") as ShapeCast3D
	if probe != null:
		var probe_shape := probe.shape as CapsuleShape3D
		check(probe_shape != null, "StandClearance shape is not a capsule")
		if probe_shape != null:
			check_approx(probe_shape.height, capsule.height, 0.001, \
				"StandClearance capsule height must match the body's standing capsule")
			check_approx(probe_shape.radius, capsule.radius, 0.001, \
				"StandClearance capsule radius must match the body's standing capsule")

	player.queue_free()
	await step(1)

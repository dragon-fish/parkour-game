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

	# The exported reference must survive serialisation, or the camera silently
	# does nothing at runtime.
	check(player.camera_rig != null, "camera_rig export was not wired")
	check(player.camera_rig == player.get_node("CameraRig"), "camera_rig points at the wrong node")

	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	check(capsule != null, "collision shape is not a capsule")
	check_approx(capsule.height, 1.8, 0.001, "capsule height wrong")
	check_approx(capsule.radius, 0.4, 0.001, "capsule radius wrong")

	player.queue_free()
	await step(1)

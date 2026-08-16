class_name TestWorld
extends RefCounted

# Builds a minimal physics world: one large floor slab and one player driven
# by a ScriptedInputSource. Callers must await one physics frame after build()
# before touching global transforms.
#
# Filename deliberately does NOT start with "test_": tests/test_runner.gd
# discovers every tests/test_*.gd file and tries to run it as a TestCase.
# This is a RefCounted helper, not a TestCase, so it must stay outside that
# glob or the runner hangs trying to treat it as one.

static func build(tree: SceneTree, cfg: MovementConfig) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	tree.root.add_child(floor_body)

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = player_scene.instantiate()
	tree.root.add_child(player)

	var input := ScriptedInputSource.new()
	player.setup(cfg, input)
	# The rig is present in the real scene, so give it the same config the
	# player got — otherwise its update_effects() no-ops and the tests exercise
	# a different code path than the game does.
	if player.camera_rig != null:
		player.camera_rig.setup(cfg)

	return {"player": player, "input": input, "floor": floor_body}

## Places the floor so its top surface is y = 0 and drops the player onto it.
## Must be called after at least one physics frame has elapsed.
static func place(world: Dictionary) -> void:
	world["floor"].global_position = Vector3(0.0, -0.5, 0.0)
	world["player"].global_position = Vector3(0.0, 0.95, 0.0)

static func teardown(world: Dictionary) -> void:
	world["player"].queue_free()
	world["floor"].queue_free()

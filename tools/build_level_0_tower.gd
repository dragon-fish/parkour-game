extends SceneTree

# Generates scenes/levels/level_0/tower.tscn from SpiralTower's arithmetic.
#
# ONE MATERIAL FOR EVERY PLATFORM. A material's GPU pipeline is compiled the
# first time it is actually drawn, so a platform with a material of its own
# costs a frame the moment it comes into view -- and the symptom is "only the
# seventh lap stutters". DO NOT give a platform a special material.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_level_0_tower.gd

const OUTPUT := "res://scenes/levels/level_0/tower.tscn"

## The lit end of the palette; the same near-white the plain is.
const PALE := Color(0.93, 0.96, 0.98)
## The orb: the one bright thing in the level, and the way out of it.
const ORB_COLOUR := Color(1.0, 0.98, 0.92)
const ORB_RADIUS := 1.2
## Reach, not size: the ball a body has to touch is bigger than the ball it
## can see, so the ending is not a pixel-perfect landing.
const ORB_REACH := 2.2

var _root: Node3D

func _initialize() -> void:
	var shape := SpiralTower.DEFAULT_SHAPE
	var root := Node3D.new()
	root.name = "Tower"
	_root = root

	var surface := StandardMaterial3D.new()
	surface.resource_name = "TowerSurface"
	surface.albedo_color = PALE
	surface.metallic = 0.2
	surface.roughness = 0.35

	var per_turn: int = SpiralTower.per_turn(shape)
	for index in SpiralTower.platform_count(shape):
		root.add_child(_platform(shape, index, surface))
		if index % per_turn == 0:
			root.add_child(_checkpoint(shape, index, index / per_turn))

	root.add_child(_orb(shape))

	# OWNERSHIP IS CLAIMED ONCE, OVER THE ASSEMBLED TREE. Godot only serialises
	# a node whose owner is the scene root, and a node cannot be given an owner
	# before it is inside that root's tree.
	_claim(root)

	DirAccess.make_dir_recursive_absolute("res://scenes/levels/level_0")
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)

func _platform(shape: Dictionary, index: int, surface: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Platform%02d" % index
	var size := Vector3(float(shape.platform_length), float(shape.thickness),
		float(shape.platform_width))
	# The origin SpiralTower reports is the running surface, so the slab hangs
	# below it.
	body.position = SpiralTower.platform_origin(shape, index) \
		- Vector3(0.0, float(shape.thickness) * 0.5, 0.0)
	body.rotation = Vector3(0.0, SpiralTower.platform_yaw(shape, index), 0.0)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	body.add_child(shape_node)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	# ON THE NODE, not on the mesh: material_override is a top-level property,
	# and reaching a material through Mesh in the inspector takes the editor
	# down (see .claude/skills/authoring-godot-scene-files).
	mesh_instance.material_override = surface
	body.add_child(mesh_instance)
	return body

## One checkpoint per turn. Ranked so a fall back through the ones already
## climbed cannot undo the climb; numbered in tens so a point can be inserted
## later without renumbering.
func _checkpoint(shape: Dictionary, index: int, turn: int) -> Area3D:
	var area := Area3D.new()
	area.name = "Checkpoint%02d" % index
	area.set_script(load("res://scripts/level/checkpoint.gd"))
	area.set("index", (turn + 1) * 10)
	area.set("display_name", "塔 第%d圈" % (turn + 1))
	# Origin = BODY CENTRE, the convention Checkpoint and SpawnPoint share.
	area.position = SpiralTower.platform_origin(shape, index) + Vector3(0.0, 0.95, 0.0)
	area.rotation = Vector3(0.0, SpiralTower.platform_yaw(shape, index), 0.0)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box := BoxShape3D.new()
	box.size = Vector3(float(shape.platform_length), 2.4, float(shape.platform_width))
	shape_node.shape = box
	area.add_child(shape_node)
	return area

func _orb(shape: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.name = "Orb"
	area.position = SpiralTower.summit_origin(shape)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var sphere := SphereShape3D.new()
	sphere.radius = ORB_REACH
	shape_node.shape = sphere
	area.add_child(shape_node)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := SphereMesh.new()
	mesh.radius = ORB_RADIUS
	mesh.height = ORB_RADIUS * 2.0
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	# UNSHADED AND EMISSIVE. The orb is a light, not a lit object -- a shaded
	# ball in a shadowless level reads as a prop.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = ORB_COLOUR
	material.emission_enabled = true
	material.emission = ORB_COLOUR
	material.emission_energy_multiplier = 3.0
	mesh_instance.material_override = material
	area.add_child(mesh_instance)

	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = ORB_COLOUR
	light.omni_range = 24.0
	light.light_energy = 3.0
	light.shadow_enabled = false
	area.add_child(light)
	return area

func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)

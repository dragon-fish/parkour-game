extends SceneTree

# Generates the tutorial's lesson scenes under scenes/levels/level_0/.
#
# A LESSON IS ALSO A PLAYABLE LEVEL. The author shapes this geometry by running
# around in it, so every lesson carries its own Sun, WorldEnvironment,
# SpawnPoint, floor and Player. The tutorial takes ONLY the Content subtree
# (LessonContent.take) and throws the rest away, so none of that scaffolding
# ever reaches the real level.
#
# BLOCKS ARE BOXES, AND A BOX GETS A CubeSwarm INSTEAD OF A MeshInstance3D. The
# swarm is what comes apart when the lesson is passed; a plain mesh would fall
# back to the alpha fade and read as a different system from everything around
# it.
#
# EVERY NUMBER IN _LESSONS IS A TUNING VALUE. They are the author's to drag;
# nothing asserts on them.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_level_0_lessons.gd

const OUT_DIR := "res://scenes/levels/level_0"

## The lit end of the palette, and the horizon. Same pair the void plain uses,
## so a lesson opened on its own looks like the level it belongs to.
const PALE := Color(0.93, 0.96, 0.98)
const COOL := Color(0.78, 0.86, 0.93)
## The guide colour. Red is what the player is meant to reach for.
const GUIDE := Color(0.91, 0.02, 0.0)

## The lessons. Named fields; see .claude/skills/naming-config-fields.
##   file    String -- the .tscn basename under OUT_DIR
##   root    String -- the scene root's node name
##   spawn   Vector3 -- where the body starts, body centre
##   blocks  Array of {name, size, at, colour}
##           name    String -- the StaticBody3D's node name
##           size    Vector3 -- metres
##           at      Vector3 -- centre of the box, level space
##           colour  Color -- the swarm's packed colour
const _LESSONS := [
	{
		file = "lesson_vault", root = "LessonVault", spawn = Vector3(0.0, 0.95, 16.0),
		blocks = [
			{name = "Wall", size = Vector3(9.0, 1.0, 0.6), at = Vector3(0.0, 0.5, 0.0), colour = PALE},
			{name = "Lip", size = Vector3(9.0, 0.08, 0.7), at = Vector3(0.0, 1.04, 0.0), colour = GUIDE},
		],
	},
	{
		file = "lesson_slide", root = "LessonSlide", spawn = Vector3(0.0, 0.95, 20.0),
		blocks = [
			# The opening is 1.1 m: a standing body does not fit, a sliding one
			# does, and the run-up is what turns the crouch into a slide.
			{name = "Roof", size = Vector3(7.0, 0.7, 5.0), at = Vector3(0.0, 1.45, 0.0), colour = PALE},
			{name = "LegLeft", size = Vector3(0.8, 1.1, 5.0), at = Vector3(-3.1, 0.55, 0.0), colour = PALE},
			{name = "LegRight", size = Vector3(0.8, 1.1, 5.0), at = Vector3(3.1, 0.55, 0.0), colour = PALE},
			{name = "Lintel", size = Vector3(7.0, 0.1, 0.2), at = Vector3(0.0, 1.16, 2.6), colour = GUIDE},
		],
	},
	{
		file = "lesson_wall_run", root = "LessonWallRun", spawn = Vector3(0.0, 0.95, 22.0),
		blocks = [
			{name = "Wall", size = Vector3(14.0, 4.5, 0.9), at = Vector3(0.0, 2.25, 0.0), colour = PALE},
			{name = "Line", size = Vector3(14.0, 0.12, 0.95), at = Vector3(0.0, 1.7, 0.0), colour = GUIDE},
		],
	},
	{
		file = "lesson_grab", root = "LessonGrab", spawn = Vector3(0.0, 0.95, 18.0),
		blocks = [
			# Too tall to vault, low enough that a jump puts the hands on the
			# lip: the block is read as a ledge, not as a wall.
			{name = "Block", size = Vector3(7.0, 2.4, 4.0), at = Vector3(0.0, 1.2, 0.0), colour = PALE},
			{name = "Edge", size = Vector3(7.0, 0.1, 0.3), at = Vector3(0.0, 2.45, 1.85), colour = GUIDE},
		],
	},
]

## Wide enough that the author cannot run off it while shaping a block.
const FLOOR_SPAN := 120.0
const FLOOR_THICKNESS := 2.0

var _root: Node3D

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for lesson in _LESSONS:
		_write(lesson)
	quit(0)

func _write(lesson: Dictionary) -> void:
	var root := Node3D.new()
	root.name = lesson.root
	_root = root
	root.set_script(load("res://scripts/level/arena.gd"))
	root.set("config", load("res://presets/default.tres"))
	# She cannot die in a lesson either -- same contract the tutorial runs
	# under, so a lesson opened on its own behaves the way it will in place.
	root.set("rescue_below_hp", 30.0)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	# NO SHADOWS. A shadow is a statement about the floor being a surface, and
	# this one is not meant to read as one.
	sun.shadow_enabled = false
	root.add_child(sun)

	root.add_child(_environment())

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.set_script(load("res://scripts/level/spawn_point.gd"))
	spawn.position = lesson.spawn
	root.add_child(spawn)

	root.add_child(_floor())

	# BEFORE anything that reads player.move_manager. Siblings run _ready() in
	# tree order, so a node placed above Player would find no manager to
	# connect to. Nothing here does, but the order is the level's contract.
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	root.add_child(player)
	root.set("player", player)
	root.set("spawn_point", spawn)

	var content := Node3D.new()
	content.name = "Content"
	root.add_child(content)
	for block in lesson.blocks:
		content.add_child(_block(block))

	_claim(root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var path: String = "%s/%s.tscn" % [OUT_DIR, lesson.file]
	var save_error := ResourceSaver.save(packed, path)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", path)

func _environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	# THE HORIZON PAIR MUST MATCH. Sky and ground meeting at the same value is
	# what deletes the horizon; the gradient lives above and below it.
	sky_material.sky_horizon_color = PALE
	sky_material.ground_horizon_color = PALE
	sky_material.sky_top_color = COOL
	sky_material.ground_bottom_color = COOL
	sky_material.sun_angle_max = 0.0
	sky_material.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.223529, 0.466667, 0.741176)
	# The acrylic ground is glossy; without this it reflects nothing.
	environment.ssr_enabled = true
	environment.ssr_max_steps = 32
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_env.environment = environment
	return world_env

func _floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	var size := Vector3(FLOOR_SPAN, FLOOR_THICKNESS, FLOOR_SPAN)

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	# THE SHARED ACRYLIC PRESET, not a fresh material: a lesson should look
	# like the level it is going to be dropped into.
	mesh_instance.material_override = load("res://materials/acrylic_void.tres")
	body.add_child(mesh_instance)
	return body

## One block: collision, and a swarm INSTEAD OF a mesh. The swarm is the only
## visible geometry, so nothing is drawn twice while it comes apart.
func _block(block: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block.name
	body.position = block.at

	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var box := BoxShape3D.new()
	box.size = block.size
	shape.shape = box
	body.add_child(shape)

	var swarm := MultiMeshInstance3D.new()
	swarm.name = "Swarm"
	swarm.set_script(load("res://scripts/level/cube_swarm.gd"))
	swarm.set("box_size", block.size)
	swarm.set("base_color", block.colour)
	body.add_child(swarm)
	return body

## Hands every descendant of the scene root its ownership. Godot only
## serialises a node whose owner is the scene root, and a node cannot be given
## one before it is inside that root's tree -- so this runs once, at the end,
## over the assembled tree. Nodes that already have an owner (an instanced
## sub-scene's children) are left alone.
func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)

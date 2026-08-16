extends SceneTree

# Generates scenes/main.tscn: the graybox arena. P0 only builds the northern
# jump area; the slide / vault / wall-run areas arrive with P1-P3 so we never
# carry geometry nothing uses yet.
#
# Run with:
#   .engine\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
#       --script res://tools/build_main_scene.gd

const OUTPUT := "res://scenes/main.tscn"

var _root: Node3D

## Colour -> StandardMaterial3D, so boxes sharing a colour (all 6 gaps, all 6
## steps, all 3 drop towers) share one material resource instead of each
## getting a byte-identical copy. Shapes and meshes are deliberately NOT
## cached here: every box's size genuinely differs, so there is nothing to
## share for those.
var _materials: Dictionary = {}

func _initialize() -> void:
	_run()

func _material_for(colour: Color) -> StandardMaterial3D:
	if not _materials.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		_materials[colour] = material
	return _materials[colour]

## Solid box with explicit collision. CSGBox3D is avoided on purpose: its
## collision body is generated at runtime and is not reliably present on the
## first physics frame in a headless run.
func _box(box_name: String, size: Vector3, pos: Vector3, colour: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = pos

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
	mesh.material = _material_for(colour)
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)

	return body

## child is typed Node rather than Node3D: WorldEnvironment extends Node
## directly (it carries no transform), so a Node3D-only signature would
## reject it here.
func _attach(parent: Node3D, child: Node) -> void:
	parent.add_child(child)
	child.owner = _root
	for grandchild in child.get_children():
		grandchild.owner = _root

func _run() -> void:
	_root = Node3D.new()
	_root.name = "Arena"
	_root.set_script(load("res://scripts/level/arena.gd"))

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	light.shadow_enabled = true
	_attach(_root, light)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = environment
	_attach(_root, world_env)

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.position = Vector3(0.0, 1.0, 0.0)
	_attach(_root, spawn)

	var ground := Color(0.42, 0.44, 0.47)
	var gap_colour := Color(0.38, 0.52, 0.62)
	var step_colour := Color(0.56, 0.50, 0.38)
	var drop_colour := Color(0.58, 0.40, 0.44)
	# Distinct from every JumpArea colour above so the slide practice area
	# reads as its own thing at a glance, and its walkable surfaces don't
	# blend into the base Floor colour in screenshots.
	var slide_colour := Color(0.40, 0.58, 0.42)
	var tunnel_colour := Color(0.32, 0.34, 0.38)

	_attach(_root, _box("Floor", Vector3(60.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0), ground))

	var jump_area := Node3D.new()
	jump_area.name = "JumpArea"
	jump_area.position = Vector3(0.0, 0.0, -12.0)
	_attach(_root, jump_area)

	# Increasing gaps: 2.0, 2.5, 3.0, 3.5, 4.0 m between platform edges.
	# Whichever platform the player can still reach reveals the jump range.
	var gap_z := [0.0, -5.0, -10.5, -16.5, -23.0, -30.0]
	for i in gap_z.size():
		_attach(jump_area, _box("Gap%d" % (i + 1), Vector3(3.0, 1.0, 3.0),
			Vector3(-9.0, 0.5, gap_z[i]), gap_colour))

	# Increasing heights: 1..6 m, for reading off the maximum step-up.
	for i in 6:
		var height := float(i + 1)
		_attach(jump_area, _box("Step%d" % (i + 1), Vector3(3.0, height, 3.0),
			Vector3(0.0, height * 0.5, -4.0 * i), step_colour))

	# Drop towers, for comparing landing-dip strength across fall heights.
	_attach(jump_area, _box("DropLow", Vector3(4.0, 1.0, 4.0), Vector3(9.0, 3.0, 0.0), drop_colour))
	_attach(jump_area, _box("DropMid", Vector3(4.0, 1.0, 4.0), Vector3(9.0, 8.0, -6.0), drop_colour))
	_attach(jump_area, _box("DropHigh", Vector3(4.0, 1.0, 4.0), Vector3(9.0, 15.0, -12.0), drop_colour))

	var slide_area := Node3D.new()
	slide_area.name = "SlideArea"
	# x=14 put TunnelWallL at world x 10..11, overlapping the drop towers
	# (world x 7..11). x=18 puts it at 14..15, leaving 3 m clear.
	slide_area.position = Vector3(18.0, 0.0, 0.0)
	_attach(_root, slide_area)

	# Downhill ramp into the tunnel, for feeling out whether a slide carries
	# speed downhill. Rotated, so it cannot come from _box() alone.
	var ramp_up := _box("RampUp", Vector3(6.0, 1.0, 10.0), Vector3(0.0, 1.2, -6.0), slide_colour)
	ramp_up.rotation.x = deg_to_rad(-12.0)
	_attach(slide_area, ramp_up)

	# Tunnel: roof underside at y=2.2, floor top at y=1.0, clearance 1.2 m.
	# Taller than the sliding capsule (0.9 m) and shorter than standing
	# (1.8 m) — only a slide fits. See task-4-brief.md for the arithmetic.
	_attach(slide_area, _box("TunnelFloor", Vector3(6.0, 1.0, 14.0), Vector3(0.0, 0.5, -18.0), slide_colour))
	_attach(slide_area, _box("TunnelRoof", Vector3(6.0, 1.0, 14.0), Vector3(0.0, 2.7, -18.0), tunnel_colour))
	_attach(slide_area, _box("TunnelWallL", Vector3(1.0, 3.0, 14.0), Vector3(-3.5, 1.5, -18.0), tunnel_colour))
	_attach(slide_area, _box("TunnelWallR", Vector3(1.0, 3.0, 14.0), Vector3(3.5, 1.5, -18.0), tunnel_colour))

	# Exit runway, for reading off how much speed the slide delivered.
	_attach(slide_area, _box("Runway", Vector3(6.0, 1.0, 20.0), Vector3(0.0, 0.5, -35.0), slide_colour))

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player := player_scene.instantiate()
	player.name = "Player"
	_root.add_child(player)
	player.owner = _root
	# An instantiated sub-scene keeps its own internal ownership; marking only
	# the instance root is what makes it serialise as an instance rather than
	# an expanded copy.

	_root.player = player
	_root.spawn_point = spawn

	var hud := CanvasLayer.new()
	hud.name = "DebugHud"
	hud.set_script(load("res://scripts/debug/debug_hud.gd"))
	_root.add_child(hud)
	hud.owner = _root
	hud.player = player

	var panel := CanvasLayer.new()
	# The node name is load-bearing: Arena._ready() finds it with
	# get_node_or_null("TuningPanel") to inject the shared config.
	panel.name = "TuningPanel"
	panel.set_script(load("res://scripts/debug/tuning_panel.gd"))
	_root.add_child(panel)
	panel.owner = _root

	DirAccess.make_dir_recursive_absolute("res://scenes")
	var packed := PackedScene.new()
	var pack_error := packed.pack(_root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)

extends SceneTree

# Generates scenes/debug_levels/void_plain.tscn: a bare torus plain for judging
# the wrap by hand. Built in code for the same reason the arena is -- a
# hand-written .tscn in this project has cost sessions (see
# .claude/skills/authoring-godot-scene-files).
#
# THE CONTENT IS PERIODIC ON PURPOSE. A torus whose furniture sits in only one
# period gives itself away the instant the player looks across a seam: the
# ground beyond x = +50 would be empty where the world says x = -50 stands.
# Tiling the boxes 3x3 makes both sides of every seam identical, which is what
# the finished level gets for free from the collapse radius (nothing beyond it
# is drawn at all).
#
# A correct wrap is therefore INVISIBLE, which is why this scene carries a
# readout (VoidProbe) and two coloured seam lines: without them there is no way
# to tell a crossing from an ordinary stride.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_void_plain.gd

const OUTPUT := "res://scenes/debug_levels/void_plain.tscn"

## Matches TorusWrap.period's default. The plain is built three periods wide so
## the player can see a whole neighbouring copy across either seam.
const PERIOD := 100.0
## How many metres of floor to lay. Three periods plus a margin, so a body
## standing at a seam still has ground under the copy it is looking at.
const FLOOR_SPAN := PERIOD * 3.0 + 20.0
const FLOOR_THICKNESS := 2.0
## One line every this many metres, for reading distance travelled at a glance.
const GRID_STEP := 10.0
const GRID_WIDTH := 0.12
## The seam lines at +/- PERIOD/2, in their own colour.
const SEAM_WIDTH := 0.5

## The scene root, held so _attach() can hand every descendant the ownership
## Godot serialises by. A node whose owner is its immediate parent rather than
## the scene root is silently dropped from the saved .tscn -- the grid and the
## furniture vanished exactly that way once.
var _root: Node3D

func _initialize() -> void:
	_run()

func _run() -> void:
	var root := Node3D.new()
	root.name = "VoidPlain"
	_root = root
	root.set_script(load("res://scripts/level/arena.gd"))
	# OFF here. The calibration course is a bench of graded obstacles that
	# belongs to the arena; this scene is about the ground being endless.
	root.set("load_calibration_course", false)
	# She cannot die here either -- a fall off the plain should cost time and
	# nothing else, same contract the tutorial itself runs under.
	root.set("rescue_below_hp", 30.0)
	var fog := FogConfig.new()
	fog.resource_local_to_scene = true
	# No fog. The whole question this scene exists to answer is whether a seam
	# is visible, and a curtain of fog would answer it by hiding the evidence.
	fog.enabled = false
	root.set("fog", fog)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.shadow_enabled = true
	_attach(root, sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = load("res://assets/sky/day_sky.tres")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.223529, 0.466667, 0.741176)
	world_env.environment = environment
	_attach(root, world_env)

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.set_script(load("res://scripts/level/spawn_point.gd"))
	spawn.position = Vector3(0.0, 0.95, 0.0)
	_attach(root, spawn)

	_attach(root, _floor())
	_attach(root, _grid())
	_attach(root, _seams())
	_attach(root, _furniture())

	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	root.add_child(player)
	root.set("player", player)
	root.set("spawn_point", spawn)

	var wrap := Node.new()
	wrap.name = "TorusWrap"
	wrap.set_script(load("res://scripts/level/torus_wrap.gd"))
	wrap.set("period", PERIOD)
	root.add_child(wrap)
	wrap.set("player", player)

	var probe := CanvasLayer.new()
	probe.name = "VoidProbe"
	probe.set_script(load("res://scripts/debug/void_probe.gd"))
	root.add_child(probe)
	probe.set("player", player)
	probe.set("wrap", wrap)

	# OWNERSHIP IS SET ONCE, HERE, OVER THE WHOLE TREE. Godot only serialises a
	# node whose owner is the scene root, and a node cannot be given an owner
	# before it is inside that root's tree -- so setting it while building a
	# detached subtree silently does nothing. Two rounds of this scene came out
	# missing its furniture's collision shapes that way. Claim ownership after
	# everything is assembled, not as each piece is made.
	_claim(root)

	DirAccess.make_dir_recursive_absolute("res://scenes/debug_levels")
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)

func _attach(parent: Node, child: Node) -> void:
	parent.add_child(child)

## Hands every descendant of the scene root its ownership. See the call site.
func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)

func _material(colour: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

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
	_attach(body, shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(Color(0.82, 0.85, 0.89))
	mesh_instance.mesh = mesh
	_attach(body, mesh_instance)
	return body

## Flat stripes every GRID_STEP metres, so distance covered is readable without
## looking at the numbers. Decoration only -- no collision.
func _grid() -> Node3D:
	var grid := Node3D.new()
	grid.name = "Grid"
	var half: float = FLOOR_SPAN * 0.5
	var colour := Color(0.62, 0.68, 0.76)
	var line: int = 0
	var at: float = -half
	while at <= half:
		# The seam lines own +/- PERIOD/2; leave those to _seams().
		if not is_equal_approx(absf(at), PERIOD * 0.5):
			_attach(grid, _stripe("GridX%d" % line, Vector3(GRID_WIDTH, 0.02, FLOOR_SPAN),
				Vector3(at, 0.011, 0.0), colour))
			_attach(grid, _stripe("GridZ%d" % line, Vector3(FLOOR_SPAN, 0.02, GRID_WIDTH),
				Vector3(0.0, 0.011, at), colour))
		line += 1
		at += GRID_STEP
	return grid

## The four seams, in their own colour and wider than a grid line. Crossing one
## is the event everything else in this scene exists to make readable.
func _seams() -> Node3D:
	var seams := Node3D.new()
	seams.name = "Seams"
	var half: float = PERIOD * 0.5
	var colour := Color("#e90100")
	for sign_index in 2:
		var at: float = half if sign_index == 0 else -half
		_attach(seams, _stripe("SeamX%d" % sign_index,
			Vector3(SEAM_WIDTH, 0.02, FLOOR_SPAN), Vector3(at, 0.012, 0.0), colour))
		_attach(seams, _stripe("SeamZ%d" % sign_index,
			Vector3(FLOOR_SPAN, 0.02, SEAM_WIDTH), Vector3(0.0, 0.012, at), colour))
	return seams

func _stripe(stripe_name: String, size: Vector3, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = stripe_name
	mesh_instance.position = pos
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(colour, true)
	mesh_instance.mesh = mesh
	return mesh_instance

## Boxes to look at, TILED ONE PERIOD APART IN BOTH AXES. The copies are what
## make a crossing invisible: whatever stands at x will also stand at x +/-
## PERIOD, so the view across a seam matches the view behind you. Remove the
## tiling and the plain stops being a torus to the eye, whatever the code does.
func _furniture() -> Node3D:
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	# One period's worth of content. Deliberately off-centre and uneven: a
	# symmetric arrangement would look the same after a crossing even if the
	# wrap were broken, which would prove nothing.
	var pieces: Array[Dictionary] = [
		{size = Vector3(4.0, 3.0, 4.0), at = Vector3(-18.0, 1.5, -12.0), colour = Color(0.55, 0.60, 0.68)},
		{size = Vector3(2.0, 8.0, 2.0), at = Vector3(12.0, 4.0, -30.0), colour = Color(0.45, 0.50, 0.58)},
		{size = Vector3(10.0, 1.2, 3.0), at = Vector3(28.0, 0.6, 8.0), colour = Color(0.62, 0.66, 0.72)},
		{size = Vector3(3.0, 5.0, 3.0), at = Vector3(-34.0, 2.5, 24.0), colour = Color(0.50, 0.55, 0.63)},
		{size = Vector3(6.0, 2.0, 6.0), at = Vector3(4.0, 1.0, 36.0), colour = Color(0.58, 0.63, 0.70)},
	]
	for tile_x in [-1, 0, 1]:
		for tile_z in [-1, 0, 1]:
			var offset := Vector3(float(tile_x) * PERIOD, 0.0, float(tile_z) * PERIOD)
			var index: int = 0
			for piece in pieces:
				var body := StaticBody3D.new()
				body.name = "Box%d_%d%d" % [index, tile_x + 1, tile_z + 1]
				body.position = piece["at"] + offset
				var shape := CollisionShape3D.new()
				shape.name = "Collision"
				var box := BoxShape3D.new()
				box.size = piece["size"]
				shape.shape = box
				_attach(body, shape)
				var mesh_instance := MeshInstance3D.new()
				mesh_instance.name = "Mesh"
				var mesh := BoxMesh.new()
				mesh.size = piece["size"]
				mesh.material = _material(piece["colour"])
				mesh_instance.mesh = mesh
				_attach(body, mesh_instance)
				_attach(furniture, body)
				index += 1
	return furniture

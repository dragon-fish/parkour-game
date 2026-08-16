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

## A sloped deck, built from _box() plus a rotation.x — the one piece of arena
## geometry an axis-aligned box cannot express.
##
## The deck's TOP FACE is placed to pass exactly through the two requested
## points (z_near, y_near) and (z_far, y_far), measured in the parent's local
## space, where "near" is the +Z end and "far" the -Z end. Placing the top face
## rather than the box centre is what lets a ramp meet the floor or a platform
## with no lip: ask for y = 0 and the deck emerges from the floor exactly there,
## with the rest of the box buried harmlessly inside the floor slab.
##
## SIGN CONVENTION, verified empirically rather than reasoned about (the
## previous attempt at this area got it backwards): rotating a box by a
## POSITIVE rotation.x raises its -Z end and lowers its +Z end. A deck that
## DESCENDS as the player runs toward -Z therefore needs a NEGATIVE rotation.x,
## which is what atan2(rise, run) below produces when rise is negative.
func _ramp(ramp_name: String, width: float, thickness: float,
		z_near: float, y_near: float, z_far: float, y_far: float,
		colour: Color) -> StaticBody3D:
	var run := z_near - z_far       # > 0: the deck extends toward -Z
	var rise := y_far - y_near      # > 0: it climbs toward -Z
	var length := sqrt(run * run + rise * rise)
	var angle := atan2(rise, run)
	# World-space up-normal of the rotated top face. Sliding the box down along
	# it by half the thickness moves the TOP face onto the requested points.
	var normal := Vector3(0.0, cos(angle), sin(angle))
	var top_mid := Vector3(0.0, (y_near + y_far) * 0.5, (z_near + z_far) * 0.5)
	var body := _box(ramp_name, Vector3(width, thickness, length),
		top_mid - normal * thickness * 0.5, colour)
	body.rotation.x = angle
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

	# --- Slide course -------------------------------------------------------
	#
	# One continuous route, run from +Z toward -Z, entirely inside the 60x60
	# Floor slab (z = -30..30) so every flat section IS the arena floor rather
	# than a deck raised above it. Local z here equals world z; the area's only
	# offset is x = 18.
	#
	#   z  +26 .. +16   approach   bare arena floor, 10 m to reach sprint speed
	#   z  +16 ..  +7   UpRamp     walkable 18.4 deg climb, 0 -> 3 m
	#   z   +7 ..  +3   Platform   4 m of flat deck at y = 3 to commit from
	#   z   +3 ..  -7   DownRamp   16.7 deg descent, 3 -> 0 m: the only slope
	#                              in the arena a downhill slide can be felt on
	#   z   -7 ..  -9   run-in     bare arena floor, flat, no lip
	#   z   -9 .. -16   Tunnel     7 m of 1.3 m clearance over the arena floor
	#   z  -16 .. -30   exit       bare arena floor, 14 m to read off the
	#                              speed the slide delivered
	#
	# The tunnel length is sized so slide MOMENTUM clears it with room to
	# spare, not so the crawl has to rescue every attempt: a slide entered on
	# the platform at sprint speed reaches the far mouth still doing about
	# 6.1 m/s, well over slide_crawl_speed. SlideState's crawl exists for the
	# player who commits too late or too slow, and this must not become the
	# normal way through — the traversability test asserts the crawl never
	# latches during the run, so shortening this is a change with a tripwire
	# on it.
	#
	# The ascent is a walkable slope, not a step: it has NO vertical rise at
	# all, so it cannot become unclimbable if jump_velocity or gravity are
	# tuned. The tunnel deck is the arena floor itself — there is deliberately
	# no TunnelFloor box, because any such box would either sit above the floor
	# (a lip the slide has to climb) or z-fight with it.
	const COURSE_WIDTH := 6.0
	const DECK_Y := 0.0            # top of the arena Floor slab
	const PLATFORM_Y := 3.0
	const TUNNEL_NEAR_Z := -9.0
	const TUNNEL_FAR_Z := -16.0
	const TUNNEL_CLEARANCE := 1.3  # > slide_capsule_height 0.9, < standing 1.8

	_attach(slide_area, _ramp("UpRamp", COURSE_WIDTH, 1.0,
		16.0, DECK_Y, 7.0, PLATFORM_Y, slide_colour))
	_attach(slide_area, _box("Platform", Vector3(COURSE_WIDTH, PLATFORM_Y, 4.0),
		Vector3(0.0, PLATFORM_Y * 0.5, 5.0), slide_colour))
	_attach(slide_area, _ramp("DownRamp", COURSE_WIDTH, 1.0,
		3.0, PLATFORM_Y, -7.0, DECK_Y, slide_colour))

	# Tunnel: walls stand on the floor, the roof spans between them with its
	# underside at DECK_Y + TUNNEL_CLEARANCE. Only a slide fits.
	var tunnel_length: float = TUNNEL_NEAR_Z - TUNNEL_FAR_Z
	var tunnel_mid: float = (TUNNEL_NEAR_Z + TUNNEL_FAR_Z) * 0.5
	var wall_height := TUNNEL_CLEARANCE + 0.7
	for side in [-1.0, 1.0]:
		_attach(slide_area, _box("TunnelWall%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.0, wall_height, tunnel_length),
			Vector3(side * (COURSE_WIDTH * 0.5 + 0.5), wall_height * 0.5, tunnel_mid),
			tunnel_colour))
	_attach(slide_area, _box("TunnelRoof",
		Vector3(COURSE_WIDTH + 2.0, wall_height - TUNNEL_CLEARANCE, tunnel_length),
		Vector3(0.0, (TUNNEL_CLEARANCE + wall_height) * 0.5, tunnel_mid), tunnel_colour))

	# Kerbs marking the two flat stretches that are bare arena floor, so the
	# approach and the exit runway read as part of the course rather than as
	# empty ground. Low and set outside the running lane on purpose — they mark
	# the route, they are not obstacles on it.
	# Each entry is [name, near z, far z]; the approach runs from the foot of
	# the climb back to the floor's edge, the exit from the far tunnel mouth to
	# the other edge.
	for spec in [["Approach", 26.0, 16.0], ["Exit", TUNNEL_FAR_Z, -30.0]]:
		var kerb_length: float = spec[1] - spec[2]
		var kerb_mid: float = (spec[1] + spec[2]) * 0.5
		for side in [-1.0, 1.0]:
			_attach(slide_area, _box("%sKerb%s" % [spec[0], "L" if side < 0.0 else "R"],
				Vector3(0.3, 0.2, kerb_length),
				Vector3(side * (COURSE_WIDTH * 0.5 + 0.35), 0.1, kerb_mid), slide_colour))

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

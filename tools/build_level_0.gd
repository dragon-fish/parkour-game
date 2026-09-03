extends SceneTree

# Generates scenes/levels/level_0/level_0.tscn: the tutorial.
#
# NO DEBUG SCAFFOLDING. RoamingProps and VoidProbe belong to
# scenes/debug_levels/void_plain.tscn, which exists so a wrap can be judged by
# hand -- scattered furniture in every direction is the OPPOSITE of what this
# level wants, which is one thing growing in front of the player at a time.
#
# NODE ORDER IS A CONTRACT. Siblings run _ready() in tree order, and both
# TutorialDirector and LevelZero reach into the Player during theirs, so both
# must come AFTER it. TutorialIntro must come after it for a second reason: it
# freezes the camera rig from its own _physics_process, and that tick has to
# land after the Player's, on a rig update_effects() has already placed once.
# LevelZero comes last of all: it connects to the director's own signal and to
# the intro's.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_level_0.gd

const OUTPUT := "res://scenes/levels/level_0/level_0.tscn"
const LESSON_DIR := "res://scenes/levels/level_0"

## How far the player runs before the plain repeats him back. Tuning value; the
## only thing that depends on it is materials/acrylic_void.tres's phase_wrap,
## which must stay equal to PERIOD / its own dot spacing or every dot in sight
## changes its blink on a crossing.
const PERIOD := 100.0

## How far the camera draws. Free of the period: nothing out there is a copy of
## anything, so a long view exposes nothing.
const VIEW_DISTANCE := 240.0

## Wide enough that the body is always inside the centre period, so this only
## has to cover sight plus one period.
const FLOOR_SPAN := (VIEW_DISTANCE + PERIOD) * 2.0
const FLOOR_THICKNESS := 2.0

const PALE := Color(0.93, 0.96, 0.98)
const COOL := Color(0.78, 0.86, 0.93)

var _root: Node3D

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Level0"
	_root = root
	root.set_script(load("res://scripts/level/arena.gd"))
	root.set("config", load("res://presets/default.tres"))
	root.set("load_calibration_course", false)
	# SHE DOES NOT DIE HERE. Every route to a death becomes a white curtain and
	# a respawn at the highest checkpoint reached.
	root.set("rescue_below_hp", 30.0)
	root.set("view_distance", VIEW_DISTANCE)
	# The tutorial hands control over from behind the body. The preference, not
	# a pin: V still works, and nothing is written to disk.
	root.set("start_in_third_person", true)
	# SHE IS A SILHOUETTE IN THE VOID, the same red she is on the front door.
	root.set("paint_body_as_silhouette", true)

	var fog := FogConfig.new()
	fog.resource_local_to_scene = true
	# FOG IS THE SEAM'S COVER, not weather. The end distance stays under the
	# far plane so geometry is already opaque by the time it reaches the cut --
	# otherwise things wink out at a fixed radius.
	fog.enabled = true
	fog.fade_begin_distance = VIEW_DISTANCE * 0.4
	fog.fade_end_distance = VIEW_DISTANCE * 0.95
	fog.max_opacity = 1.0
	# The horizon's own value, so anything the fog swallows arrives at exactly
	# the colour behind it.
	fog.tint = PALE
	root.set("fog", fog)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	# NO SHADOWS. She should look like she is standing on nothing; a cast
	# shadow is a statement that the void has a ground.
	sun.shadow_enabled = false
	root.add_child(sun)

	root.add_child(_environment())

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.set_script(load("res://scripts/level/spawn_point.gd"))
	spawn.position = Vector3(0.0, 0.95, 25.0)
	root.add_child(spawn)

	var plain := _plain()
	root.add_child(plain)

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

	var director := Node.new()
	director.name = "TutorialDirector"
	director.set_script(load("res://scripts/level/tutorial_director.gd"))
	root.add_child(director)
	director.set("player", player)
	director.set("wrap", wrap)
	director.set("lessons", _lessons())

	# THE ONLY THREE LINES THIS LEVEL SAYS ABOUT CONTROLS. Without it the
	# tutorial opens on an empty plain with no text and no geometry -- lesson 0
	# has no scene on purpose -- and the player is left to guess.
	var opening := Node.new()
	opening.name = "TutorialOpening"
	opening.set_script(load("res://scripts/level/tutorial_opening.gd"))
	root.add_child(opening)
	opening.set("subtitle", player.get_node("CameraRig/Subtitle"))

	# THE LEVEL OPENS ON A HELD SHOT, not on a curtain. The crouched profile,
	# the stand-up, the camera swinging round behind her and control arriving
	# all happen inside this scene, so there is nothing between the picture and
	# the game -- see scripts/level/tutorial_intro.gd.
	var intro := Node.new()
	intro.name = "TutorialIntro"
	intro.set_script(load("res://scripts/level/tutorial_intro.gd"))
	root.add_child(intro)
	intro.set("player", player)

	var tower: Node = load("%s/tower.tscn" % LESSON_DIR).instantiate()
	tower.name = "Tower"
	root.add_child(tower)

	# LAST. It connects to the director's `finished` and reaches into the
	# tower's own children.
	var chain := Node.new()
	chain.name = "LevelZero"
	chain.set_script(load("res://scripts/level/level_zero.gd"))
	root.add_child(chain)
	chain.set("player", player)
	chain.set("director", director)
	chain.set("wrap", wrap)
	chain.set("tower", tower)
	chain.set("tower_checkpoint", tower.get_node("Checkpoint00"))
	chain.set("orb", tower.get_node("Orb"))
	chain.set("plain", plain)
	chain.set("plain_mesh", plain.get_node("Mesh"))
	chain.set("plain_collision", plain.get_node("Collision"))
	# THE SAME MARKER ARENA RESPAWNS AT. LevelZero moves it to the foot of the
	# tower when the plain goes, so a restart lands on the climb instead of on
	# a plain that is no longer there.
	chain.set("spawn_point", spawn)
	chain.set("opening", opening)
	chain.set("intro", intro)
	chain.set("void_colour", PALE)

	_claim(root)

	DirAccess.make_dir_recursive_absolute(LESSON_DIR)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	assert(pack_error == OK, "pack failed: %d" % pack_error)
	var save_error := ResourceSaver.save(packed, OUTPUT)
	assert(save_error == OK, "save failed: %d" % save_error)
	print("wrote ", OUTPUT)
	quit(0)

## The teaching order. One row per lesson; see TutorialDirector.lessons for the
## schema.
##
## ROW 0 HAS NO SCENE ON PURPOSE. The first stretch of this level is an empty
## plain and its whole job is that the player discovers he cannot fall off it
## and cannot reach the end of it. The first jump anywhere passes it.
func _lessons() -> Array[Dictionary]:
	return [
		{teaches = Move.JUMP, scene = null},
		{teaches = Move.SPEED_VAULT, scene = _lesson("lesson_vault")},
		{teaches = Move.SLIDE, scene = _lesson("lesson_slide")},
		{teaches = Move.WALL_RUN, scene = _lesson("lesson_wall_run")},
		{teaches = Move.GRAB, scene = _lesson("lesson_grab")},
	]

## A MISTYPED PATH MUST NOT LOOK LIKE ROW 0. load() returns null on a path
## that is not there, and null is also what the opening row carries on
## purpose, so a typo would bake a level that silently teaches one lesson
## fewer. Nothing downstream can tell the two apart -- this is the only place
## that can.
func _lesson(stem: String) -> PackedScene:
	var path := "%s/%s.tscn" % [LESSON_DIR, stem]
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("build_level_0: no lesson scene at %s" % path)
	return scene

func _environment() -> WorldEnvironment:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	# A SKY THAT IS ONE FLAT COLOUR, not the absence of one. The floor is
	# nearly a mirror and a metal surface has no colour of its own -- with no
	# radiance map every direction that misses geometry reflects black and the
	# white floor comes out charcoal. And sky and ground meeting at the same
	# value is what deletes the horizon.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_horizon_color = PALE
	sky_material.ground_horizon_color = PALE
	sky_material.sky_top_color = COOL
	sky_material.ground_bottom_color = COOL
	# The sun disc is off: a bright spot in the sky is the one landmark this
	# level must not have.
	sky_material.sun_angle_max = 0.0
	sky_material.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.223529, 0.466667, 0.741176)
	environment.ssr_enabled = true
	environment.ssr_max_steps = 32
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_env.environment = environment
	return world_env

## The plain. Named `Plain` rather than `Floor` because LevelZero takes it away
## and the node it drives should say which one it is.
func _plain() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Plain"
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
	# THE SHARED ACRYLIC PRESET. Its phase_wrap is already PERIOD / spacing,
	# which is what keeps every dot's blink from being replaced on a crossing.
	# LevelZero duplicates this material before it touches it.
	mesh_instance.material_override = load("res://materials/acrylic_void.tres")
	body.add_child(mesh_instance)
	return body

func _claim(node: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = _root
		_claim(child)

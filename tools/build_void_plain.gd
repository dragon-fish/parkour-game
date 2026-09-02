extends SceneTree

# Generates scenes/debug_levels/void_plain.tscn: a bare torus plain for judging
# the wrap by hand. Built in code for the same reason the arena is -- a
# hand-written .tscn in this project has cost sessions (see
# .claude/skills/authoring-godot-scene-files).
#
# SCENERY FOLLOWS THE PLAYER, IT IS NOT TILED. An earlier version laid copies
# of a fixed layout one period apart in both axes, so both sides of a seam
# would match. It works, and it is the wrong shape: a wrap exists so the player
# can run forever, NOT so he can see infinite copies of a world. Tiling also
# drags in constraints that belong to the scaffolding rather than to the level
# -- sight confined inside the tiled area, the period forced to divide the
# ground pattern's spacing, the ring count re-derived on every change of view
# distance. RoamingProps recycles instead, which is also what the real tutorial
# does with its obstacles.
#
# A correct wrap is invisible, which is why this scene carries a readout
# (VoidProbe) and two coloured seam lines: without them there is no way to tell
# a crossing from an ordinary stride.
#
# Run with:
#   .engine/Godot_v4.7.1-stable_macos.universal.app/Contents/MacOS/Godot \
#       --headless --path . --script res://tools/build_void_plain.gd

const OUTPUT := "res://scenes/debug_levels/void_plain.tscn"

## The wrap period: how far the player runs before the plain repeats him back.
## NOTHING ELSE DEPENDS ON IT ANY MORE -- with scenery that follows, sight and
## the floor are free of it. It only sets how often a crossing happens.
const PERIOD := 100.0

## How far the camera draws. Free to be whatever looks right: there are no
## copies out there to give the wrap away.
const VIEW_DISTANCE := 240.0

## Floor wide enough that the player never reaches its edge -- he is always
## inside the centre period, so this only has to cover sight plus that.
const FLOOR_SPAN := (VIEW_DISTANCE + PERIOD) * 2.0

const FLOOR_THICKNESS := 2.0
## The seam lines at +/- PERIOD/2, in their own colour.
const SEAM_WIDTH := 0.5
# THE PALETTE IS HIGH-KEY BUT NOT WHITE, and the difference is the whole
# reason it can be looked at. A screen that is one flat bright value has
# nowhere for the eye to rest; the reference this is built from carries almost
# the same brightness everywhere but splits it by HUE -- lit faces near white,
# shadowed faces distinctly blue. Contrast by colour, not by darkness.
#
# The sky is a gradient for the same reason: a dead-flat sky is what made the
# first attempt hurt to look at.

## Bright end: lit surfaces and the horizon, where sky and ground meet and must
## be indistinguishable.
const PALE := Color(0.93, 0.96, 0.98)
## Cool end: the top of the sky and the ground under it. Blue rather than grey
## -- this is the shade Arena.COLD_AMBIENT_TINT already tints shadows with.
const COOL := Color(0.78, 0.86, 0.93)

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
	# The hard edge of sight, just past where the fog finishes. Fog hides the
	# cut; the cut is what stops a distant box from keeping its silhouette.
	# Free of the period now that scenery follows instead of tiling -- there is
	# nothing repeated out there for a long view to expose.
	root.set("view_distance", VIEW_DISTANCE)
	var fog := FogConfig.new()
	fog.resource_local_to_scene = true
	# FOG IS NOT ATMOSPHERE HERE, IT IS THE SEAM'S COVER. Without a limit on
	# sight the wrap gives itself away every time: the furniture is tiled over
	# a FINITE span, so shifting the body one period also shifts where that
	# span ends, and the outermost ring of boxes pops in or out. The finished
	# level solves this with the collapse radius; fog is the cheap equivalent.
	#
	# THE END DISTANCE MUST STAY UNDER HALF A PERIOD -- that is the spec's
	# `2R < P`. Push it past 50 here and the pop comes back.
	fog.enabled = true
	fog.fade_begin_distance = VIEW_DISTANCE * 0.4
	fog.fade_end_distance = VIEW_DISTANCE * 0.95
	fog.max_opacity = 1.0
	# Fog the same shade as the background, so a swallowed object does not
	# merely dim -- it stops existing as a shape.
	# The horizon's own value, so anything the fog swallows arrives at exactly
	# the colour behind it.
	fog.tint = PALE
	root.set("fog", fog)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	# NO SHADOWS ANYWHERE. A shadow is a statement about a floor being a
	# surface, and this floor is not meant to read as one -- she should look
	# like she is standing on nothing, with the dots as the only clue that
	# space exists at all. The sun stays on so the body keeps its shading;
	# it is the cast shadows that would give the void a ground.
	sun.shadow_enabled = false
	_attach(root, sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var environment := Environment.new()
	# A SKY THAT IS ONE FLAT COLOUR, not the absence of a sky. Two things need
	# it and a plain background colour serves neither:
	#
	#   The floor is nearly a mirror (see materials/acrylic_void.tres), and a
	#   metal surface HAS no colour of its own -- it is made of what it
	#   reflects. With no sky there is no radiance map, so every direction that
	#   misses geometry reflects black and the white floor comes out charcoal.
	#
	#   The horizon has to disappear. Sky and ground being the same value is
	#   what deletes it; a sky with any gradient at all draws the line back in.
	#
	# The sun disc is switched off -- a bright spot in the sky would be the one
	# landmark this level must not have.
	var sky_material := ProceduralSkyMaterial.new()
	# THE HORIZON PAIR MUST MATCH. Sky and ground meeting at the same value is
	# what deletes the horizon; the gradient lives above and below it, never
	# across it.
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
	# THE BACKGROUND IS THE REFLECTION SOURCE. A metallic surface has no
	# diffuse of its own -- it is made entirely of what it reflects -- and with
	# no sky in this level there would be nothing but screen-space hits, so
	# every direction that misses geometry comes back black. Pointing it at the
	# background makes the floor mirror the same white the void is made of.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	world_env.environment = environment
	_attach(root, world_env)

	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	spawn.set_script(load("res://scripts/level/spawn_point.gd"))
	spawn.position = Vector3(0.0, 0.95, 0.0)
	_attach(root, spawn)

	_attach(root, _floor())
	_attach(root, _seams())

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

	var props := Node3D.new()
	props.name = "RoamingProps"
	props.set_script(load("res://scripts/debug/roaming_props.gd"))
	root.add_child(props)
	props.set("player", player)
	props.set("wrap", wrap)

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
	mesh_instance.mesh = mesh
	# THE SHARED ACRYLIC SHADER, not a fresh material. materials/acrylic_void.tres
	# is its preset for this level: the menu's own backdrop shade, a glossier
	# sheet, and the dots BREATHING -- each cell on its own phase, the way
	# scripts/ui/dot_grid.gdshader does it for the menu floor. The level should
	# look like the screen it is entered from.
	mesh_instance.material_override = load("res://materials/acrylic_void.tres")
	_attach(body, mesh_instance)
	return body

## The four seams, in their own colour and wider than a grid line. Crossing one
## is the event everything else in this scene exists to make readable.
func _seams() -> Node3D:
	var seams := Node3D.new()
	seams.name = "Seams"
	var half: float = PERIOD * 0.5
	var span: float = FLOOR_SPAN
	var colour := Color("#e90100")
	for sign_index in 2:
		var at: float = half if sign_index == 0 else -half
		_attach(seams, _stripe("SeamX%d" % sign_index,
			Vector3(SEAM_WIDTH, 0.02, span), Vector3(at, 0.012, 0.0), colour))
		_attach(seams, _stripe("SeamZ%d" % sign_index,
			Vector3(span, 0.02, SEAM_WIDTH), Vector3(0.0, 0.012, at), colour))
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

class_name ArenaBuilder
extends RefCounted

# Builds the graybox arena's node tree in memory. This is the ONE place the
# arena's layout is defined; nothing else may duplicate it.
#
# tools/build_main_scene.gd (a thin SceneTree script, since only a MainLoop
# subclass can run via --script) calls build() and packs/saves the result to
# scenes/main.tscn. tests/test_arena.gd's
# test_regenerating_the_scene_matches_what_is_committed also calls build()
# directly, on a tree that is never added to the SceneTree, and compares it
# structurally against what ResourceLoader loads back from the committed
# .tscn -- both paths run this exact code, so the two cannot silently drift
# apart the way a hand-edited main.tscn once did.

var _root: Node3D

## Colour -> StandardMaterial3D, so boxes sharing a colour (all 6 gaps, all 6
## steps, all 3 drop towers) share one material resource instead of each
## getting a byte-identical copy. Shapes and meshes are deliberately NOT
## cached here: every box's size genuinely differs, so there is nothing to
## share for those.
var _materials: Dictionary = {}

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

## Builds and returns the full arena tree, unparented and not yet added to
## any SceneTree. Caller owns it: pack it (tools/build_main_scene.gd) or
## inspect it directly and free() it (tests/test_arena.gd).
func build() -> Node3D:
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
	# Distinct again from every colour above: warm amber for something you
	# CAN vault, red for something the area proves you cannot do anything
	# with (too tall to vault, too tall to grab), cool violet for something
	# you can grab and mantle.
	var vault_colour := Color(0.62, 0.46, 0.30)
	var blocked_colour := Color(0.55, 0.30, 0.30)
	var ledge_colour := Color(0.45, 0.42, 0.62)

	# 60x100, not 60x60: P3's WallArea (built below, north of spawn at +Z)
	# needed more +Z room than the original 60x60 slab left free, and the
	# fix is to enlarge the floor rather than let anything hang over its
	# edge (see the WallArea comment for the exact budget). The extra 40 m
	# is added entirely on the +Z side -- x is untouched and the -Z edge
	# stays at -30 exactly, because JumpArea's Gap5/Gap6 and Step5/Step6
	# deliberately extend past that edge into open air (the "missed jump
	# falls forever" case test_falling_out_of_the_level_respawns_the_player
	# covers) and moving that edge would silently turn them into solid
	# ground.
	_attach(_root, _box("Floor", Vector3(60.0, 1.0, 100.0), Vector3(0.0, -0.5, 20.0), ground))

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

	# --- Vault and ledge course ----------------------------------------------
	#
	# Mirrors SlideArea across the spawn point (x = -18 instead of +18), so it
	# can never overlap either existing area regardless of how long either
	# course runs: JumpArea's boxes span roughly world x -10.5..11, SlideArea's
	# roughly x 14..22, and everything below sits at world x -23..-16 — clear
	# of both with several metres to spare on every side, and still well
	# inside the 60x60 Floor slab (x, z each ±30).
	#
	# Every obstacle here rests directly on the floor (its box is centred at
	# y = height * 0.5, exactly like JumpArea's Step boxes), so there is no
	# elevation change to get wrong: the whole course lives on one flat plane,
	# reachable on foot from spawn like JumpArea's, which rules out the
	# vertical-disconnection mistake this task's brief warns this arena has
	# made before.
	#
	# Heights are computed from a fresh MovementConfig rather than written as
	# literals — Arena itself falls back to `MovementConfig.new()` whenever
	# scenes/main.tscn does not wire an explicit config (see arena.gd's
	# _ready()), which this generator never does, so this mirrors the same
	# default the running game actually uses. Deriving from config, not
	# copying its current numbers by hand, is what keeps this course meaningful
	# after a future tuning pass changes vault_max_height or the ledge bounds.
	#
	# This area's own x/z stay within the ORIGINAL ±30 footprint on both
	# axes (only the +Z side was later extended, for WallArea below), so
	# every distance claim in this comment block still holds unchanged.
	var vault_config := MovementConfig.new()
	var vault_area := Node3D.new()
	vault_area.name = "VaultArea"
	vault_area.position = Vector3(-18.0, 0.0, 0.0)
	_attach(_root, vault_area)

	# Three vaultable obstacles, increasing toward vault_max_height, run
	# from +Z to -Z like every other course in this arena. Depth 2 m and a
	# 7-8 m stride between them (5-6 m of clear floor after each obstacle's
	# far face) is comfortably enough room to regain vault_min_speed before
	# the next one, since vault_speed_keep already keeps most of the
	# approach speed through the vault itself.
	var vault_low_height: float = vault_config.vault_max_height * 0.4
	var vault_mid_height: float = vault_config.vault_max_height * 0.7
	# Just inside the limit, not exactly on it: MIN_HEIGHT_EPSILON and normal
	# float noise sit near zero, not near vault_max_height, so this margin is
	# about keeping VaultHigh readable as "the tallest thing you can still
	# vault" rather than guarding against any known edge case at the boundary.
	var vault_high_height: float = vault_config.vault_max_height - 0.05

	_attach(vault_area, _box("VaultLow", Vector3(4.0, vault_low_height, 2.0),
		Vector3(0.0, vault_low_height * 0.5, 20.0), vault_colour))
	_attach(vault_area, _box("VaultMid", Vector3(4.0, vault_mid_height, 2.0),
		Vector3(0.0, vault_mid_height * 0.5, 13.0), vault_colour))
	_attach(vault_area, _box("VaultHigh", Vector3(4.0, vault_high_height, 2.0),
		Vector3(0.0, vault_high_height * 0.5, 6.0), vault_colour))

	# A wall clearly over the vault limit, proving "too tall to vault" is
	# real. It sits ON the running lane (local x = 0, like every Vault/Ledge
	# box above and below it) so a player running straight down the course
	# hits it rather than needing to already know to avoid it — but it is
	# only 6 m wide and offset to x = -2, so it covers local x -5..1 and
	# leaves x 1.. open floor (nothing else in this area extends past x = 2)
	# for the player to sidestep around and continue toward the ledges.
	var vault_wall_height: float = vault_config.vault_max_height + 2.0
	_attach(vault_area, _box("WallTooTall", Vector3(6.0, vault_wall_height, 2.0),
		Vector3(-2.0, vault_wall_height * 0.5, -2.0), blocked_colour))

	# Two grabbable ledges bracketing the reachable range: one just above
	# ledge_min_height (below this, Probes.ledge_query() would never even
	# see it as tall enough to register), one just under ledge_max_height.
	var ledge_low_height: float = vault_config.ledge_min_height + 0.1
	var ledge_mid_height: float = vault_config.ledge_max_height - 0.1
	_attach(vault_area, _box("LedgeLow", Vector3(4.0, ledge_low_height, 2.0),
		Vector3(0.0, ledge_low_height * 0.5, -10.0), ledge_colour))
	_attach(vault_area, _box("LedgeMid", Vector3(4.0, ledge_mid_height, 2.0),
		Vector3(0.0, ledge_mid_height * 0.5, -18.0), ledge_colour))

	# And a platform clearly beyond ledge_max_height, so "too high to grab"
	# has something to point at too.
	var ledge_too_high_height: float = vault_config.ledge_max_height + 1.5
	_attach(vault_area, _box("LedgeTooHigh", Vector3(4.0, ledge_too_high_height, 2.0),
		Vector3(0.0, ledge_too_high_height * 0.5, -26.0), blocked_colour))

	# --- Wall run course -----------------------------------------------------
	#
	# North of spawn (+Z), not east/west like Slide/Vault: JumpArea, SlideArea
	# and VaultArea between them already occupy every x column at z <= ~26
	# (JumpArea's own boxes never reach z > 0 at all -- see its gap_z/Step
	# loops above), so the +Z half of the floor past that is untouched. This
	# area's own boxes stay inside x [-1.7, 1.7] and z [17.5, 55] -- nowhere
	# near SlideArea's x [14, 22] or VaultArea's x [-23, -16] -- so there is
	# no overlap to compute here beyond confirming those ranges don't touch,
	# which they don't by more than 12 m on every side.
	#
	# WallArea.position is deliberately left at the origin (unlike every
	# other area here, which offsets to keep ITS OWN local numbers small):
	# with no offset, a child's `position` (local) and world coordinates are
	# the same numbers, which is what let the non-overlap claim above be
	# checked directly against Slide/Vault/Jump's own world-space comments
	# without a conversion step.
	#
	# Course, run from +Z toward -Z like every other area here:
	#
	#   z ~65 .. 55   approach   bare arena floor -- ground_accel (60 m/s^2)
	#                            reaches wall_min_speed (5 m/s) in well under
	#                            a metre, so this is about pacing, not need
	#   z  55 .. 38.5 LongWall   one continuous wall, length derived below
	#   z 38.5 .. 35.5 gap       bare floor: a beat to land and reset after
	#                            LongWall before the zig-zag starts
	#   z 35.5 .. 17.5 zig-zag   four walls alternating sides, chained by
	#                            wall jumps -- see the note above the loop
	#
	# The floor was enlarged (see the Floor comment above) specifically to
	# fit this without anything hanging over its edge: the course's own
	# northern approach ends at z=65, 5 m short of the new edge at z=70.
	var wall_config := MovementConfig.new()
	var wall_area := Node3D.new()
	wall_area.name = "WallArea"
	_attach(_root, wall_area)

	# Colour distinct from every area above: a cool steel blue that has not
	# been used for ground (blue-grey), gap (blue-cyan), slide (green), vault
	# (amber), or ledge (violet) — chosen furthest in hue from slide_colour
	# and gap_colour, the two nearest neighbours in this palette.
	var wall_colour := Color(0.32, 0.52, 0.68)

	# How far a wall's near face may sit from the running lane's centreline
	# (local x = 0) and still be within wall_reach (0.75 m default) of a
	# player running straight down it — proven in practice, not just in
	# theory: this is the exact offset tests/test_wall_run.gd's own
	# `_wall_world()` fixture uses (wall centred at x=0.95, this thickness),
	# and every wall-attach test in that file passes against it. Kept well
	# under wall_reach itself (0.75) rather than pushed right up against it,
	# so a player drifting a few centimetres off the lane's exact centre
	# during a real run does not fall outside reach.
	const WALL_NEAR_FACE := 0.45
	const WALL_THICKNESS := 1.0
	# Tall enough that a wall run's modest vertical drift (gravity is only
	# wall_gravity_scale of normal while attached) and a wall jump's vertical
	# impulse (wall_jump_up, decaying under full gravity the instant the
	# player leaves the wall) cannot carry the player's attach point above
	# the wall's top edge mid-run -- matches the height
	# tests/test_wall_run.gd's own fixture already runs every wall-run test
	# against without that ever happening.
	const WALL_HEIGHT := 8.0

	# Long enough to exhaust a FULL wall_max_duration run, not merely the
	# brief's minimum bar (half of wall_max_speed * wall_max_duration, which
	# only proves the duration cap is reachable in principle) -- using the
	# whole product means a run that holds along this wall the entire time
	# actually hits the timer, not just clears the test's threshold.
	var long_wall_length: float = wall_config.wall_max_speed * wall_config.wall_max_duration
	const LONG_WALL_NEAR_Z := 55.0
	var long_wall_far_z: float = LONG_WALL_NEAR_Z - long_wall_length
	_attach(wall_area, _box("LongWall",
		Vector3(WALL_THICKNESS, WALL_HEIGHT, long_wall_length),
		Vector3(WALL_NEAR_FACE + WALL_THICKNESS * 0.5, WALL_HEIGHT * 0.5,
			(LONG_WALL_NEAR_Z + long_wall_far_z) * 0.5),
		wall_colour))

	# --- Zig-zag section ------------------------------------------------------
	#
	# The reason this area exists: adjacent walls face OPPOSITE directions
	# (one on each side of the running lane), so player.can_attach_wall()'s
	# same-wall cooldown -- which blocks re-attaching a wall whose normal is
	# too close to one just left, precisely to stop climbing one face forever
	# -- never triggers between them (opposite normals dot to -1, nowhere near
	# wall_same_normal_dot's 0.85 threshold). A wall jump off one throws the
	# player toward the other, which is what makes relaying UP between them
	# possible at all; two walls facing the SAME way here would teach the
	# opposite lesson, or nothing.
	#
	# Half-width kept under wall_reach exactly like LongWall's WALL_NEAR_FACE,
	# but a little looser (0.7 vs 0.45): LongWall only ever needs to be
	# reached from one fixed side, but this corridor needs BOTH faces inside
	# reach from the same centred running line, while still leaving the 0.4 m
	# player capsule (see tools/build_player_scene.gd) 0.3 m of clearance on
	# each side to run it without scraping either wall.
	const ZIG_HALF_WIDTH := 0.7
	const ZIG_X := ZIG_HALF_WIDTH + WALL_THICKNESS * 0.5
	const ZIG_LENGTH := 6.0
	# Less than ZIG_LENGTH on purpose: consecutive walls overlap by 2 m in Z,
	# so the transition point (where a jump off one wall must land within
	# wall_reach of the next) is comfortably inside both walls' spans rather
	# than balanced on their shared edge.
	const ZIG_STEP := 4.0
	const ZIG_START_Z := 35.5

	# name, side sign (-1 = left/-x, +1 = right/+x), position in the sequence
	var zig_walls := [
		["ZigLeft1", -1.0, 0],
		["ZigRight1", 1.0, 1],
		["ZigLeft2", -1.0, 2],
		["ZigRight2", 1.0, 3],
	]
	for entry in zig_walls:
		var wall_name: String = entry[0]
		var side: float = entry[1]
		var index: int = entry[2]
		var near_z: float = ZIG_START_Z - ZIG_STEP * index
		var far_z: float = near_z - ZIG_LENGTH
		_attach(wall_area, _box(wall_name, Vector3(WALL_THICKNESS, WALL_HEIGHT, ZIG_LENGTH),
			Vector3(side * ZIG_X, WALL_HEIGHT * 0.5, (near_z + far_z) * 0.5), wall_colour))

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

	return _root

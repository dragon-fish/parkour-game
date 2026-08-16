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

## Constant-acceleration kinematics: sqrt(max(v0^2 + 2*accel*distance, 0)).
## Used to derive how much of SlideState's own speed model (friction, slope
## accel, the entry boost -- see slide_state.gd) a stretch of course geometry
## actually costs or grants, so a course length can be SIZED from that instead
## of hand-tuned by trial and error. Clamped at 0 under the sqrt so a segment
## long enough to fully arrest the given accel does not attempt a negative
## square root.
func _speed_after(v0: float, accel: float, distance: float) -> float:
	return sqrt(maxf(v0 * v0 + 2.0 * accel * distance, 0.0))

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

## Recursively collects every StaticBody3D with a box-shaped "Collision" child
## under node -- the same convention _box() always builds. Duplicated rather
## than shared with tests/test_arena.gd's own identically-named helper: this
## runs at BUILD time, on a tree that may never be added to a SceneTree (see
## build()'s own header comment), so it cannot depend on anything under
## tests/.
func _collect_box_bodies(node: Node, out: Array) -> void:
	if node is StaticBody3D:
		var collision := node.get_node_or_null("Collision")
		if collision is CollisionShape3D and collision.shape is BoxShape3D:
			out.append(node)
	for child in node.get_children():
		_collect_box_bodies(child, out)

## Composes `node`'s transform up through its Node3D ancestors by hand.
##
## NOT the same as node.global_transform: that getter requires the node to
## actually be INSIDE a live SceneTree (Node.is_inside_tree()) and silently
## returns IDENTITY -- logging "Condition "!is_inside_tree()" is true" -- when
## it is not. build() constructs its ENTIRE tree off-tree (see its own header
## comment: callers pack it or inspect it directly, neither of which requires
## adding it to a SceneTree first), so every body._collect_box_bodies() below
## finds is in exactly that state at the point the Floor block calls this.
## Verified directly: computing the floor's bounds via global_transform first
## produced a nonsensical ~28x35 slab (every body's world-space box collapsed
## to its LOCAL box size centred on the origin, identity transform applied to
## each), rather than the true, much larger footprint -- this walk fixes that
## by using `transform` (always valid regardless of tree membership) at every
## step instead.
func _global_transform_offline(node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform

## World-space AABB of a box body, computed from its transform so a rotated
## box (SlideArea's UpRamp/DownRamp) is handled correctly, not just a
## translated one -- see _global_transform_offline()'s own comment for why
## this cannot simply read body.global_transform the way
## tests/test_arena.gd's identically-named helper does (that one runs AFTER
## the arena is loaded into a live tree, where global_transform is valid).
func _world_aabb(body: Node3D) -> AABB:
	var box: BoxShape3D = (body.get_node("Collision") as CollisionShape3D).shape
	var half := box.size * 0.5
	return _global_transform_offline(body) * AABB(-half, box.size)

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

	# Shared jump-arc quantities, derived from a fresh MovementConfig exactly
	# the way Arena._ready() falls back to one when scenes/main.tscn wires no
	# explicit config (see the VaultArea comment below, which already does
	# this for vault/ledge heights) -- so JumpArea's gap and step ladders keep
	# testing the REAL limits of whatever gravity/jump_velocity/ground_speed
	# are currently set to, instead of a snapshot from whenever this file was
	# last hand-edited. Both are closed-form projectile arithmetic on a flat
	# takeoff-to-landing arc:
	#   airtime   = 2 * jump_velocity / gravity          (up and back down)
	#   distance  = ground_speed * airtime                (run-up speed is the
	#               ground speed cap -- momentum carried into a jump, not
	#               something air control can add to; see air_accel's own
	#               comment in movement_config.gd)
	#   peak height = jump_velocity^2 / (2 * gravity)
	var config := MovementConfig.new()
	var jump_airtime: float = 2.0 * config.jump_velocity / maxf(config.gravity, 0.001)
	var max_jump_distance: float = config.ground_speed * jump_airtime
	var jump_peak_height: float = (config.jump_velocity * config.jump_velocity) \
		/ (2.0 * maxf(config.gravity, 0.001))

	# Floor is built LAST (see the bottom of this function), sized from the
	# union of every practice area's own bounds once they all exist, rather
	# than the other way round -- see that comment for why.

	var jump_area := Node3D.new()
	jump_area.name = "JumpArea"
	jump_area.position = Vector3(0.0, 0.0, -12.0)
	_attach(_root, jump_area)

	# Increasing gaps, as FRACTIONS of max_jump_distance rather than fixed
	# metres, so the ladder keeps bracketing the true limit -- some rungs
	# clearable, at least one not -- across any future retune of gravity,
	# jump_velocity or ground_speed, instead of quietly becoming either
	# trivial (every gap far under the limit) or impossible (every gap far
	# over it). 0.9 and 1.1 straddle 1.0 without landing exactly on it, which
	# would leave that one rung's reachability riding on float noise.
	const GAP_FRACTIONS := [0.5, 0.7, 0.9, 1.1, 1.35]
	const GAP_PLATFORM_LENGTH := 3.0
	var gap_z: Array[float] = [0.0]
	for fraction in GAP_FRACTIONS:
		var gap: float = max_jump_distance * fraction
		gap_z.append(gap_z[gap_z.size() - 1] - gap - GAP_PLATFORM_LENGTH)
	for i in gap_z.size():
		_attach(jump_area, _box("Gap%d" % (i + 1), Vector3(GAP_PLATFORM_LENGTH, 1.0, GAP_PLATFORM_LENGTH),
			Vector3(-9.0, 0.5, gap_z[i]), gap_colour))

	# Increasing heights, as FRACTIONS of jump_peak_height for the same reason
	# the gap ladder above uses fractions of max_jump_distance: a step sits
	# directly against the running lane (no horizontal gap to clear), so the
	# tallest one a jump can reach is bounded by how high a jump rises, full
	# stop -- there is no run-up distance to trade against it the way there is
	# for a gap. Six rungs, the middle pair straddling 1.0 without landing on
	# it exactly, mirroring the gap ladder's own margin choice above.
	const STEP_FRACTIONS := [0.4, 0.6, 0.8, 0.95, 1.15, 1.4]
	for i in STEP_FRACTIONS.size():
		var height: float = jump_peak_height * STEP_FRACTIONS[i]
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
	# One continuous route, run from +Z toward -Z, entirely inside the arena
	# Floor slab (sized to contain every practice area, see the Floor comment
	# further down) so every flat section IS the arena floor rather than a
	# deck raised above it. Local z here equals world z; the area's only
	# offset is x = 18.
	#
	#   z  +26 .. +16   approach   bare arena floor, 10 m to reach ground_speed
	#   z  +16 ..  +7   UpRamp     walkable 18.4 deg climb, 0 -> 3 m
	#   z   +7 ..  +3   Platform   4 m of flat deck at y = 3 to commit from
	#   z   +3 ..  -7   DownRamp   16.7 deg descent, 3 -> 0 m: the only slope
	#                              in the arena a downhill slide can be felt on
	#   z   -7 ..  -9   run-in     bare arena floor, flat, no lip
	#   z   -9 .. TUNNEL_FAR_Z     Tunnel, length DERIVED below
	#   z  TUNNEL_FAR_Z .. -30     exit, bare arena floor
	#
	# The tunnel length is DERIVED, not hand-tuned, from SlideState's own speed
	# model (slide_state.gd) applied to this exact geometry via _speed_after():
	# the entry boost on the platform, friction over the platform's remaining
	# length, the DownRamp's net acceleration (slide_slope_accel * grade -
	# slide_friction; ME's downhill slides must resist decay, see
	# slide_slope_accel's own comment), then friction again over the flat
	# run-in. That gives the speed AT THE TUNNEL'S OWN MOUTH, from which the
	# longest tunnel that still clears with real headroom over slide_crawl_speed
	# follows from plain kinematics (v^2 = u^2 - 2*a*d, solved for d). This is
	# what keeps "the tunnel is clearable on slide momentum alone" true across
	# a future retune of ground_speed, slide_friction or the ramp geometry,
	# instead of silently going stale the way the fixed 7 m tunnel did when
	# ground_speed dropped from 9.0 to 7.2 (see the numbers-only retune's own
	# report on this exact test failing as a result).
	const COURSE_WIDTH := 6.0
	const DECK_Y := 0.0            # top of the arena Floor slab
	const PLATFORM_Y := 3.0
	const PLATFORM_NEAR_Z := 7.0   # where UpRamp hands off to the flat deck
	const PLATFORM_FAR_Z := 3.0    # where DownRamp begins
	# "1 m onto the platform" -- matches test_the_slide_course_can_be_run_end_
	# to_end's own Phase 1 target (platform_aabb.end.z - 1.0), i.e. where the
	# test actually presses crouch and SlideState.enter() actually samples the
	# entry speed, not the platform's near edge.
	const PLATFORM_ENTRY_MARGIN := 1.0
	const DOWNRAMP_FAR_Z := -7.0    # where DownRamp meets the floor again
	const RUN_IN_LENGTH := 2.0      # flat floor between DownRamp and the tunnel
	const TUNNEL_NEAR_Z := DOWNRAMP_FAR_Z - RUN_IN_LENGTH
	const TUNNEL_CLEARANCE := 1.3  # > slide_capsule_height 0.9, < standing 1.8
	# How far above slide_crawl_speed the tunnel must still be moving at the
	# far mouth -- a MULTIPLE of it, not a bare number, so this margin scales
	# with any future retune of slide_crawl_speed itself rather than needing
	# its own separate adjustment.
	const TUNNEL_EXIT_SPEED_MARGIN := 1.5

	_attach(slide_area, _ramp("UpRamp", COURSE_WIDTH, 1.0,
		16.0, DECK_Y, PLATFORM_NEAR_Z, PLATFORM_Y, slide_colour))
	_attach(slide_area, _box("Platform", Vector3(COURSE_WIDTH, PLATFORM_Y, 4.0),
		Vector3(0.0, PLATFORM_Y * 0.5, 5.0), slide_colour))
	_attach(slide_area, _ramp("DownRamp", COURSE_WIDTH, 1.0,
		PLATFORM_FAR_Z, PLATFORM_Y, DOWNRAMP_FAR_Z, DECK_Y, slide_colour))

	# SlideState.enter()'s own boost formula (slide_state.gd), applied to the
	# ground speed cap: entering at or under slide_boost_entry_threshold grants
	# slide_boost, capped the same way. Mirrored here rather than imported so
	# this course sizing keeps tracking slide_state.gd's own math if it is
	# ever retuned independently.
	var slide_entry_speed: float = config.ground_speed
	if slide_entry_speed <= config.slide_boost_entry_threshold:
		slide_entry_speed = minf(slide_entry_speed + config.slide_boost, \
			config.slide_boost_entry_threshold + config.slide_boost)

	var down_ramp_length: float = PLATFORM_FAR_Z - DOWNRAMP_FAR_Z
	var down_ramp_rise: float = PLATFORM_Y - DECK_Y
	# sin(descent angle), i.e. -slope_dir.y the way slide_state.gd's own
	# _slope_direction() computes grade, without a redundant atan2 -> sin
	# round trip.
	var down_ramp_grade: float = down_ramp_rise / sqrt(down_ramp_rise * down_ramp_rise \
		+ down_ramp_length * down_ramp_length)

	var platform_remaining: float = (PLATFORM_NEAR_Z - PLATFORM_FAR_Z) - PLATFORM_ENTRY_MARGIN
	var speed_after_platform: float = _speed_after(slide_entry_speed, -config.slide_friction, \
		platform_remaining)
	var speed_after_ramp: float = _speed_after(speed_after_platform, \
		config.slide_slope_accel * down_ramp_grade - config.slide_friction, down_ramp_length)
	var speed_at_tunnel_mouth: float = _speed_after(speed_after_ramp, -config.slide_friction, \
		RUN_IN_LENGTH)

	var tunnel_exit_target_speed: float = config.slide_crawl_speed * TUNNEL_EXIT_SPEED_MARGIN
	var tunnel_length: float = maxf((speed_at_tunnel_mouth * speed_at_tunnel_mouth \
		- tunnel_exit_target_speed * tunnel_exit_target_speed) / (2.0 * config.slide_friction), 1.0)
	var tunnel_far_z: float = TUNNEL_NEAR_Z - tunnel_length

	# Tunnel: walls stand on the floor, the roof spans between them with its
	# underside at DECK_Y + TUNNEL_CLEARANCE. Only a slide fits.
	var tunnel_mid: float = (TUNNEL_NEAR_Z + tunnel_far_z) * 0.5
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
	for spec in [["Approach", 26.0, 16.0], ["Exit", tunnel_far_z, -30.0]]:
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
	# inside the arena Floor slab (sized to contain every practice area, see
	# the Floor comment further down).
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
	const WALL_TOO_TALL_Z := -2.0
	const WALL_TOO_TALL_DEPTH := 2.0
	_attach(vault_area, _box("WallTooTall", Vector3(6.0, vault_wall_height, WALL_TOO_TALL_DEPTH),
		Vector3(-2.0, vault_wall_height * 0.5, WALL_TOO_TALL_Z), blocked_colour))

	# Ledge spacing: a run-up-and-jump distance, the same closed-form arc
	# JumpArea's gap ladder uses (max_jump_distance = ground_speed * airtime;
	# see its own comment). There is no sprint key any more -- ground speed is
	# a single top speed GroundState always targets (see MovementConfig.
	# ground_speed's own comment) -- so ground_speed remains the real ground
	# speed cap here unconditionally (measured directly: the player is still
	# at exactly ground_speed when it leaves the ground for LedgeLow).
	# Grabbing a ledge, unlike clearing a gap, only works late in the arc (near
	# the bottom of the parabola, just before landing -- ledge_query()'s own
	# height gate is too narrow a window anywhere near the apex), so the
	# ledges sit a nearly-full jump's reach apart rather than somewhere in the
	# middle of it. LEDGE_RUNUP_MARGIN keeps the target comfortably inside
	# that theoretical ceiling: the run-up never starts from a dead stop with
	# the whole distance clear ahead of it (REALIGN_BUFFER below is the short
	# manoeuvre that eats into it), so a margin is what keeps this reliably
	# reachable rather than resting on float precision. Verified against an
	# actual driven run at this value, not just the arithmetic.
	const LEDGE_RUNUP_MARGIN := 0.95
	const REALIGN_BUFFER := 2.0
	const LEDGE_DEPTH := 2.0
	var ledge_gap: float = max_jump_distance * LEDGE_RUNUP_MARGIN

	var wall_too_tall_far_z: float = WALL_TOO_TALL_Z - WALL_TOO_TALL_DEPTH * 0.5

	# Two grabbable ledges bracketing the reachable range. LedgeMid sits just
	# under ledge_max_height, straightforwardly -- a tall target is grabbable
	# the instant the forward probe is in range, so nothing about the new arc
	# changes how close to the ceiling it can safely sit.
	#
	# LedgeLow is NOT simply "just above ledge_min_height" any more, and this
	# needed measuring, not just reasoning about: ledge_query()'s height gate
	# (probes.gd) only opens while `ledge_top - feet_height` sits inside
	# [ledge_min_height, ledge_max_height], and a low target's feet_height
	# crosses out of that window within a few HUNDREDTHS of a second of
	# leaving the ground (verified directly -- a target at ledge_min_height +
	# 0.1 was never once grabbed across a range of approach distances). The
	# test's own realign phase (test_the_vault_and_ledge_course_can_be_run_
	# end_to_end's Phase 3/4) always parks the run-up ~1.4 m short of the
	# ledge before jumping, regardless of where this generator places it, so
	# the height gate has to still be open at the moment ledge_reach first
	# lets the forward probe see the wall, not merely at some point during
	# the flight. GRAB_SAFETY_TIME is headroom past that moment for ordinary
	# tick-to-tick timing jitter, not a hand-picked height:
	#   time to close to ledge_reach = max(REALIGN_OFFSET - ledge_reach, 0) / ground_speed
	#   height risen by then + GRAB_SAFETY_TIME more   (closed-form projectile
	#     arithmetic again: h(t) = jump_velocity*t - 0.5*gravity*t^2)
	# added to ledge_min_height, so this still tracks any future retune of
	# gravity/jump_velocity/ground_speed/ledge_reach instead of needing its
	# own separate fix the way the flat +0.1 did.
	const REALIGN_OFFSET := 1.4  # mirrors test_arena.gd's own realign target, ledge.end.z + 1.4
	const GRAB_SAFETY_TIME := 0.12
	var time_to_ledge_reach: float = maxf(REALIGN_OFFSET - vault_config.ledge_reach, 0.0) / config.ground_speed
	var grab_time: float = time_to_ledge_reach + GRAB_SAFETY_TIME
	var height_risen_at_grab: float = config.jump_velocity * grab_time - 0.5 * config.gravity * grab_time * grab_time
	var ledge_low_height: float = vault_config.ledge_min_height + height_risen_at_grab
	var ledge_mid_height: float = vault_config.ledge_max_height - 0.1
	var ledge_low_z: float = wall_too_tall_far_z - REALIGN_BUFFER - ledge_gap
	_attach(vault_area, _box("LedgeLow", Vector3(4.0, ledge_low_height, LEDGE_DEPTH),
		Vector3(0.0, ledge_low_height * 0.5, ledge_low_z), ledge_colour))
	var ledge_low_far_z: float = ledge_low_z - LEDGE_DEPTH * 0.5
	var ledge_mid_z: float = ledge_low_far_z - REALIGN_BUFFER - ledge_gap
	_attach(vault_area, _box("LedgeMid", Vector3(4.0, ledge_mid_height, LEDGE_DEPTH),
		Vector3(0.0, ledge_mid_height * 0.5, ledge_mid_z), ledge_colour))

	# And a platform clearly beyond ledge_max_height, so "too high to grab"
	# has something to point at too. Never driven at by the traversal test
	# (only checked structurally, by test_the_ledge_platforms_bracket_the_
	# configured_range), so it stays a short, fixed hop past LedgeMid rather
	# than another full run-up-and-jump away.
	const LEDGE_TOO_HIGH_GAP := 6.0
	var ledge_mid_far_z: float = ledge_mid_z - LEDGE_DEPTH * 0.5
	var ledge_too_high_z: float = ledge_mid_far_z - LEDGE_TOO_HIGH_GAP
	var ledge_too_high_height: float = vault_config.ledge_max_height + 1.5
	_attach(vault_area, _box("LedgeTooHigh", Vector3(4.0, ledge_too_high_height, LEDGE_DEPTH),
		Vector3(0.0, ledge_too_high_height * 0.5, ledge_too_high_z), blocked_colour))

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
	#   z ~65 .. 55         approach  bare arena floor -- ground_accel (60 m/s^2)
	#                                 reaches wall_min_speed (5 m/s) in well under
	#                                 a metre, so this is about pacing, not need
	#   z  55 .. LongWall's far z     one continuous wall, length derived below
	#   z  LongWall's far z .. 35.5   gap: bare floor, a beat to land and reset
	#                                 before the zig-zag starts
	#   z  35.5 .. the zig-zag's own far z     four walls alternating sides,
	#                                 chained by wall jumps -- see the note
	#                                 above the loop
	#
	# Both derived spans above move with wall_config (wall_max_speed,
	# wall_max_duration, wall_reattach_cooldown) rather than holding still, so
	# retuning any of those keeps this comment true without anyone having to
	# hand-edit a z value here.
	#
	# The floor is sized AFTER this area (see the Floor comment further down)
	# specifically so nothing here can ever hang over its edge: the floor's
	# footprint is derived from the union of every area's own bounds, this one
	# included, plus a fixed margin -- so a future change to LongWall's own
	# length or the zig-zag's own spacing keeps the floor covering it
	# automatically instead of needing a hand-tuned edge coordinate here.
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
	# Tall enough to contain a CHAINED climb, though no longer sized to hide an
	# unbounded one -- a PREVIOUS pass here found that wall_run_state.gd's
	# consume_buffered_jump() branch ASSIGNED velocity.y = wall_jump_up on
	# every wall-jump with no reference to how much height a chain had already
	# banked, and "fixed" the symptom by making these walls tall enough to
	# contain the worst case instead of touching the mechanic (see this task's
	# own report on why that was a band-aid). WallRunState now bounds the
	# climb itself: a chain of wall-jumps can never lift the player more than
	# jump_peak_height (one plain jump's own reach) plus one wall_jump's own
	# textbook peak rise above the ground it started from -- see
	# wall_run_state.gd's own comment on that fix for the reasoning. This
	# mirrors that SAME derivation, using PLAIN gravity rather than
	# wall_gravity_scale-weakened gravity to match it exactly (gravity is
	# never weakened the instant a wall-jump hands off to AirState;
	# wall_gravity_scale only applies while actually attached), so a future
	# retune of gravity/jump_velocity/wall_jump_up keeps this tall enough
	# automatically without needing its own separate fix -- and no longer
	# needs multiplying by the zig-zag's own wall count, since the bound no
	# longer grows with chain length.
	var wall_jump_peak_rise: float = (wall_config.wall_jump_up * wall_config.wall_jump_up) \
		/ (2.0 * maxf(wall_config.gravity, 0.001))
	const WALL_HEIGHT_MARGIN := 1.3
	var wall_run_height: float = (jump_peak_height + wall_jump_peak_rise) * WALL_HEIGHT_MARGIN

	# Long enough to exhaust a FULL wall_max_duration run, not merely the
	# brief's minimum bar (half of wall_max_speed * wall_max_duration, which
	# only proves the duration cap is reachable in principle) -- using the
	# whole product means a run that holds along this wall the entire time
	# actually hits the timer, not just clears the test's threshold.
	var long_wall_length: float = wall_config.wall_max_speed * wall_config.wall_max_duration
	const LONG_WALL_NEAR_Z := 55.0
	var long_wall_far_z: float = LONG_WALL_NEAR_Z - long_wall_length
	_attach(wall_area, _box("LongWall",
		Vector3(WALL_THICKNESS, wall_run_height, long_wall_length),
		Vector3(WALL_NEAR_FACE + WALL_THICKNESS * 0.5, wall_run_height * 0.5,
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
	const ZIG_START_Z := 35.5

	# ZIG_STEP -- the distance between CONSECUTIVE zig walls' near faces --
	# used to be a hardcoded 4.0, the one length in this whole area that was
	# not derived from config. That let it silently fall out of sync with the
	# very cooldown it has to clear: ZigLeft1 and ZigLeft2 share a normal (two
	# walls apart, so 2 * ZIG_STEP in Z), and player.can_attach_wall() refuses
	# a same-facing wall until wall_reattach_cooldown has elapsed. A player
	# chaining the walls well does not ride each one to its far end before
	# jumping off -- they leave via the wall jump long before that, so the
	# REAL forward distance covered between leaving one same-facing wall and
	# reaching the next tracks closer to ZIG_STEP alone than to the full
	# nominal 2 * ZIG_STEP gap between them (this is what let the old 4.0
	# hardcode look safe on paper -- 2 * 4.0 = 8 m against an 11 m/s wall's
	# 5.5 m cooldown reach -- while still refusing the third wall for ~0.14 s
	# in an actual fast run). ZIG_STEP is therefore held, on its own, to
	# comfortably clear the distance a player moving at wall_max_speed the
	# whole time would cover before the cooldown expires -- a flat break-even
	# value would just move the same failure to whichever knob gets tuned
	# next, so ZIG_STEP_SAFETY_MARGIN keeps real headroom over it. Verified
	# against actual chained play, not just this arithmetic: see
	# tests/test_arena.gd's test_the_zig_zag_wall_section_chains_multiple_walls.
	const ZIG_STEP_SAFETY_MARGIN := 1.5
	var zig_step: float = wall_config.wall_max_speed * wall_config.wall_reattach_cooldown \
		* ZIG_STEP_SAFETY_MARGIN
	# Consecutive walls must still overlap in Z, or a wall jump timed to land
	# between them finds neither -- wall_query() only sees a wall where its
	# collision box actually is, so a Z gap between them would be a dead
	# stretch no cooldown fix could rescue. ZIG_OVERLAP is the same 2 m this
	# area always used; ZIG_LENGTH now tracks ZIG_STEP (rather than the
	# reverse) specifically so growing ZIG_STEP to satisfy the cooldown above
	# can never shrink -- or invert -- that overlap.
	const ZIG_OVERLAP := 2.0
	var zig_length: float = zig_step + ZIG_OVERLAP

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
		var near_z: float = ZIG_START_Z - zig_step * index
		var far_z: float = near_z - zig_length
		_attach(wall_area, _box(wall_name, Vector3(WALL_THICKNESS, wall_run_height, zig_length),
			Vector3(side * ZIG_X, wall_run_height * 0.5, (near_z + far_z) * 0.5), wall_colour))

	# --- Floor ----------------------------------------------------------------
	#
	# Sized from the union of every practice area's OWN bounds, not the other
	# way round: every course above already derives its own geometry from the
	# live jump arc (see each area's comments), so the floor is the one piece
	# of geometry that must ADAPT to whatever they need, not something they are
	# squeezed to fit inside. A fixed footprint (this used to be a hardcoded
	# FLOOR_NORTH_EDGE=70 / FLOOR_SOUTH_MARGIN=25, sized to fit only VaultArea's
	# own worst case) silently stopped covering JumpArea's gap ladder once the
	# jump arc roughly doubled: Gap5 and Gap6 ended up sitting 14-32 m past the
	# floor's south edge with nothing underneath them, which sent a missed jump
	# there into an endless fall and the fall-recovery teleport instead of back
	# onto solid practice ground -- silently destroying the thing the ladder
	# exists to teach. Nothing caught it because the containment test of the
	# time only ever checked VaultArea and WallArea by name; see
	# tests/test_arena.gd's test_every_practice_area_fits_inside_the_arena_floor
	# for the generalised replacement that closes that gap.
	#
	# Areas are discovered the same "XxxArea" naming convention
	# test_practice_areas_do_not_overlap_each_other and the containment test
	# above both already use, so a newly added area is covered the moment it
	# exists, with no separate floor-sizing code to remember to update.
	var practice_bounds: AABB
	var has_practice_bounds := false
	for area in _root.get_children():
		if not (area is Node3D and String(area.name).ends_with("Area")):
			continue
		var boxes: Array = []
		_collect_box_bodies(area, boxes)
		for body in boxes:
			var body_aabb := _world_aabb(body)
			if not has_practice_bounds:
				practice_bounds = body_aabb
				has_practice_bounds = true
			else:
				practice_bounds = practice_bounds.merge(body_aabb)

	# Generous, uniform headroom beyond the outermost body on every side --
	# not a tight fit. Sized to comfortably clear the largest known approach
	# runway in the arena: WallArea's own north approach starts the player 8 m
	# north of LongWall's near face (see
	# tests/test_arena.gd's test_the_wall_run_course_can_be_run_end_to_end),
	# and LongWall's near face is the arena's northernmost solid body, so a
	# margin under 8 m there would put that test's own start position off the
	# floor. This is a fixed design buffer, like GAP_PLATFORM_LENGTH or
	# LEDGE_DEPTH above -- not something that scales with the jump arc.
	const FLOOR_MARGIN := 10.0
	var floor_min_x: float = practice_bounds.position.x - FLOOR_MARGIN
	var floor_max_x: float = practice_bounds.end.x + FLOOR_MARGIN
	var floor_min_z: float = practice_bounds.position.z - FLOOR_MARGIN
	var floor_max_z: float = practice_bounds.end.z + FLOOR_MARGIN
	var floor_size := Vector3(floor_max_x - floor_min_x, 1.0, floor_max_z - floor_min_z)
	var floor_center := Vector3((floor_min_x + floor_max_x) * 0.5, -0.5,
		(floor_min_z + floor_max_z) * 0.5)
	var floor_body := _box("Floor", floor_size, floor_center, ground)
	_attach(_root, floor_body)
	# Purely cosmetic in the resulting tree/.tscn: index 3 keeps Floor reading
	# as "the ground, before the courses standing on it" (right after Sun,
	# WorldEnvironment, SpawnPoint), matching where it always used to sit.
	# Nothing depends on this ordering -- containment and overlap checks alike
	# find bodies by name/path, not by sibling index.
	_root.move_child(floor_body, 3)

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

extends TestCase

const SCENE := "res://scenes/main.tscn"

func _load_arena() -> Node3D:
	var packed: PackedScene = ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	var arena = packed.instantiate()
	tree.root.add_child(arena)
	await step(3)
	return arena

func test_arena_scene_is_wired() -> void:
	await step(1)
	check(ResourceLoader.exists(SCENE), "main.tscn was not generated")
	var arena = await _load_arena()

	check(arena.player != null, "Arena.player export was not wired")
	check(arena.spawn_point != null, "Arena.spawn_point export was not wired")
	check(arena.config != null, "Arena did not create a default MovementConfig")
	check(arena.get_node_or_null("Floor") != null, "Floor missing")
	check(arena.get_node_or_null("JumpArea/Gap6") != null, "jump area geometry missing")
	check(arena.get_node_or_null("JumpArea/DropHigh") != null, "drop towers missing")

	arena.queue_free()
	await step(1)

func test_player_and_panel_share_one_config_instance() -> void:
	await step(1)
	var arena = await _load_arena()
	# If these are different objects, dragging a slider changes nothing.
	check(arena.player.config == arena.config, "player does not share the arena's config")
	arena.queue_free()
	await step(1)

func test_player_settles_on_the_floor_at_spawn() -> void:
	await step(1)
	var arena = await _load_arena()
	await step(60)
	check(arena.player.is_on_floor(), "player did not settle onto the arena floor")
	check(arena.player.state_machine.current_name == &"Ground", "player is not in Ground at rest")
	arena.queue_free()
	await step(1)

func test_reset_returns_the_player_to_spawn() -> void:
	await step(1)
	var arena = await _load_arena()
	arena.player.global_position = Vector3(20.0, 12.0, -20.0)
	await step(5)
	arena.reset_player()
	await step(1)
	var offset: float = arena.player.global_position.distance_to(arena.spawn_point.global_position)
	check(offset < 0.01, "reset did not return the player to spawn (offset %f)" % offset)
	check(arena.player.velocity.length() < 0.01, "reset did not clear velocity")
	arena.queue_free()
	await step(1)

func test_reset_restores_a_level_view_and_does_not_fire_a_buffered_jump() -> void:
	await step(1)
	var arena = await _load_arena()
	var player = arena.player
	await step(30)

	# Pitch the camera through the same public path real mouse input takes.
	player.camera_rig.apply_look(Vector2(0.0, -500.0), player)
	await step(1)
	check(absf(player.camera_rig.rotation.x) > 0.01, "precondition: camera should be pitched")

	# Force the player airborne and let coyote time fully decay, then buffer
	# a jump press while still in the air. Both conditions consume_jump()
	# checks land on the SAME tick only if it fires immediately, so this
	# reproduces "pressed jump slightly before pressing R" without the jump
	# firing before the reset even happens.
	player.state_machine.start(PlayerState.AIR)
	player.global_position = arena.spawn_point.global_position + Vector3(0.0, 5.0, 0.0)
	await step(20)
	check(player.state_machine.current_name == &"Air", \
		"precondition: player should still be airborne")

	var input := ScriptedInputSource.new()
	player.input_source = input
	input.press_jump()
	await step(1)
	check(player.velocity.y < 4.0, \
		"precondition: the buffered jump must not have fired yet, velocity.y = %f" % player.velocity.y)

	arena.reset_player()
	await step(1)
	check_approx(player.camera_rig.rotation.x, 0.0, 0.001, "reset did not restore a level camera view")

	# reset_player() itself freezes Player physics for exactly one tick, and
	# the player then takes several more ticks to actually settle onto the
	# floor and refresh coyote time — a stale leftover jump buffer would only
	# fire on the tick coyote refreshes, not immediately. Watch a window well
	# past that settling point (~5-6 ticks; test_player_settles_on_the_floor
	# _at_spawn gives it up to 60) rather than a single frame, and look for
	# the unmistakable signature of a fired jump — velocity.y jumping to
	# roughly jump_velocity — rather than merely "not currently in Ground",
	# since brief airborne settling ticks are normal and not a bug.
	var cfg: MovementConfig = player.config
	var jumped := false
	for i in 20:
		await step(1)
		if player.velocity.y > cfg.jump_velocity * 0.5:
			jumped = true
	check(not jumped, "a buffered jump fired after reset instead of staying grounded")
	check(player.state_machine.current_name == &"Ground", \
		"player did not settle back into Ground after the reset, state = %s" \
			% player.state_machine.current_name)

	arena.queue_free()
	await step(1)

func test_falling_out_of_the_level_respawns_the_player() -> void:
	await step(1)
	var arena = await _load_arena()
	await step(30)

	# Past the floor's south edge, the practice gaps deliberately extend
	# further than the floor so their spacing keeps reading off increasing
	# jump distances (see tools/build_main_scene.gd) — a missed jump falls
	# forever there without the kill-plane recovery this test checks for.
	var fall_depth: float = arena.config.fall_recovery_depth + 5.0
	arena.player.global_position = arena.spawn_point.global_position + Vector3(0.0, -fall_depth, 0.0)
	for i in 5:
		await step(1)

	var offset: float = arena.player.global_position.distance_to(arena.spawn_point.global_position)
	check(offset < 1.0, "falling below the kill plane did not return the player to spawn (offset %f)" % offset)

	arena.queue_free()
	await step(1)

func test_debug_hud_is_wired_and_reports_state() -> void:
	await step(1)
	var arena = await _load_arena()
	var hud = arena.get_node_or_null("DebugHud")
	check(hud != null, "DebugHud node missing from the arena")
	check(hud.player == arena.player, "DebugHud.player export was not wired")

	await step(30)
	# _process only refreshes while visible, which is the default.
	check(hud.visible, "HUD should start visible")
	var text: String = hud._label.text
	check(text.contains("state"), "HUD text missing the state line")
	check(text.contains("Ground"), "HUD did not report the resting state, text = %s" % text)

	arena.queue_free()
	await step(1)

func test_tuning_panel_writes_back_into_the_shared_config() -> void:
	await step(1)
	var arena = await _load_arena()
	var panel = arena.get_node_or_null("TuningPanel")
	check(panel != null, "TuningPanel node missing from the arena")
	check(panel.config == arena.config, "panel was not given the shared config instance")

	# _build_ui is deferred, so give it a frame to construct the sliders.
	await step(2)
	var sliders: Array = panel._sliders()
	check_greater(float(sliders.size()), 10.0, "expected a slider per float parameter")

	var target: HSlider = null
	for s in sliders:
		if s.get_meta("property_name") == "walk_speed":
			target = s
			break
	check(target != null, "no slider was generated for walk_speed")

	var before: float = arena.config.walk_speed
	target.value = before + 1.0
	await step(1)
	check_approx(arena.config.walk_speed, before + 1.0, 0.001, \
		"moving the slider did not write back into the shared config")
	# The player must see it too, since it holds the same object.
	check_approx(arena.player.config.walk_speed, before + 1.0, 0.001, \
		"the player does not observe the tuned value")

	arena.queue_free()
	await step(1)

func test_preset_save_and_load_round_trips() -> void:
	await step(1)
	var arena = await _load_arena()
	var panel = arena.get_node_or_null("TuningPanel")
	await step(2)

	panel._preset_name.text = "test_roundtrip"
	arena.config.walk_speed = 3.25
	panel._on_save()

	arena.config.walk_speed = 99.0
	panel._on_load()
	check_approx(arena.config.walk_speed, 3.25, 0.001, \
		"preset load did not restore the saved value")

	DirAccess.remove_absolute("user://presets/test_roundtrip.tres")
	arena.queue_free()
	await step(1)

func test_movement_follows_the_view_direction() -> void:
	await step(1)
	var arena = await _load_arena()
	await step(30)
	var player = arena.player

	# Face -X by yawing 90 degrees, then hold forward. Velocity must follow the
	# body's facing, not a fixed world axis.
	player.rotation.y = deg_to_rad(90.0)
	var input := ScriptedInputSource.new()
	input.state.move = Vector2(0.0, 1.0)
	player.input_source = input
	await step(30)

	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	check_greater(horizontal.length(), 1.0, "player did not move")
	check(horizontal.normalized().x < -0.9, \
		"movement did not follow the view direction, dir = %s" % horizontal.normalized())

	arena.queue_free()
	await step(1)

## Top surface of the arena's base floor slab, which is also the slide
## tunnel's deck — there is deliberately no separate tunnel floor box.
func _floor_top(arena) -> float:
	var floor_node := arena.get_node("Floor") as StaticBody3D
	var box: BoxShape3D = (floor_node.get_node("Collision") as CollisionShape3D).shape
	return floor_node.global_position.y + box.size.y * 0.5

func test_the_slide_area_exists_and_is_low_enough_to_require_sliding() -> void:
	await step(1)
	var arena = await _load_arena()
	var roof = arena.get_node_or_null("SlideArea/TunnelRoof")
	check(roof != null, "the slide tunnel roof is missing")

	# The tunnel deck IS the arena floor: measuring against a raised deck box
	# is what let the previous layout pass this test while sitting 1 m above
	# everything the player could actually reach.
	var deck := _floor_top(arena)
	var roof_aabb := _world_aabb(roof)
	var clearance: float = roof_aabb.position.y - deck

	# The tunnel only earns its place if standing cannot fit and sliding can.
	# Both bounds are read from the live capsule and config, so tuning either
	# one cannot leave the tunnel silently impassable or silently pointless.
	var standing := ((arena.player.get_node("CollisionShape3D") as CollisionShape3D).shape \
		as CapsuleShape3D).height
	check(clearance < standing, \
		"the tunnel is tall enough to walk through, so it teaches nothing (clearance %f vs standing %f)" \
		% [clearance, standing])
	check_greater(clearance, arena.config.slide_capsule_height, \
		"the tunnel is lower than the sliding capsule, so even a slide cannot pass (clearance %f vs slide %f)" \
		% [clearance, arena.config.slide_capsule_height])

	# ...and the deck has to be continuous with the floor, not a step up onto
	# one. Assert that literally: nothing in the slide area may occupy the
	# volume between the walls, from just above the deck to just under the
	# roof. A tunnel floor raised even 0.1 m would be a lip a slide cannot
	# climb, and the clearance arithmetic above would never notice.
	var wall_l = arena.get_node_or_null("SlideArea/TunnelWallL")
	var wall_r = arena.get_node_or_null("SlideArea/TunnelWallR")
	check(wall_l != null and wall_r != null, "the slide tunnel walls are missing")
	var interior_min := Vector3(_world_aabb(wall_l).end.x, deck, roof_aabb.position.z)
	var interior_max := Vector3(_world_aabb(wall_r).position.x, roof_aabb.position.y, roof_aabb.end.z)
	# Shrunk so boxes that legitimately END at the tunnel mouth or rest
	# against a wall are not counted as intruding.
	var interior := AABB(interior_min, interior_max - interior_min).grow(-0.05)
	var boxes: Array = []
	_collect_box_bodies(arena.get_node("SlideArea"), boxes)
	for body in boxes:
		if body == wall_l or body == wall_r or body == roof:
			continue
		check(not _world_aabb(body).intersects(interior), \
			"SlideArea/%s intrudes into the tunnel — the deck must be the bare arena floor, with no lip or step" \
			% body.name)

	arena.queue_free()
	await step(1)

## Steps the player forward (travelling toward -Z) until it passes target_z,
## for at most `budget` physics ticks, giving up early if it makes no forward
## progress at all for three seconds. Returns where it got to and whether it
## was ever in Slide along the way, so a failure can report WHERE the player
## stopped instead of only that an assertion failed.
func _advance_until_z(player: Player, target_z: float, budget: int) -> Dictionary:
	var best_z: float = player.global_position.z
	var stalled := 0
	var slid := false
	var crawled := false
	var ticks := 0
	# Crawling is also state Slide, so `slid` alone cannot tell "cleared it on
	# momentum" from "rescued by the safety net". Watch the latch itself.
	var slide_state = player.state_machine.state_for(PlayerState.SLIDE)
	for i in budget:
		await step(1)
		ticks += 1
		if player.state_machine.current_name == PlayerState.SLIDE:
			slid = true
			if slide_state != null and slide_state.is_crawling():
				crawled = true
		var z: float = player.global_position.z
		if z < best_z - 0.005:
			best_z = z
			stalled = 0
		else:
			stalled += 1
		if z <= target_z:
			break
		if stalled > 180:
			break
	var position: Vector3 = player.global_position
	return {
		"reached": position.z <= target_z,
		"slid": slid,
		"crawled": crawled,
		"ticks": ticks,
		"position": position,
		"state": player.state_machine.current_name,
		"speed": player.horizontal_speed(),
	}

func _where(result: Dictionary) -> String:
	var position: Vector3 = result["position"]
	return "stopped at (%.2f, %.2f, %.2f) in state %s at %.2f m/s after %d ticks" \
		% [position.x, position.y, position.z, result["state"], result["speed"], result["ticks"]]

## The clearance test above measures a cross-section; it says nothing about
## whether the tunnel can be REACHED. This one is the reachability oracle: it
## drives the player through the whole course under scripted input and checks
## that it comes out the far side, having actually slid to get there. Every
## landmark is read off the live geometry rather than hardcoded, so re-laying
## out the course cannot leave this test quietly measuring the wrong place.
func test_the_slide_course_can_be_run_end_to_end() -> void:
	await step(1)
	var arena = await _load_arena()
	var player: Player = arena.player

	var up_ramp_aabb := _world_aabb(arena.get_node("SlideArea/UpRamp"))
	var platform_aabb := _world_aabb(arena.get_node("SlideArea/Platform"))
	var roof_aabb := _world_aabb(arena.get_node("SlideArea/TunnelRoof"))
	var deck := _floor_top(arena)
	var lane_x: float = platform_aabb.get_center().x

	# Start on the flat approach, well short of the climb, with room to reach
	# sprint speed before the ramp.
	player.global_position = Vector3(lane_x, deck + 1.0, up_ramp_aabb.end.z + 8.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	await step(20)
	check(player.is_on_floor(), "precondition: the player did not settle onto the approach")

	var input := ScriptedInputSource.new()
	player.input_source = input
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = true

	# Phase 1 — approach and climb, ending a metre onto the raised platform.
	var climb := await _advance_until_z(player, platform_aabb.end.z - 1.0, 900)
	check(climb["reached"], \
		"the player could not reach the raised platform: %s" % _where(climb))
	check_approx(player.global_position.y, platform_aabb.end.y + 0.9, 0.35, \
		"the player reached the platform's z but not its height — it is not standing on the platform: %s" \
		% _where(climb))

	# Phase 2 — commit to the slide and ride it down the ramp and through the
	# tunnel, stopping the measurement exactly AT the far mouth. Sampling there
	# rather than after the exit matters: once the player is clear of the roof
	# it stands up and GroundState winds it straight back to sprint speed, so a
	# reading taken a few metres later would be 9 m/s no matter how the tunnel
	# was crossed.
	input.press_crouch()
	var run := await _advance_until_z(player, roof_aabb.position.z, 1800)
	check(run["reached"], \
		"the player never reached the far mouth of the tunnel: %s" % _where(run))
	check(run["slid"], \
		"the player crossed the course without ever entering Slide, so the route did not require sliding")

	# The tunnel must be passable on slide MOMENTUM, with the crawl as a safety
	# net for the player who commits too late — not as the normal way through.
	# Two independent readings of that, because they fail differently: the
	# crawl latching at all, and the speed at the mouth collapsing to what a
	# crawl would produce even if the latch has not tripped yet.
	check(not run["crawled"], \
		"the player only got through because the crawl rescued it; the tunnel must be clearable on slide momentum: %s" \
		% _where(run))
	check_greater(run["speed"], arena.config.slide_crawl_speed, \
		"speed at the far mouth is no better than a crawl would give, so the slide did not carry the player: %s" \
		% _where(run))

	# Phase 3 — and it actually comes out the other side.
	var exit_run := await _advance_until_z(player, roof_aabb.position.z - 1.5, 600)
	check(exit_run["reached"], \
		"the player reached the far mouth but never came out of it: %s" % _where(exit_run))
	check_approx(player.global_position.y, deck + 0.9, 0.35, \
		"the player left the course vertically instead of running it: %s" % _where(exit_run))

	arena.queue_free()
	await step(1)

## Drives the player toward a world-space waypoint, recomputing the input
## direction every tick, and records which states it passed through on the way.
## The body is never yawed by these tests, so its basis is identity and
## MoveInput's local (x, y) maps to world (+x, -z) — that is what lets a
## waypoint be expressed in world space at all.
##
## Returns the same shape as _advance_until_z so _where() can report it.
func _drive_to(player: Player, input: ScriptedInputSource, target: Vector3, \
		tolerance: float, budget: int, seen: Dictionary) -> Dictionary:
	var best := INF
	var stalled := 0
	var ticks := 0
	var reached := false
	for i in budget:
		var to_target := target - player.global_position
		to_target.y = 0.0
		input.state.move = Vector2(to_target.x, -to_target.z).normalized()
		await step(1)
		ticks += 1
		seen[player.state_machine.current_name] = true

		to_target = target - player.global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance <= tolerance:
			reached = true
			break
		if distance < best - 0.01:
			best = distance
			stalled = 0
		else:
			stalled += 1
		# Three seconds of no progress at all. Deliberately generous: a mantle
		# holds the body on a scripted arc that can briefly move AWAY from a
		# waypoint, and running into an obstacle before vaulting it is a stall
		# by this measure too.
		if stalled > 180:
			break
	return {
		"reached": reached,
		"ticks": ticks,
		"position": player.global_position,
		"state": player.state_machine.current_name,
		"speed": player.horizontal_speed(),
	}

## Holds forward and jumps repeatedly until the ledge in front is grabbed, then
## holds forward through the mantle until it hands back to Ground.
##
## Jumping is what makes a ledge grab possible at all: AirState is the only
## state that runs the ledge probe, and a ledge sitting ledge_min_height or more
## above the feet is by definition above head height from the floor, so the
## player has to leave the ground to reach it. The press is repeated rather than
## timed because the grab window is the first airborne tick of a jump taken from
## within ledge_reach of the face — pressing on every grounded tick guarantees
## one lands there without the test having to know where "there" is.
func _grab_and_mantle(player: Player, input: ScriptedInputSource, budget: int) -> Dictionary:
	input.state.move = Vector2(0.0, 1.0)
	input.state.sprint_held = false
	var grabbed := false
	var ticks := 0
	for i in budget:
		if player.is_on_floor():
			input.press_jump()
		await step(1)
		ticks += 1
		if player.state_machine.current_name == PlayerState.LEDGE:
			grabbed = true
			break
	if not grabbed:
		return {"reached": false, "ticks": ticks, "position": player.global_position, \
			"state": player.state_machine.current_name, "speed": player.horizontal_speed()}

	# Forward is also the mantle's commitment input, so simply keeping it held
	# climbs. Wait for the hand-off, then let GroundState settle.
	for i in budget:
		await step(1)
		ticks += 1
		if player.state_machine.current_name != PlayerState.LEDGE:
			break
	input.state.move = Vector2.ZERO
	await step(20)
	ticks += 20
	return {"reached": true, "ticks": ticks, "position": player.global_position, \
		"state": player.state_machine.current_name, "speed": player.horizontal_speed()}

## The vault/ledge area's counterpart to test_the_slide_course_can_be_run_end_to
## _end. Until this existed the whole area had only STRUCTURAL assertions —
## "LedgeMid's box is between ledge_min_height and ledge_max_height" — and that
## asymmetry is exactly why an inverted mantle_forward_offset could ship: every
## test agreed the geometry was correct and none of them ever tried to climb it.
##
## Every landmark is read off the live geometry rather than hardcoded, so
## re-laying out the course cannot leave this quietly measuring the wrong place,
## and each phase reports WHERE the player stopped when it fails.
func test_the_vault_and_ledge_course_can_be_run_end_to_end() -> void:
	await step(1)
	var arena = await _load_arena()
	var player: Player = arena.player

	var vault_low := _world_aabb(arena.get_node("VaultArea/VaultLow"))
	var vault_high := _world_aabb(arena.get_node("VaultArea/VaultHigh"))
	var wall := _world_aabb(arena.get_node("VaultArea/WallTooTall"))
	var ledge_low := _world_aabb(arena.get_node("VaultArea/LedgeLow"))
	var ledge_mid := _world_aabb(arena.get_node("VaultArea/LedgeMid"))
	var deck := _floor_top(arena)
	var lane_x: float = vault_low.get_center().x

	# Count the two manoeuvres this course exists to teach, over the whole run.
	# Without these the test could be satisfied by a player who simply walked
	# around everything: the vault obstacles are only 4 m wide on a 60 m floor.
	var vaults := [0]
	var mantles := [0]
	player.state_machine.state_changed.connect(func(from: StringName, to: StringName) -> void:
		if to == PlayerState.VAULT:
			vaults[0] += 1
		elif from == PlayerState.LEDGE and to == PlayerState.GROUND:
			mantles[0] += 1)

	player.global_position = Vector3(lane_x, deck + 1.0, vault_low.end.z + 6.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	await step(20)
	check(player.is_on_floor(), "precondition: the player did not settle onto the course approach")

	var input := ScriptedInputSource.new()
	player.input_source = input
	input.state.sprint_held = true

	var seen: Dictionary = {}

	# Phase 1 — the three vaultable obstacles, in the lane, at sprint speed.
	var vault_run := await _drive_to(player, input, \
		Vector3(lane_x, 0.0, vault_high.position.z - 1.5), 1.0, 900, seen)
	check(vault_run["reached"], \
		"the player could not get past the vault obstacles: %s" % _where(vault_run))
	check_greater(float(vaults[0]), 2.5, \
		"the player crossed all three vaultable obstacles having vaulted %d of them — the route did not require vaulting: %s" \
		% [vaults[0], _where(vault_run)])

	# Phase 2 — WallTooTall is deliberately unvaultable and deliberately only
	# partly across the lane, so the way past it is around its open side.
	var bypass_x: float = wall.end.x + 0.7
	var bypass := await _drive_to(player, input, Vector3(bypass_x, 0.0, wall.end.z - 0.5), 1.0, 900, seen)
	check(bypass["reached"], \
		"the player could not reach the open side of WallTooTall: %s" % _where(bypass))
	var past_wall := await _drive_to(player, input, Vector3(bypass_x, 0.0, wall.position.z - 2.0), 1.0, 900, seen)
	check(past_wall["reached"], \
		"the player could not get past WallTooTall: %s" % _where(past_wall))
	check(not seen.has(PlayerState.VAULT) or vaults[0] == 3, \
		"WallTooTall was vaulted; it exists to prove the height limit is real")

	# Phase 3 — back into the lane and up LedgeLow.
	var realign := await _drive_to(player, input, \
		Vector3(lane_x, 0.0, ledge_low.end.z + 1.4), 0.6, 900, seen)
	check(realign["reached"], \
		"the player could not line up on LedgeLow: %s" % _where(realign))

	input.state.sprint_held = false
	var climb_low := await _grab_and_mantle(player, input, 600)
	check(climb_low["reached"], "the player never grabbed LedgeLow: %s" % _where(climb_low))
	check(player.state_machine.current_name == PlayerState.GROUND and player.grounded, \
		"the player did not end up standing on LedgeLow: %s" % _where(climb_low))
	check_approx(player.global_position.y, ledge_low.end.y + 0.9, 0.35, \
		"the player is not standing on top of LedgeLow (top y=%f): %s" \
		% [ledge_low.end.y, _where(climb_low)])

	# Phase 4 — off the far side of LedgeLow, across the gap, and up LedgeMid,
	# which is the tallest thing in the area that can still be grabbed.
	var descend := await _drive_to(player, input, \
		Vector3(lane_x, 0.0, ledge_mid.end.z + 1.4), 0.6, 900, seen)
	check(descend["reached"], \
		"the player could not cross from LedgeLow to LedgeMid: %s" % _where(descend))

	var climb_mid := await _grab_and_mantle(player, input, 600)
	check(climb_mid["reached"], "the player never grabbed LedgeMid: %s" % _where(climb_mid))

	# The end condition: past the far end of the reachable course, on solid
	# ground, at LedgeMid's own height — which is 2.7 m of sheer face, so there
	# is no way to be standing here that did not involve climbing it.
	check(player.state_machine.current_name == PlayerState.GROUND, \
		"the player did not finish the course in Ground: %s" % _where(climb_mid))
	check(player.grounded, "the player did not finish the course on solid ground: %s" % _where(climb_mid))
	check_approx(player.global_position.y, ledge_mid.end.y + 0.9, 0.35, \
		"the player is not standing on top of LedgeMid (top y=%f): %s" \
		% [ledge_mid.end.y, _where(climb_mid)])
	check(player.global_position.z < ledge_mid.end.z, \
		"the player finished short of LedgeMid's near face (z=%f): %s" \
		% [ledge_mid.end.z, _where(climb_mid)])

	check_greater(float(mantles[0]), 1.5, \
		"the course was completed with %d mantle(s); both ledges must be climbed, not walked around" % mantles[0])
	check_greater(float(vaults[0]), 2.5, \
		"the course was completed with %d vault(s); all three vaultable obstacles must be vaulted" % vaults[0])

	arena.queue_free()
	await step(1)

## Recursively collects every StaticBody3D with a box-shaped "Collision"
## child under node, used by test_practice_areas_do_not_overlap_each_other.
func _collect_box_bodies(node: Node, out: Array) -> void:
	if node is StaticBody3D:
		var collision := node.get_node_or_null("Collision")
		if collision is CollisionShape3D and collision.shape is BoxShape3D:
			out.append(node)
	for child in node.get_children():
		_collect_box_bodies(child, out)

## World-space AABB of a box body, computed from its live global transform so
## rotated boxes (the slide course's UpRamp and DownRamp) are handled
## correctly, not just translated ones.
func _world_aabb(body: Node3D) -> AABB:
	var box: BoxShape3D = (body.get_node("Collision") as CollisionShape3D).shape
	var half := box.size * 0.5
	return body.global_transform * AABB(-half, box.size)

func test_practice_areas_do_not_overlap_each_other() -> void:
	await step(1)
	var arena = await _load_arena()

	# Practice areas are discovered by the existing "XxxArea" naming
	# convention (JumpArea, SlideArea, and whatever P2/P3 add) rather than
	# hardcoded, so a newly added area is covered the moment it exists. Floor,
	# SpawnPoint, Player, etc. don't match and are excluded automatically.
	var areas: Dictionary = {}  # area name -> Array[StaticBody3D]
	for child in arena.get_children():
		if child is Node3D and String(child.name).ends_with("Area"):
			var boxes: Array = []
			_collect_box_bodies(child, boxes)
			areas[child.name] = boxes

	var area_names: Array = areas.keys()
	check_greater(float(area_names.size()), 1.0, \
		"expected at least two practice areas to compare, found %d" % area_names.size())

	# _collect_box_bodies only recognises a solid whose collision child is
	# named exactly "Collision" with a BoxShape3D on it — the convention
	# _box() follows. An area built some other way would contribute zero
	# boxes and be silently excluded from every comparison below, so the
	# whole test would pass by not looking. Fail loudly instead.
	for area_name in area_names:
		check_greater(float(areas[area_name].size()), 0.0, \
			"%s contributed no box solids, so it was silently skipped by the overlap check" % area_name)

	# Boxes touching face-to-face (e.g. the tunnel roof resting on its walls)
	# are legitimate and must not be flagged, so each box is shrunk slightly
	# before the intersection test. Only comparisons ACROSS different areas
	# are made — two boxes inside the same area are allowed to touch or even
	# be designed to abut, and are never compared here.
	const TOLERANCE := 0.01
	for i in area_names.size():
		for j in range(i + 1, area_names.size()):
			var name_a: String = area_names[i]
			var name_b: String = area_names[j]
			for body_a in areas[name_a]:
				var aabb_a: AABB = _world_aabb(body_a).grow(-TOLERANCE)
				for body_b in areas[name_b]:
					var aabb_b: AABB = _world_aabb(body_b).grow(-TOLERANCE)
					check(not aabb_a.intersects(aabb_b), \
						"%s/%s overlaps %s/%s — practice areas must not intersect each other" \
						% [name_a, body_a.name, name_b, body_b.name])

	arena.queue_free()
	await step(1)

func test_the_vault_area_spans_the_configured_limits() -> void:
	await step(1)
	var arena = await _load_arena()
	for name in ["VaultLow", "VaultMid", "VaultHigh", "WallTooTall", "LedgeLow", "LedgeMid", "LedgeTooHigh"]:
		check(arena.get_node_or_null("VaultArea/%s" % name) != null, "%s is missing" % name)

	# The area is only useful if it brackets the configured limits: something
	# just inside each bound and something just outside it.
	var high = arena.get_node("VaultArea/VaultHigh")
	var high_box := ((high.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check(high_box.size.y <= arena.config.vault_max_height, \
		"VaultHigh should sit at or under the vault limit")

	var wall = arena.get_node("VaultArea/WallTooTall")
	var wall_box := ((wall.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check_greater(wall_box.size.y, arena.config.vault_max_height, \
		"WallTooTall should exceed the vault limit, or it teaches nothing")

	arena.queue_free()
	await step(1)

## Companion to test_the_vault_area_spans_the_configured_limits, covering the
## ledge half of the same area: LedgeLow and LedgeMid must each fall inside
## [ledge_min_height, ledge_max_height], bracketing the two ends of that
## range, and LedgeTooHigh must clearly exceed it.
func test_the_ledge_platforms_bracket_the_configured_range() -> void:
	await step(1)
	var arena = await _load_arena()

	var low = arena.get_node("VaultArea/LedgeLow")
	var low_box := ((low.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check(low_box.size.y >= arena.config.ledge_min_height, \
		"LedgeLow should sit at or above the ledge minimum, or it can never be grabbed")
	check(low_box.size.y <= arena.config.ledge_max_height, \
		"LedgeLow should still be within the reachable ledge range")

	var mid = arena.get_node("VaultArea/LedgeMid")
	var mid_box := ((mid.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check(mid_box.size.y <= arena.config.ledge_max_height, \
		"LedgeMid should sit at or under the ledge maximum")
	check_greater(mid_box.size.y, arena.config.ledge_min_height, \
		"LedgeMid should still be within the reachable ledge range")

	var too_high = arena.get_node("VaultArea/LedgeTooHigh")
	var too_high_box := ((too_high.get_node("Collision") as CollisionShape3D).shape as BoxShape3D)
	check_greater(too_high_box.size.y, arena.config.ledge_max_height, \
		"LedgeTooHigh should exceed the ledge limit, or it teaches nothing")

	arena.queue_free()
	await step(1)

## The hard constraint from this task's brief: every body in the new practice
## area must sit entirely inside the arena floor's footprint, or a missed
## attempt drops the player through open air into the fall-recovery
## teleport instead of back onto solid ground. Read the floor's own live
## extent rather than hardcoding a +-30 literal, so a future floor resize
## cannot leave this test quietly checking the wrong bound.
func test_the_vault_area_fits_inside_the_arena_floor() -> void:
	await step(1)
	var arena = await _load_arena()

	var floor_node := arena.get_node("Floor") as StaticBody3D
	var floor_box: BoxShape3D = (floor_node.get_node("Collision") as CollisionShape3D).shape
	var floor_aabb := AABB(floor_node.global_position - floor_box.size * 0.5, floor_box.size)

	var boxes: Array = []
	_collect_box_bodies(arena.get_node("VaultArea"), boxes)
	check_greater(float(boxes.size()), 0.0, \
		"VaultArea contributed no box solids, so this test silently checked nothing")

	for body in boxes:
		var body_aabb := _world_aabb(body)
		check(body_aabb.position.x >= floor_aabb.position.x and body_aabb.end.x <= floor_aabb.end.x, \
			"VaultArea/%s extends past the floor's x extent (body %s, floor %s)" \
			% [body.name, body_aabb, floor_aabb])
		check(body_aabb.position.z >= floor_aabb.position.z and body_aabb.end.z <= floor_aabb.end.z, \
			"VaultArea/%s extends past the floor's z extent (body %s, floor %s)" \
			% [body.name, body_aabb, floor_aabb])

	arena.queue_free()
	await step(1)

## Recursively builds a semantic snapshot of a node tree for structural
## comparison: node path, class, script identity, local transform, and (for a
## CollisionShape3D wrapping a BoxShape3D) its shape size. Deliberately
## excludes anything belonging to the on-disk .tscn FORMAT rather than the
## live objects it describes — unique_id values and sub_resource/ext_resource
## numbering both churn on every save, which is exactly why a plain text diff
## of scenes/main.tscn against itself is useless here. None of that is
## visible through the node/resource API this walks, so it is excluded by
## construction rather than by filtering it back out afterward.
func _snapshot(node: Node, path: String, out: Dictionary) -> void:
	var entry := {
		"class": node.get_class(),
		"script": node.get_script().resource_path if node.get_script() != null else "",
	}
	if node is Node3D:
		entry["position"] = node.position
		entry["rotation"] = node.rotation
		entry["scale"] = node.scale
	if node is CollisionShape3D and node.shape is BoxShape3D:
		entry["box_size"] = (node.shape as BoxShape3D).size
	out[path] = entry
	for child in node.get_children():
		_snapshot(child, path + "/" + String(child.name), out)

## Regenerating scenes/main.tscn must never be able to silently diverge from
## what is actually committed — that is exactly how a hand-edited .tscn (a
## Floor resized from 60x1x60 to 60x1x80.84 by something other than this
## generator) once sat undetected in this repo. ArenaBuilder.build() is the
## single source of truth both tools/build_main_scene.gd and this test call,
## so comparing its live, unsaved output against what ResourceLoader reads
## back from disk is a direct test of "the committed file IS this generator's
## output", not an approximation of it.
func test_regenerating_the_scene_matches_what_is_committed() -> void:
	await step(1)

	var builder_script: GDScript = load("res://tools/arena_builder.gd")
	var fresh: Node3D = builder_script.new().build()
	var fresh_snapshot: Dictionary = {}
	_snapshot(fresh, fresh.name, fresh_snapshot)
	fresh.free()  # never entered a tree — an immediate free() is correct here

	var packed: PackedScene = ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE)
	var committed: Node3D = packed.instantiate()
	var committed_snapshot: Dictionary = {}
	_snapshot(committed, committed.name, committed_snapshot)
	committed.free()

	var fresh_paths: Array = fresh_snapshot.keys()
	var committed_paths: Array = committed_snapshot.keys()

	var only_fresh: Array = []
	for p in fresh_paths:
		if not committed_snapshot.has(p):
			only_fresh.append(p)
	var only_committed: Array = []
	for p in committed_paths:
		if not fresh_snapshot.has(p):
			only_committed.append(p)
	check(only_fresh.is_empty() and only_committed.is_empty(), \
		"regenerating produces a different node set than what is committed — only in regenerated: %s, only in committed: %s" \
		% [only_fresh, only_committed])

	for path in fresh_paths:
		if not committed_snapshot.has(path):
			continue  # already reported above
		var a: Dictionary = fresh_snapshot[path]
		var b: Dictionary = committed_snapshot[path]
		check(a["class"] == b["class"], \
			"%s: class differs between regenerated (%s) and committed (%s)" % [path, a["class"], b["class"]])
		check(a["script"] == b["script"], \
			"%s: script differs between regenerated (%s) and committed (%s)" % [path, a["script"], b["script"]])
		if a.has("position"):
			check((a["position"] as Vector3).is_equal_approx(b["position"]), \
				"%s: position differs between regenerated (%s) and committed (%s)" % [path, a["position"], b["position"]])
			check((a["rotation"] as Vector3).is_equal_approx(b["rotation"]), \
				"%s: rotation differs between regenerated (%s) and committed (%s)" % [path, a["rotation"], b["rotation"]])
			check((a["scale"] as Vector3).is_equal_approx(b["scale"]), \
				"%s: scale differs between regenerated (%s) and committed (%s)" % [path, a["scale"], b["scale"]])
		if a.has("box_size"):
			check((a["box_size"] as Vector3).is_equal_approx(b["box_size"]), \
				"%s: collision box size differs between regenerated (%s) and committed (%s)" % [path, a["box_size"], b["box_size"]])

	await step(1)

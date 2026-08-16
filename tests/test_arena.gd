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

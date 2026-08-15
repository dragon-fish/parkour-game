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

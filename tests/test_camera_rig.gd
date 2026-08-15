extends TestCase

const TICK := 1.0 / 60.0

func _make_rig() -> CameraRig:
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	tree.root.add_child(rig)
	return rig

func test_fov_widens_as_speed_rises() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	for i in 120:
		rig.update_effects(TICK, 0.0, true)
	var slow_fov := rig.camera.fov

	for i in 120:
		rig.update_effects(TICK, cfg.fov_speed_ref, true)
	var fast_fov := rig.camera.fov

	check_greater(fast_fov, slow_fov, "FOV did not widen with speed")
	rig.queue_free()
	await step(1)

func test_landing_dip_lowers_then_recovers() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	rig.punch_landing(cfg.land_dip_speed_ref)
	rig.update_effects(TICK, 0.0, true)
	var dipped := rig.camera.position.y
	check(dipped < 0.0, "landing did not lower the camera, y = %f" % dipped)

	for i in 300:
		rig.update_effects(TICK, 0.0, true)
	check_approx(rig.camera.position.y, 0.0, 0.01, "camera did not recover from the landing dip")

	rig.queue_free()
	await step(1)

func test_pitch_is_clamped() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	var body := Node3D.new()
	tree.root.add_child(body)
	await step(1)

	# Push the view far past vertical in both directions.
	for i in 200:
		rig.apply_look(Vector2(0.0, -1000.0), body)
	check(rig.rotation.x <= deg_to_rad(cfg.pitch_limit_deg) + 0.001, "pitch exceeded the upper limit")

	for i in 400:
		rig.apply_look(Vector2(0.0, 1000.0), body)
	check(rig.rotation.x >= -deg_to_rad(cfg.pitch_limit_deg) - 0.001, "pitch exceeded the lower limit")

	rig.queue_free()
	body.queue_free()
	await step(1)

func test_bob_fades_instead_of_snapping_at_liftoff() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	var speed := cfg.fov_speed_ref
	# Advance to (near) the first bob peak so the recorded offset is clearly
	# non-zero regardless of the config's tuning values, rather than hoping a
	# fixed frame count happens to land away from a zero crossing.
	var frames_to_peak := int(round((PI / 2.0) / (TICK * cfg.bob_frequency * speed)))
	for i in frames_to_peak:
		rig.update_effects(TICK, speed, true)
	var grounded_offset := rig.camera.position.y
	check_greater(absf(grounded_offset), cfg.bob_amplitude * 0.5, "bob offset was not clearly non-zero while grounded")

	# The instant the player leaves the ground, the offset must fade, not snap.
	rig.update_effects(TICK, speed, false)
	var just_after_takeoff := rig.camera.position.y
	check(absf(just_after_takeoff - grounded_offset) < absf(just_after_takeoff), "bob offset collapsed toward zero the instant the player left the ground")

	for i in 300:
		rig.update_effects(TICK, speed, false)
	check_approx(rig.camera.position.y, 0.0, 0.01, "bob offset did not fade toward zero while airborne")

	rig.queue_free()
	await step(1)

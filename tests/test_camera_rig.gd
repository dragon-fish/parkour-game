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

func test_eye_height_is_applied_and_stays_live_tunable() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	check_approx(rig.position.y, cfg.eye_height, 0.001, "setup() did not apply eye_height")

	# The F1 panel writes straight into the shared config at runtime; a live
	# rig must pick that up on the next tick rather than only at setup().
	cfg.eye_height = cfg.eye_height + 1.0
	rig.update_effects(TICK, 0.0, true)
	check_approx(rig.position.y, cfg.eye_height, 0.001, "eye_height change was not applied live")

	rig.queue_free()
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

## IMPORTANT (review): asserting only that the two sides roll opposite ways
## cannot catch a sign INVERSION -- a roll flipped on both sides together is
## still "opposite ways". This additionally checks each side against an
## independent, world-space quantity the sign has to agree with: the camera's
## own up vector. Verified empirically against this exact Godot build first
## (not assumed): a positive rotation.z rotates local up toward -X --
## `n.rotation.z = deg_to_rad(10); n.transform.basis.y` prints
## approximately (-0.17, 0.98, 0). "Roll toward the wall" (the phase's stated
## intent, and the Mirror's Edge / Titanfall convention it cites) means a
## wall on the right (side=+1, +X) must tilt the up vector's X component
## POSITIVE -- into the wall -- which requires a NEGATIVE rotation.z, the
## opposite of the naive `roll_deg * wall_side` sign.
func test_the_camera_rolls_toward_the_wall_side() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	rig.set_wall_side(1)
	for i in 60:
		rig.update_effects(TICK, 8.0, false)
	var right_roll := rig.rotation.z
	# Pinned against the CONFIGURED angle, not just "moved the right way" --
	# a roll capped at one frame's worth of motion (e.g. a lerp reset every
	# tick, the same class of bug update_effects()'s eye_height re-apply has
	# already produced once in this file) would still pass a direction-only
	# check. Negative: see the derivation above.
	check_approx(right_roll, -deg_to_rad(cfg.wall_camera_roll_deg), 0.001, "roll did not settle at the configured angle for a wall on the right")
	var right_up: Vector3 = rig.transform.basis.y
	check_greater(right_up.x, 0.0, \
		"a wall on the right must roll the camera's up vector toward +X (into the wall), got up.x = %f" % right_up.x)

	rig.set_wall_side(-1)
	for i in 120:
		rig.update_effects(TICK, 8.0, false)
	var left_roll := rig.rotation.z
	check_approx(left_roll, deg_to_rad(cfg.wall_camera_roll_deg), 0.001, "roll did not settle at the configured angle for a wall on the left")
	check(right_roll * left_roll < 0.0, "the two wall sides must roll opposite ways")
	var left_up: Vector3 = rig.transform.basis.y
	check(left_up.x < 0.0, \
		"a wall on the left must roll the camera's up vector toward -X (into the wall), got up.x = %f" % left_up.x)

	rig.set_wall_side(0)
	for i in 200:
		rig.update_effects(TICK, 0.0, true)
	check_approx(rig.rotation.z, 0.0, 0.001, "roll must return to level")

	rig.queue_free()
	await step(1)

func test_roll_and_pitch_compose_without_clobbering() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	var body := Node3D.new()
	tree.root.add_child(body)
	await step(1)

	rig.apply_look(Vector2(0.0, -200.0), body)
	var pitch_after_look := rig.rotation.x
	check_greater(absf(pitch_after_look), 0.001, "look did not pitch the camera")

	rig.set_wall_side(1)
	for i in 60:
		rig.update_effects(TICK, 8.0, false)
	check_approx(rig.rotation.x, pitch_after_look, 0.0001, "roll clobbered the pitch set by apply_look")
	check_greater(absf(rig.rotation.z), 0.01, "roll did not apply alongside an existing pitch")

	# And the reverse direction: a look input made AFTER the roll has settled
	# must not clobber it either.
	var roll_after_wall := rig.rotation.z
	rig.apply_look(Vector2(0.0, -50.0), body)
	check_approx(rig.rotation.z, roll_after_wall, 0.0001, "a look input clobbered the settled wall roll")

	rig.queue_free()
	body.queue_free()
	await step(1)

func test_reset_state_clears_camera_roll() -> void:
	var cfg := MovementConfig.new()
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	rig.set_wall_side(1)
	for i in 60:
		rig.update_effects(TICK, 0.0, true)
	check_greater(absf(rig.rotation.z), 0.01, "roll did not build up before reset")

	rig.reset_state()
	check_approx(rig.rotation.z, 0.0, 0.0001, "reset_state left the camera rolled")

	# The wall side itself must be cleared too, not just rotation.z: if
	# _wall_side survived reset_state() untouched, further ticks with no new
	# set_wall_side() call would roll the camera straight back toward the
	# same old tilt on their own -- a stale wall leaking into whatever state
	# follows the reset.
	for i in 60:
		rig.update_effects(TICK, 0.0, true)
	check_approx(rig.rotation.z, 0.0, 0.0001, "reset_state did not clear the wall side, the roll rebuilt on its own")

	rig.queue_free()
	await step(1)

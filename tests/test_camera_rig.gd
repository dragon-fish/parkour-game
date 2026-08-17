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
	# Advance to (near) a bob peak so the recorded offset is clearly non-zero
	# regardless of the config's tuning values, rather than hoping a fixed
	# frame count happens to land away from a zero crossing.
	#
	# The peak must also land AFTER bob_weight has fully faded in (see
	# MovementConfig.bob_fade_speed): bob_weight ramps in independently of
	# bob_frequency, at a fixed per-tick rate, so a high enough bob_frequency
	# reaches its first phase peak in fewer frames than the weight fade-in
	# takes -- sampling THAT peak would read an offset still scaled down by a
	# mid-fade weight, not the full-amplitude offset this test means to
	# check. Keep walking forward by whole cycles until the candidate peak
	# frame is past the weight's saturation point.
	var phase_step := TICK * cfg.bob_frequency * speed
	var weight_saturation_frames := ceilf(1.0 / (cfg.bob_fade_speed * TICK))
	var frames_to_peak := int(round((PI / 2.0) / phase_step))
	while frames_to_peak < weight_saturation_frames:
		frames_to_peak += int(round((2.0 * PI) / phase_step))
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

## Direct proportionality, not just "a bigger strength moves it more": with
## no other camera effect in play (grounded speed 0, no landing, no crouch,
## no wall), update_effects() reduces to `position = eye_height.lerp(head,
## strength)`, so the OFFSET from the strength=0 baseline must equal
## `(head - eye_height) * strength` exactly, for more than one strength
## value. A test that only checked "offset grows with strength" could still
## pass a head-follow that saturates, or one silently scaled by something
## other than the configured value (e.g. hardcoded to always follow at a
## fixed 50%).
func test_head_follow_offset_scales_with_configured_strength() -> void:
	var cfg := MovementConfig.new()

	# A head position clearly off in every axis, so a bug that only follows
	# (say) Y cannot hide behind a head position that happens to be pure Y.
	var head := Vector3(0.3, 1.1, -0.2)
	var baseline := Vector3(0.0, cfg.eye_height, 0.0)

	# A FRESH rig per strength value, not one rig reused across iterations:
	# update_effects() only hard-resets position.Y each call (see its own
	# comment on why); X/Z are written ONLY by the head-follow lerp, so a
	# rig that already followed the head once at strength 0.25 carries that
	# X/Z into the next iteration's starting `position` -- comparing against
	# a fixed `baseline` computed once, up front, would then be comparing
	# against a position the rig was never actually AT going into that call.
	for strength: float in [0.25, 0.6, 1.0]:
		cfg.camera_head_follow_strength = strength
		var rig := _make_rig()
		await step(1)
		rig.setup(cfg)
		rig.set_head_position(head)
		rig.update_effects(TICK, 0.0, true)
		var expected: Vector3 = baseline + (head - baseline) * strength
		check(rig.position.distance_to(expected) < 0.001, \
			"strength %f: expected position ~%s, got %s" % [strength, expected, rig.position])
		rig.queue_free()

	await step(1)

## strength = 0 must reproduce the no-body camera EXACTLY, not merely
## approximately -- see update_effects()'s own comment on why lerp(t=0.0) is
## bit-exact for this. Sampled across a moving/airborne/landing sequence, not
## just at rest: `position` (as opposed to `camera.position`, which carries
## bob/dip and is deliberately NOT what this checks) is written only by the
## eye_height reset, the crouch offset (pinned at 0 here -- set_crouch_amount()
## is never called in this test), and the head-follow lerp itself, so a
## SINGLE rig's `position` before vs. after a head position is supplied is a
## direct, bit-exact comparison with nothing else able to explain a
## difference.
func test_head_follow_at_zero_strength_matches_no_body_exactly() -> void:
	var cfg := MovementConfig.new()
	cfg.camera_head_follow_strength = 0.0
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	for i in 60:
		var speed := 6.0 if i < 40 else 0.0
		var grounded := i < 30 or i >= 45
		if i == 35:
			rig.punch_landing(cfg.land_dip_speed_ref)
		rig.update_effects(TICK, speed, grounded)
	var without_head := rig.position

	# A head position clearly off in every axis, so a bug that only zeroes
	# out ONE component (or a fixed Vector3.ZERO fallback rather than truly
	# gating on _has_head) cannot hide here.
	rig.set_head_position(Vector3(5.0, -5.0, 5.0))
	rig.update_effects(TICK, 0.0, true)
	var with_head_at_zero_strength := rig.position

	check(with_head_at_zero_strength == without_head, \
		"strength 0.0 must reproduce the no-body camera bit-for-bit, got %s vs %s" \
			% [with_head_at_zero_strength, without_head])

	rig.queue_free()
	await step(1)

## The regression this guards: update_effects() used to hard-reset only
## position.Y fresh each frame (via the eye_height re-apply) while X/Z were
## never reset, so `position = position.lerp(head, strength)` kept reading
## its OWN previous output back as input on those two axes. That is an
## exponential approach -- position_n = head + (position_0 - head) * (1 -
## strength)^n -- which converges to within millimetres of the head in
## roughly thirty frames REGARDLESS of how small `strength` is; the owner's
## bug report measured exactly this (Z landing 0.005m from the head with
## strength 0.15). A correct fix rebuilds the base position from scratch every
## frame on every axis, so the blend must land on the SAME fractional offset
## on frame 1 and hold there through frame 300, never drifting closer to the
## head. Re-introducing the accumulating form (`position = position.lerp(...)`
## with no fresh base) makes this fail at the final per-frame check, not at
## the first, since a single frame's lerp from a fresh start is
## indistinguishable from a single frame of the accumulating form -- the bug
## only shows up once there is a "previous frame" to accumulate from.
func test_head_follow_settles_at_the_configured_fraction_and_does_not_drift_toward_the_head() -> void:
	var cfg := MovementConfig.new()
	var strength := 0.15
	cfg.camera_head_follow_strength = strength
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	# Off in every axis, as in the other head-follow tests, so a bug confined
	# to one axis (e.g. only X/Z accumulate, Y stays correct because of its
	# own separate reset) cannot hide behind an axis-aligned head position.
	var head := Vector3(0.3, 1.1, -0.2)
	rig.set_head_position(head)

	var baseline := Vector3(0.0, cfg.eye_height, 0.0)
	var expected: Vector3 = baseline + (head - baseline) * strength

	for i in 300:
		rig.update_effects(TICK, 0.0, true)
		check(rig.position.distance_to(expected) < 0.001, \
			"frame %d: expected the camera to hold at the %f fraction toward the head (%s), got %s -- it drifted toward the head instead of staying at a fixed blend" \
				% [i, strength, expected, rig.position])

	# Belt and braces against the specific failure mode this test names: an
	# exponential approach would have the camera essentially AT the head by
	# now (the owner's own measurement put it 5mm away), so also assert it
	# is nowhere close.
	check_greater(rig.position.distance_to(head), 0.3, \
		"camera ended up close to the head instead of stopping at the configured fraction, got %s vs head %s" % [rig.position, head])

	rig.queue_free()
	await step(1)

## Same accumulation bug, viewed from the strength=0.0 side: a rig that keeps
## _has_head true across many frames must track a completely independent
## "never had a head" rig's `position` bit-for-bit on EVERY frame, not just
## once at the end. This exercises the fix while bob/dip/crouch are also live
## (unlike the simpler single-axis zero-strength test above), so a fix that
## only rebuilds base_position.y correctly (mirroring the pre-existing
## eye_height reset) but forgets X/Z would still show 0.0 * anything = 0.0
## here and NOT be caught -- this test instead exists to pin the composition
## with the other effects now that they all funnel through base_position
## rather than position directly.
func test_head_follow_zero_strength_tracks_the_no_head_camera_every_frame() -> void:
	var cfg := MovementConfig.new()
	cfg.camera_head_follow_strength = 0.0
	var with_head := _make_rig()
	var without_head := _make_rig()
	await step(1)
	with_head.setup(cfg)
	without_head.setup(cfg)
	with_head.set_head_position(Vector3(5.0, -5.0, 5.0))

	for i in 90:
		var speed := 6.0 if i < 60 else 0.0
		var grounded := i < 40 or i >= 55
		if i == 45:
			with_head.punch_landing(cfg.land_dip_speed_ref)
			without_head.punch_landing(cfg.land_dip_speed_ref)
		with_head.set_crouch_amount(0.5 if i > 70 else 0.0)
		without_head.set_crouch_amount(0.5 if i > 70 else 0.0)
		with_head.update_effects(TICK, speed, grounded)
		without_head.update_effects(TICK, speed, grounded)
		check(with_head.position == without_head.position, \
			"frame %d: strength 0.0 with a head attached must match a rig with no head bit-for-bit, got %s vs %s" \
				% [i, with_head.position, without_head.position])

	with_head.queue_free()
	without_head.queue_free()
	await step(1)

## Full strength (1.0) must reach the head exactly, every frame, even while a
## moving head position composes with bob/dip/crouch -- not just at a single
## static sample the way the parametrized strength test above checks it.
func test_head_follow_at_full_strength_tracks_a_moving_head_exactly() -> void:
	var cfg := MovementConfig.new()
	cfg.camera_head_follow_strength = 1.0
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	for i in 90:
		var head := Vector3(sin(float(i) * 0.1) * 0.2, 1.0 + float(i) * 0.001, cos(float(i) * 0.1) * 0.2)
		rig.set_head_position(head)
		var speed := 6.0 if i < 60 else 0.0
		var grounded := i < 40 or i >= 55
		rig.set_crouch_amount(0.5 if i > 70 else 0.0)
		rig.update_effects(TICK, speed, grounded)
		check(rig.position == head, \
			"frame %d: strength 1.0 must reach the head exactly, got %s vs head %s" % [i, rig.position, head])

	rig.queue_free()
	await step(1)

## Never having called set_head_position() at all -- the "no body attached,
## or Player never found a head/neck node" case -- must degrade the same way
## a zero strength does, not error and not silently apply some stale/default
## head position (Vector3.ZERO is a legitimate head position elsewhere in
## this file, so falling back to it here would be wrong, not merely unlucky).
func test_head_follow_degrades_without_error_when_no_head_was_ever_set() -> void:
	var cfg := MovementConfig.new()
	cfg.camera_head_follow_strength = 1.0
	var rig := _make_rig()
	await step(1)
	rig.setup(cfg)

	# No set_head_position() call anywhere above this line.
	for i in 30:
		rig.update_effects(TICK, 3.0, true)
	check_approx(rig.position.y, cfg.eye_height, 0.01, \
		"a rig that was never told about a head must keep behaving like today's stable camera")

	rig.queue_free()
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

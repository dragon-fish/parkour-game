class_name CameraRig
extends Node3D

# Everything the camera does that is not "sit on the player's head".
# Deliberately decoupled from physics: it is fed speed and grounded-ness and
# owns no movement logic of its own.

@onready var camera: Camera3D = $Camera3D

var _config: MovementConfig
var _pitch: float = 0.0
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _dip: float = 0.0
var _crouch_amount: float = 0.0
var _crouch_offset: float = 0.0
var _wall_side: int = 0
var _roll: float = 0.0

## The attached body's head/neck node position, in THIS rig's PARENT's
## (Player's) local space -- i.e. Player.to_local(head_node.global_position)
## -- as of the most recent set_head_position() call. Meaningless whenever
## _has_head is false. Driven by Player every physics tick, mirroring
## set_wall_side()/set_crouch_amount(); see update_effects()'s own use of it
## for the head-follow camera.
var _head_local_position: Vector3 = Vector3.ZERO
## True only for ticks Player actually supplied a head position -- i.e. a
## body is attached AND Player._find_head_node() matched something visible
## in it. update_effects() must gate on this rather than comparing
## _head_local_position against a sentinel: Vector3.ZERO is itself a
## perfectly legitimate head position, so treating it as "no head" would
## silently misread a real, if centred, head as absent.
var _has_head: bool = false

func setup(cfg: MovementConfig) -> void:
	_config = cfg
	position.y = cfg.eye_height
	if camera != null:
		camera.fov = cfg.fov_base

## 0 = standing, 1 = fully crouched. Driven by Player each tick.
func set_crouch_amount(amount: float) -> void:
	_crouch_amount = clampf(amount, 0.0, 1.0)

## -1 wall on the left, +1 on the right, 0 none. Driven by Player each tick
## from Player.wall_side, itself set by WallRunState. update_effects() eases
## rotation.z toward the corresponding tilt every frame.
func set_wall_side(side: int) -> void:
	_wall_side = side

## The attached body's head/neck node position, in Player's local space
## (Player.to_local(head_node.global_position)) -- see _head_local_position's
## own comment. Called by Player every tick a head is available.
func set_head_position(local_position: Vector3) -> void:
	_head_local_position = local_position
	_has_head = true

## Called by Player every tick NO head is available -- no body attached, or
## the attached body has nothing _find_head_node() could match. Must be
## called explicitly rather than relying on a timeout: a stale _has_head left
## true from a body that has since gone away would otherwise keep blending
## toward a head position nothing is updating any more.
func clear_head_position() -> void:
	_has_head = false

## Levels the view and clears landing/bob state. Called on a manual reset
## (Arena's R key) so the camera snaps back to a fresh-spawn look instead of
## keeping whatever pitch, landing dip, or bob phase it had the instant
## before the reset.
func reset_state() -> void:
	_pitch = 0.0
	_dip = 0.0
	_bob_phase = 0.0
	_crouch_amount = 0.0
	_crouch_offset = 0.0
	_wall_side = 0
	_roll = 0.0
	_has_head = false
	rotation.x = 0.0
	rotation.z = 0.0
	if camera != null:
		camera.position.y = 0.0

## Yaw turns the body so movement follows the view; pitch stays on the rig.
func apply_look(look_delta: Vector2, body: Node3D) -> void:
	if _config == null:
		return
	body.rotate_y(-look_delta.x * _config.mouse_sensitivity)
	var limit := deg_to_rad(_config.pitch_limit_deg)
	_pitch = clampf(_pitch - look_delta.y * _config.mouse_sensitivity, -limit, limit)
	rotation.x = _pitch

func update_effects(delta: float, horizontal_speed: float, grounded: bool) -> void:
	if _config == null or camera == null:
		return

	# Where the rig would sit this frame with NO head-follow applied,
	# recomputed from scratch every call rather than read back from last
	# frame's `position`. This is what makes camera_head_follow_strength mean
	# the same thing on every axis: previously only Y got a fresh base (via
	# the eye_height re-apply below) while X/Z inherited whatever the PREVIOUS
	# frame's lerp already blended them to, so the head-follow lerp at the
	# bottom of this function was blending toward the head from an
	# ever-more-converged starting point on X/Z -- an exponential approach to
	# the head regardless of how small `strength` was, even though Y (reset
	# fresh every frame) genuinely held at the configured fraction. Composing
	# every other contribution below into `base_position` instead of `position`
	# keeps that guarantee on all three axes: `position` itself is written
	# exactly once, at the very end of this function.
	var base_position := Vector3.ZERO
	base_position.y = _config.eye_height

	var speed_ratio := clampf(horizontal_speed / maxf(_config.fov_speed_ref, 0.001), 0.0, 1.0)

	var target_fov := lerpf(_config.fov_base, _config.fov_max, speed_ratio)
	camera.fov = lerpf(camera.fov, target_fov, clampf(_config.fov_lerp_speed * delta, 0.0, 1.0))

	var bob_target := 1.0 if grounded else 0.0
	_bob_weight = move_toward(_bob_weight, bob_target, _config.bob_fade_speed * delta)

	if grounded:
		_bob_phase += delta * _config.bob_frequency * horizontal_speed
	# The phase freezes while airborne, so the offset it produces here holds
	# steady from the moment of leaving the ground; _bob_weight is what fades
	# it toward zero instead of letting it vanish in a single frame.
	var bob := sin(_bob_phase) * _config.bob_amplitude * speed_ratio * _bob_weight

	_dip = move_toward(_dip, 0.0, _config.land_dip_recover * delta)
	camera.position.y = bob - _dip

	# Tracked as an offset independent of base_position.y (mirroring _dip
	# above) rather than lerping base_position.y toward a target directly:
	# base_position.y is freshly set to the live eye_height a few lines up,
	# every frame, so the F1 panel's slider stays instant. Lerping
	# base_position.y itself would get reset to eye_height before move_toward
	# ever got a chance to build on the previous frame's progress, capping the
	# visible drop at a single frame's worth of movement no matter how long
	# the slide lasted. A persistent offset (_crouch_offset, a plain float
	# member that DOES survive frame to frame, unlike base_position) survives
	# that reset and actually eases across crouch_lerp_speed.
	var target_offset := _config.slide_camera_drop * _crouch_amount
	_crouch_offset = move_toward(_crouch_offset, target_offset, _config.crouch_lerp_speed * delta)
	base_position.y -= _crouch_offset

	# Blend the eye position toward the attached body's head/neck node, LAST
	# among the base_position.* writes above -- lerp(t=0.0) returns
	# `base_position` bit-for-bit (Vector3.lerp is exactly a + (b-a)*t, and
	# any finite delta times 0.0 is exactly 0.0 in IEEE 754), which is what
	# makes camera_head_follow_strength == 0.0 degrade to EXACTLY today's
	# camera rather than merely close to it -- and _has_head being false (no
	# body, or nothing in it matched _find_head_node()) takes the plain
	# `position = base_position` branch below, the same guarantee. Blending
	# FROM base_position (recomputed above, this frame, from nothing) rather
	# than from the previous frame's `position` is what keeps this a one-shot
	# fraction instead of an exponential approach: `position` is read here
	# only as the assignment target, never as an input. Deliberately no
	# move_toward/easing layer of its own: the attached body's own
	# AnimationPlayer already supplies whatever motion this tracks, and the
	# strength dial is meant to scale that directly, not add a second lag on
	# top of it. Clamped independently of whatever range the F1 panel's
	# slider can reach (see MovementConfig.camera_head_follow_strength's own
	# comment on why its range and this clamp can disagree) so a value pushed
	# past 1.0 can never overshoot past the bone's own position.
	if _has_head:
		var strength := clampf(_config.camera_head_follow_strength, 0.0, 1.0)
		position = base_position.lerp(_head_local_position, strength)
	else:
		position = base_position

	# rotation.z, unlike position.y above, is never hard-reset elsewhere in
	# this function, so a plain move_toward accumulates correctly frame to
	# frame instead of needing the offset workaround the crouch drop uses.
	#
	# SIGN, verified empirically against this exact Godot build rather than
	# assumed (see the verification script referenced in the phase-final-
	# fixes report): a positive rotation.z rotates local up toward -X --
	# `n.rotation.z = deg_to_rad(10); n.transform.basis.y` prints
	# (-0.17, 0.98, 0). So a plain `roll_deg * wall_side` (positive for
	# wall_side=+1, a wall on the right) tilts the head's up vector toward -X,
	# i.e. LEFT -- away from a wall on the right, not into it. "Roll toward
	# the wall" (the phase's own stated intent, and the Mirror's Edge /
	# Titanfall convention it cites) needs the OPPOSITE sign: negated here so
	# wall_side=+1 (right) produces a NEGATIVE rotation.z, whose up vector
	# tilts toward +X -- into the wall on the right -- and wall_side=-1
	# (left) produces a positive rotation.z, tilting toward -X into the wall
	# on the left. tests/test_camera_rig.gd's
	# test_the_camera_rolls_toward_the_wall_side pins this against the
	# camera's own world-space up vector, not just "the two sides are
	# opposite" (which an inverted-but-still-symmetric roll would also pass).
	var target_roll := -deg_to_rad(_config.wall_camera_roll_deg) * float(_wall_side)
	_roll = move_toward(_roll, target_roll, deg_to_rad(_config.wall_camera_roll_speed) * delta)
	rotation.z = _roll

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.land_dip_max)

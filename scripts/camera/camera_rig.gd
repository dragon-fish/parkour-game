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

	# Re-applied every frame (not just once in setup()) so dragging the F1
	# panel's eye_height slider moves the view immediately, the same as every
	# other camera value here.
	position.y = _config.eye_height

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

	# Tracked as an offset independent of position.y (mirroring _dip above)
	# rather than lerping position.y toward a target directly: position.y is
	# hard-set to the live eye_height a few lines up, every frame, so the F1
	# panel's slider stays instant. Lerping position.y itself would get reset
	# to eye_height before move_toward ever got a chance to build on the
	# previous frame's progress, capping the visible drop at a single frame's
	# worth of movement no matter how long the slide lasted. A persistent
	# offset survives that reset and actually eases across crouch_lerp_speed.
	var target_offset := _config.slide_camera_drop * _crouch_amount
	_crouch_offset = move_toward(_crouch_offset, target_offset, _config.crouch_lerp_speed * delta)
	position.y -= _crouch_offset

	# rotation.z, unlike position.y above, is never hard-reset elsewhere in
	# this function, so a plain move_toward accumulates correctly frame to
	# frame instead of needing the offset workaround the crouch drop uses.
	var target_roll := deg_to_rad(_config.wall_camera_roll_deg) * float(_wall_side)
	_roll = move_toward(_roll, target_roll, deg_to_rad(_config.wall_camera_roll_speed) * delta)
	rotation.z = _roll

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.land_dip_max)

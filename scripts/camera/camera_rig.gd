class_name CameraRig
extends Node3D

# Everything the camera does that is not "sit on the player's head".
# Deliberately decoupled from physics: it is fed speed and grounded-ness and
# owns no movement logic of its own.

@onready var camera: Camera3D = $Camera3D

var _config: MovementConfig
var _pitch: float = 0.0
var _bob_phase: float = 0.0
var _dip: float = 0.0

func setup(cfg: MovementConfig) -> void:
	_config = cfg
	if camera != null:
		camera.fov = cfg.fov_base

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

	var speed_ratio := clampf(horizontal_speed / maxf(_config.fov_speed_ref, 0.001), 0.0, 1.0)

	var target_fov := lerpf(_config.fov_base, _config.fov_max, speed_ratio)
	camera.fov = lerpf(camera.fov, target_fov, clampf(_config.fov_lerp_speed * delta, 0.0, 1.0))

	var bob := 0.0
	if grounded:
		_bob_phase += delta * _config.bob_frequency * horizontal_speed
		bob = sin(_bob_phase) * _config.bob_amplitude * speed_ratio

	_dip = move_toward(_dip, 0.0, _config.land_dip_recover * delta)
	camera.position.y = bob - _dip

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.land_dip_max)

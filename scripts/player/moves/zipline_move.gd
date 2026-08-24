class_name ZiplineMove
extends Move

# The original's TdMove_ZipLine. 05 §5.5.
#
# NOT A ScriptedMove. That base walks a fixed path in a fixed time; a zipline
# has neither. Its speed is integrated -- at least min_velocity, gaining at
# least min_acceleration every second and more on a slope, with no cap -- so
# how long the ride takes falls out of the cable's length and grade. Same
# reasoning IntoGrabMove gives for itself: the duration is a consequence.
#
# PHYS_Flying: the body is placed directly from the cable, every tick, and
# move_and_slide() is never called. Whatever the cable crosses, the body
# crosses.

var _line: InterestLine = null
## Arc length along the cable, metres.
var _s: float = 0.0
## Speed along the cable, m/s, always >= cfg.min_velocity.
var _v: float = 0.0
## This tick's acceleration, kept for the HUD.
var _a: float = 0.0
## +1 rides toward increasing offset, -1 toward decreasing.
var _dir: float = 1.0
var _fade: float = 0.0
var _entry_pos: Vector3 = Vector3.ZERO
var _entry_yaw: float = 0.0
var _target_yaw: float = 0.0
var _aborted: bool = false

func enter(_previous: StringName) -> void:
	# Declared, not read: this move never calls move_and_slide().
	player.set_grounded(false)
	_aborted = false
	_line = player.nearest_interest_line(InterestLine.Kind.ZIPLINE)
	if _line == null:
		_aborted = true
		return
	_s = _line.closest_offset(player.global_position)
	# Away from the nearer end. A cable is caught from the end you arrive at,
	# and that holds for a sagging one too.
	_dir = 1.0 if _s < _line.length() * 0.5 else -1.0
	var along: Vector3 = _tangent()
	# Momentum carried onto the cable, floored -- MinZipVelocity.
	_v = maxf(cfg.min_velocity, player.velocity.dot(along))
	# Computed here rather than left for the first physics_update(), so a
	# reader of ride_acceleration() on the very catch tick (before this move's
	# own physics_update has run once) already sees the real grade-driven
	# figure instead of a placeholder zero. Same formula physics_update() uses.
	_a = maxf(cfg.min_acceleration, -config.pawn.gravity * along.y)
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	_entry_yaw = player.rotation.y
	_target_yaw = atan2(-along.x, -along.z)

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	player.set_grounded(false)
	if input.crouch_pressed:
		return _release()

	var along: Vector3 = _tangent()
	# Downhill is along.y < 0. A level or rising stretch is caught by the
	# floor -- MinZipAcceleration -- so the far side of a sag never stalls.
	_a = maxf(cfg.min_acceleration, -config.pawn.gravity * along.y)
	_v = maxf(_v + _a * delta, cfg.min_velocity)
	_s += _dir * _v * delta
	if _s <= 0.0 or _s >= _line.length():
		return _release()

	var hang: Vector3 = _hang_point()
	_fade += delta
	if _fade < cfg.fade_in_time:
		var t: float = _fade / cfg.fade_in_time
		player.global_position = _entry_pos.lerp(hang, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		player.global_position = hang
		_turn_body_to(_target_yaw)
	return KEEP

func _release() -> StringName:
	# Momentum kept in full, nothing added: the owner's call is "蹲=松手，保持
	# 空速坠下去；不能跳".
	player.velocity = _tangent() * _v
	return FALLING

## The direction of travel, unit length, in world space.
func _tangent() -> Vector3:
	return _line.sample(_s)["tangent"] * _dir

func _hang_point() -> Vector3:
	return _line.sample(_s)["position"] - Vector3.UP * cfg.hang_offset

## Sets the body yaw and hands the camera the change, so the eye trails the
## turn instead of being cut through it -- the same courtesy IntoGrabMove pays.
func _turn_body_to(yaw: float) -> void:
	var before: float = player.rotation.y
	player.rotation.y = yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(yaw - before, -PI, PI))
		if yaw == _target_yaw:
			player.camera_rig.recentre_yaw_reference(yaw)

# --- read by the HUD and by tests ------------------------------------------

func ride_speed() -> float:
	return _v

func ride_offset() -> float:
	return _s

func ride_acceleration() -> float:
	return _a

func line() -> InterestLine:
	return _line

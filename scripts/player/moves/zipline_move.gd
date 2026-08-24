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
## The cable's horizontal direction AT THIS TICK'S offset. Recomputed every
## tick: 05 §5 step 6 asks the body to face along `t`, and a sagging or curving
## cable does not point where it did at the catch. Straight cables make this a
## no-op, which is why the arena's own does not exercise it.
var _cable_yaw: float = 0.0
## Where the look fan is centred. Follows _cable_yaw, but only ever through
## shift_yaw_reference() -- see _track_fan_to_cable().
var _fan_yaw: float = 0.0
## Set the tick the fade ends, when the fan is centred on the cable. Guards a
## call that MUST happen once; see _centre_fan().
var _fan_centred: bool = false
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
	_fan_centred = false
	_cable_yaw = _yaw_along(along)
	_fan_yaw = _cable_yaw

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
	_cable_yaw = _yaw_along(along)
	_fade += delta
	if _fade < cfg.fade_in_time:
		var t: float = _fade / cfg.fade_in_time
		player.global_position = _entry_pos.lerp(hang, t)
		_turn_body_to(lerp_angle(_entry_yaw, _cable_yaw, t))
	else:
		player.global_position = hang
		if not _fan_centred:
			_centre_fan()
		else:
			_track_fan_to_cable()
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

## The yaw that faces along `direction`. Body forward is -Z, so rotating
## (0, 0, -1) by yaw gives (-sin, 0, -cos): facing d means atan2(-d.x, -d.z).
func _yaw_along(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

## Sets the body yaw, hands the camera the change so the eye trails the turn
## instead of being cut through it, and takes the model along.
##
## THE FADE-IN ONLY. Once the body is on the cable its yaw is the PLAYER's --
## see _centre_fan() for why this move must stop writing it.
func _turn_body_to(yaw: float) -> void:
	var before: float = player.rotation.y
	player.rotation.y = yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(yaw - before, -PI, PI))
	# ZiplineConfig freezes the visual yaw -- both hands are on the cable, so
	# the model must not swivel to follow the view -- and that freeze cancels
	# this turn degree for degree unless the model is told where to face. Same
	# arrangement GrabMove makes at a ledge corner; see Player.pin_visual_yaw().
	player.pin_visual_yaw(yaw)

## Ends the fade: squares the body up to the cable and centres the +-90 degree
## fan on it, so "look 90 degrees off" means 90 degrees off THE CABLE rather
## than off whatever heading the jump happened to arrive with.
##
## ⚠️ ONCE, AND THAT IS THE ENTIRE POINT. recentre_yaw_reference() re-derives
## how far the view has turned from the fan's centre out of the BODY's facing.
## Called every tick with a body this move had just written to the cable's yaw,
## that difference is zero every tick -- and what it zeroes is the mouse yaw
## apply_look() accumulated a few microseconds earlier, since Player runs the
## look before the moves. The ride could not be looked out of at all and the
## config's +-90 fan never applied to anything. WallRunMove guards the same
## call with its own _fan_centred flag, for the same reason.
##
## From here the body's yaw belongs to apply_look(), which rebuilds it every
## tick as fan centre plus the player's own accumulated turn, clamped to the
## fan. This move writes rotation.y no more.
func _centre_fan() -> void:
	_fan_centred = true
	_fan_yaw = _cable_yaw
	# Not through _turn_body_to(): the fade has already brought the facing to
	# within a rounding error of the cable, so what is left is a snap to exact.
	var before: float = player.rotation.y
	player.rotation.y = _fan_yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(_fan_yaw - before, -PI, PI))
		player.camera_rig.recentre_yaw_reference(_fan_yaw)
	player.pin_visual_yaw(_fan_yaw)

## Carries the fan -- and the model -- round with a cable that turns.
##
## The fan is measured against the CABLE's own direction, so on a sagging or
## curving cable it has to turn with it, or the clamp ends up policing a
## direction the cable stopped pointing in metres ago. The same job
## WallRunMove._track_fan_to_wall() does for a curved wall.
##
## shift_yaw_reference(), NOT recentre_yaw_reference(): moving the fan's centre
## must not re-derive the player's accumulated turn from the body, or every
## metre of curve would quietly re-zero their view -- finding 1 again, spread
## thin. `assist` is 1.0 because both hands are on the cable: the view keeps the
## angle to it the player chose, exactly as a ledge corner carries the view
## round with the wall. No smoothing of the tracking itself is needed -- a
## Curve3D tangent is continuous, so the per-tick turn is already a sliver.
func _track_fan_to_cable() -> void:
	var difference: float = wrapf(_cable_yaw - _fan_yaw, -PI, PI)
	if is_zero_approx(difference):
		return
	_fan_yaw = _cable_yaw
	if player.camera_rig != null:
		player.camera_rig.shift_yaw_reference(_fan_yaw, 1.0)
	player.pin_visual_yaw(_fan_yaw)

# --- read by the HUD and by tests ------------------------------------------

func ride_speed() -> float:
	return _v

func ride_offset() -> float:
	return _s

func ride_acceleration() -> float:
	return _a

func line() -> InterestLine:
	return _line

# --- debug view ------------------------------------------------------------
#
# The F12 overlay (ScriptedPathDebug) draws any move that can sample itself.
# `t` here is the fraction of the CABLE, not of time: the ride has no duration.

func sample(t: float) -> Vector3:
	if not is_instance_valid(_line):
		return player.global_position
	return _line.sample(t * _line.length())["position"] - Vector3.UP * cfg.hang_offset

func path_debug() -> Dictionary:
	if _aborted or not is_instance_valid(_line):
		return {}
	var total: float = _line.length()
	var from: Vector3 = sample(0.0)
	var to: Vector3 = sample(1.0)
	return {"from": from, "to": to, "progress": _s / total,
		"lead": 0.0, "arc": 0.0, "duration": 0.0,
		"peak": maxf(from.y, to.y)}

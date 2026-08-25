class_name ZiplineMove
extends LineMove

# The original's TdMove_ZipLine. 05 §5.5.
#
# NOT A ScriptedMove. That base walks a fixed path in a fixed time; a zipline
# has neither. Its speed is integrated -- at least min_velocity, growing at a
# constant, owner-measured rate (about 10 km/h per second), with no cap -- so
# how long the ride takes falls out of the cable's length and grade. Same
# reasoning IntoGrabMove gives for itself: the duration is a consequence.
#
# PHYS_Flying: the body is placed from the cable every tick, never through
# move_and_slide(). Only the STEADY ride is collision-checked (slide_to()
# below) -- because designers sink cable ends into walls on purpose, and a
# rider who never lets go must be thrown off there, not carried through. The
# 0.1 s magnet fade onto the cable stays a direct write on purpose: brushing
# geometry during the pull must not abort the catch.

## Arc length along the cable, metres.
var _s: float = 0.0
## Speed along the cable, m/s, always >= cfg.min_velocity.
var _v: float = 0.0
## This tick's acceleration, kept for the HUD.
var _a: float = 0.0
## +1 rides toward increasing offset, -1 toward decreasing.
var _dir: float = 1.0
## The cable's horizontal direction AT THIS TICK'S offset. Recomputed every
## tick: 05 §5 step 6 asks the body to face along `t`, and a sagging or curving
## cable does not point where it did at the catch. Straight cables make this a
## no-op, which is why the arena's own does not exercise it.
var _cable_yaw: float = 0.0

## The direction a ride boarded at `offset` travels: +1 toward increasing arc
## length, -1 toward decreasing. THE ONLY COPY OF THE RULE -- enter() derives
## _dir from it and the entry gate asks it through travel_direction() below;
## a second copy would let the two disagree about which rides exist.
##
## ✅ THE OWNER: "从低点朝高点方向跳起触发绳索，会逆着高度滑上去，甚至还会
## 逐渐加速" -- that ride must not exist. A zipline is one-way: the original's
## cables all descend, and the min-acceleration floor exists to carry the far
## half of a SAG, not to power a climb. So travel is toward the LOWER
## endpoint; a level cable (no lower end) falls back to "away from the end
## you arrived at".
static func travel_sign(line: InterestLine, offset: float) -> float:
	var start_y: float = line.sample(0.0)["position"].y
	var end_y: float = line.sample(line.length())["position"].y
	if absf(start_y - end_y) > 0.01:
		return 1.0 if end_y < start_y else -1.0
	return 1.0 if offset < line.length() * 0.5 else -1.0

## The unit world direction a ride caught at `world_pos` would travel in --
## what AirborneMove's entry gate compares the approach against.
static func travel_direction(line: InterestLine, world_pos: Vector3) -> Vector3:
	var s: float = line.closest_offset(world_pos)
	return line.sample(s)["tangent"] * travel_sign(line, s)

func enter(_previous: StringName) -> void:
	# Declared, not read: this move never calls move_and_slide().
	player.set_grounded(false)
	if not acquire_line(InterestLine.Kind.ZIPLINE):
		return
	_s = _line.closest_offset(player.global_position)
	_dir = travel_sign(_line, _s)
	var along: Vector3 = _tangent()
	# ✅ THE OWNER, measured in the original: the entry speed is the GROUND
	# speed at the last take-off -- "即便中途蹬墙跳了一段，进入绳子的瞬间速度回变
	# 回18km/h", and a second rope resets to the same figure. Not the current
	# airspeed, not a projection. Floored by MinZipVelocity as before.
	_v = maxf(cfg.min_velocity, player.takeoff_ground_speed())
	_a = _acceleration_for(along)
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	_entry_yaw = player.rotation.y
	_fan_centred = false
	_cable_yaw = _yaw_along(along)
	_target_yaw = _cable_yaw

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	player.set_grounded(false)
	# ✅ THE OWNER: 摔落高度从离开绳索那一刻开始计算. The cable supports the body
	# the way the ground does; FallTracker measures depth below the last spot
	# that was true, so it must be re-baselined here every tick the hands are
	# still on the wire -- otherwise a long descending ride racks up its own
	# drop as "fall" before the hands ever let go, and can even score a fatal
	# one the instant they do. The landing thresholds themselves (hard_landing
	# _height, the fatal tier) are untouched -- only where the count starts.
	player.fall_tracker.reset(player.global_position.y)
	if input.crouch_pressed:
		# ✅ THE OWNER: "在ME里按一次按键只对应一次动作" -- this press already
		# spends itself letting go of the cable, so it must not also survive in
		# the roll buffer (armed unconditionally by Player._tick_timers() on
		# every crouch_pressed) to fire a skill roll at whatever the fall turns
		# out to be. NOT on the end-of-cable release below: reaching the end of
		# the cable involves no press at all.
		player.consume_roll()
		return _release()

	var along: Vector3 = _tangent()
	_a = _acceleration_for(along)
	_v = maxf(_v + _a * delta, cfg.min_velocity)
	_s += _dir * _v * delta
	if _s <= 0.0 or _s >= _line.length():
		return _release()

	var hang: Vector3 = _hang_point()
	_cable_yaw = _yaw_along(along)
	_fade += delta
	if _fade < cfg.fade_in_time:
		# ✅ THE CONTROLLER'S RULING (fix round 1): the magnet's own pull stays
		# a direct write, not collision-checked. Routing this through slide_to
		# meant brushing any geometry during the 0.1 s fade aborted the catch
		# outright -- "touched the rope but got bounced off" -- exactly the
		# UX the magnet exists to prevent. Geometry only claims the rider once
		# they are actually RIDING (see the slide_to below); the owner's
		# "滑到底忘记放手撞到墙被弹出去了" is about a rider who never lets go
		# of a cable already being ridden, not a body still fading onto one.
		var t: float = _fade / cfg.fade_in_time
		player.global_position = _entry_pos.lerp(hang, t)
		_turn_body_to(lerp_angle(_entry_yaw, _cable_yaw, t))
	else:
		# ✅ THE OWNER, on the original: "滑到底忘记放手撞到墙被弹出去了" -- a
		# cable whose path runs through solid geometry (designers deliberately
		# sink cable ends into walls) must throw the rider off AT the wall,
		# never carry the capsule through it, once the ride is underway.
		var hit := slide_to(hang)
		if hit != null:
			player.velocity = (_tangent() * _v).slide(hit.get_normal())
			return FALLING
		if not _fan_centred:
			_target_yaw = _cable_yaw
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
	var difference: float = wrapf(_cable_yaw - _target_yaw, -PI, PI)
	if is_zero_approx(difference):
		return
	_target_yaw = _cable_yaw
	if player.camera_rig != null:
		player.camera_rig.shift_yaw_reference(_target_yaw, 1.0)
	player.pin_visual_yaw(_target_yaw)

func exit() -> void:
	note_left(cfg.same_line_redo_time)

## The measured growth law: linear in the descent slope. ✅ THE OWNER, off two
## reference segments in the original (see ZiplineConfig.base_acceleration):
## a = base + gain * sin(descent). Uphill is unmeasured -- the linear form is
## extrapolated there and floored at zero; min_velocity keeps the ride moving
## through any rising stretch of a sag either way.
func _acceleration_for(along: Vector3) -> float:
	return maxf(cfg.base_acceleration + cfg.slope_acceleration * (-along.y), 0.0)

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

## The CABLE point, not the hang point: F12 draws the rope where it physically
## is. The body hangs hang_offset BELOW this -- the capsule's top rides the
## wire -- which is also why this must not subtract hang_offset the way
## _hang_point() does; that would draw the line right on top of the body
## instead of showing the owner the cable they mistook it for.
func sample(t: float) -> Vector3:
	if not is_instance_valid(_line):
		return player.global_position
	return _line.sample(t * _line.length())["position"]

func path_debug() -> Dictionary:
	if _aborted or not is_instance_valid(_line):
		return {}
	var total: float = _line.length()
	var from: Vector3 = sample(0.0)
	var to: Vector3 = sample(1.0)
	return {"from": from, "to": to, "progress": _s / total,
		"lead": 0.0, "arc": 0.0, "duration": 0.0,
		"peak": maxf(from.y, to.y)}

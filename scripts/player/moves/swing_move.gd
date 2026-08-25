class_name SwingMove
extends Move

# The original's TdMove_Swing (05 §5.5b): a 1.2 m pendulum the player pumps
# with W/S and leaves at any phase. NOT a ScriptedMove -- the angle is
# integrated, not keyed -- and, like the zipline, the body is placed directly
# every tick (PHYS_Flying).
#
# ✅ THE OWNER's two ME-measured noob compensations shape both ends of it:
#   attach  "快要碰到横杆的时候，会帮你吸附上去" -- the volume catch plus a
#           short pull onto the chain (enter()).
#   exit    "只要摇晃的角速度超过一定值（很宽松）并且身体是往前摆时，就能跳出
#           去并且飞出去的角度每次都一样" -- Task 4's fixed-angle launch.

var _line: InterestLine = null
## The fixed point on the bar the pendulum hangs from (world). Chosen at the
## catch and never slid: a swing is planar.
var _pivot: Vector3 = Vector3.ZERO
## The swing plane's horizontal "forward" (unit, perpendicular to the bar).
var _forward: Vector3 = Vector3.FORWARD
## Pendulum angle: 0 hangs straight down, positive swings toward _forward.
var _theta: float = 0.0
## Angular velocity, rad/s, positive toward _forward.
var _omega: float = 0.0
var _fade: float = 0.0
var _entry_pos: Vector3 = Vector3.ZERO
## Body yaw at the catch, and the swing plane's own yaw -- the fade turns
## between the two instead of snapping, same shape as ZiplineMove's
## _entry_yaw/_cable_yaw pair.
var _entry_yaw: float = 0.0
var _target_yaw: float = 0.0
## Set the tick the fade ends, when the look fan is centred on the swing
## plane. Guards a call that must happen once -- see ZiplineMove's own
## _fan_centred note on why recentre_yaw_reference() cannot run every tick.
var _fan_centred: bool = false
var _aborted: bool = false
## Last tick's applied pump, for the HUD's pump field.
var _last_pump: float = 0.0
## Seconds of exit-jump grace left after the window was last properly open.
var _window_grace: float = 0.0

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
	_aborted = false
	_line = player.nearest_interest_line(InterestLine.Kind.SWING)
	if _line == null:
		_aborted = true
		return
	var s: float = _line.closest_offset(player.global_position)
	_pivot = _line.sample(s)["position"]
	var axis: Vector3 = _line.sample(s)["tangent"]
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		# A vertical bar is not a swing bar.
		_aborted = true
		return
	axis = axis.normalized()
	# The swing plane's forward: the horizontal entry velocity's component
	# perpendicular to the bar, or the visible facing when arriving straight
	# down. Which way you were going is which way you swing.
	var approach := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var perp: Vector3 = approach - axis * approach.dot(axis)
	if perp.length_squared() < 0.01:
		var facing: Vector3 = -player.global_transform.basis.z
		perp = facing - axis * facing.dot(axis)
	if perp.length_squared() < 0.0001:
		perp = axis.cross(Vector3.UP)
	_forward = perp.normalized()
	# Initial state read off the arrival: angle from where the body actually
	# is (clamped -- the magnet does the rest), angular velocity from the
	# tangential share of the arrival speed.
	var offset: Vector3 = player.global_position - _pivot
	# TIGHT residual angle and absorbed momentum -- ✅ the owner, on the first
	# cut's 25-degree clamp and full carry-over: "原地起跳上杆都能晃老高."
	var max_theta: float = deg_to_rad(cfg.entry_max_theta_deg)
	_theta = clampf(atan2(offset.dot(_forward), -offset.y), -max_theta, max_theta)
	_omega = approach.dot(_forward) / cfg.pendulum_length * cfg.entry_omega_scale
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	# Turned ACROSS the fade below, not here -- see _turn_body_to()/
	# _centre_fan(). Snapping the yaw in this one tick was the review's
	# second finding.
	_entry_yaw = player.rotation.y
	_target_yaw = atan2(-_forward.x, -_forward.z)
	_fan_centred = false
	_window_grace = 0.0

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	player.set_grounded(false)
	# The bar supports the body the way the ground does -- the fall the
	# landing charges for starts where the hands let go (same rule the
	# zipline settled).
	player.fall_tracker.reset(player.global_position.y)

	# THE EXIT JUMP -- lenient and fixed-angle, ✅ the owner's ME measurement:
	# "只要摇晃的角速度超过一定值（很宽松）并且身体是往前摆时，就能跳出去并且
	# 飞出去的角度每次都一样." An out-of-window press is IGNORED, not spent.
	if input.jump_pressed and jump_window_open():
		var launch := (_forward * cos(deg_to_rad(cfg.exit_angle_deg))
			+ Vector3.UP * sin(deg_to_rad(cfg.exit_angle_deg)))
		player.velocity = launch * cfg.exit_speed
		player.apply_gravity_window(cfg.exit_gravity_multiplier, cfg.exit_gravity_time)
		return FALLING
	if input.crouch_pressed:
		# The drop keeps the swing's own velocity, under the same soft-landing
		# gravity window (both CDO pairs carry it).
		player.velocity = (_forward * cos(_theta) + Vector3.UP * sin(_theta)) \
			* tangential_speed()
		player.apply_gravity_window(cfg.exit_gravity_multiplier, cfg.exit_gravity_time)
		# One press, one action -- the same rule the zipline settled.
		player.consume_roll()
		return FALLING

	# THE PENDULUM. Gravity torque plus the pump: W adds angular acceleration
	# only when pushed WITH the current motion (pumping against the swing
	# would be free braking nobody asked for), S the mirror.
	var pump: float = 0.0
	var wish: float = input.move.y
	if absf(wish) > 0.1:
		if absf(_omega) <= 0.01:
			# PUMPING FROM REST IS ALLOWED. A straight-up catch with no
			# drift lands exactly on theta=0, omega=0 -- gravity torque
			# (sin(0)) is zero there too, so without this branch the guard
			# below turned the most ordinary approach into a dead fixed
			# point, escapable only by letting go. The guard's job was only
			# to stop counter-motion input from braking an EXISTING swing;
			# from rest there is no motion to counter.
			pump = cfg.pump_accel * signf(wish)
		elif signf(wish) == signf(_omega):
			pump = cfg.pump_accel * signf(_omega)
	_last_pump = pump
	_omega += (-config.pawn.gravity / cfg.pendulum_length) * sin(_theta) * delta \
		+ pump * delta
	# Light damping: an un-pumped swing settles instead of ringing forever --
	# keeping the amplitude is what the W/S pump is FOR.
	_omega -= _omega * cfg.damping * delta
	# The apex grace: the window stays open a beat after omega falls off it,
	# so the "top of the swing, about to come back" jump still fires -- the
	# owner's feel call, and the stand-in for SwingAngleTimingOffset.
	if _omega > cfg.jump_min_omega:
		_window_grace = cfg.jump_grace_time
	else:
		_window_grace = maxf(_window_grace - delta, 0.0)
	# ✅ MaxSwingVelocity caps the TANGENTIAL speed.
	var omega_cap: float = cfg.max_swing_velocity / cfg.pendulum_length
	_omega = clampf(_omega, -omega_cap, omega_cap)
	_theta += _omega * delta

	var chain: Vector3 = _pivot \
		+ (_forward * sin(_theta) - Vector3.UP * cos(_theta)) * cfg.pendulum_length
	_fade += delta
	if _fade < cfg.fade_in_time:
		var t: float = _fade / cfg.fade_in_time
		player.global_position = _entry_pos.lerp(chain, t)
		_turn_body_to(lerp_angle(_entry_yaw, _target_yaw, t))
	else:
		player.global_position = chain
		if not _fan_centred:
			_centre_fan()
	# The model leans along the chain -- ✅ the owner, on how ME reads
	# amplitude: "主要是靠镜头里可以看到自己身体来判断." The camera is NOT
	# pitched (ME does not sync the view to the swing); Player smooths the
	# lean on and off. Sign fixed by the owner's eyes ("pitch写反了") -- the
	# first guess had the legs trailing.
	player.set_swing_pitch_target(_theta * cfg.model_pitch_follow)
	if player.camera_rig != null:
		# Forward swings only: the lean sweeps the chest through the fixed
		# eye, so the eye slides up and ahead of it (two dials -- the owner:
		# "先试试两个方向都给点"). Backswings tip the chest away.
		var lean: float = maxf(sin(_theta), 0.0)
		player.camera_rig.extra_eye_forward = lean * cfg.eye_forward_lean
		player.camera_rig.extra_eye_lift = lean * cfg.eye_lift_lean
	return KEEP

func exit() -> void:
	player.set_swing_pitch_target(0.0)
	if player.camera_rig != null:
		player.camera_rig.extra_eye_forward = 0.0
		player.camera_rig.extra_eye_lift = 0.0
	if is_instance_valid(_line):
		player.note_line_left(_line, cfg.same_line_redo_time)

## THE FADE-IN ONLY. Turns the body from its entry facing toward the swing
## plane's forward across the magnet pull, rather than snapping there in one
## tick -- same shape as ZiplineMove._turn_body_to().
func _turn_body_to(yaw: float) -> void:
	var before: float = player.rotation.y
	player.rotation.y = yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(yaw - before, -PI, PI))
	# SwingConfig freezes the visual yaw -- both hands are on the bar -- and
	# that freeze cancels this turn degree for degree unless the model is
	# told where to face.
	player.pin_visual_yaw(yaw)

## Ends the fade: squares the body up to the swing plane's forward and
## centres the look fan on it, exactly once -- see ZiplineMove's own
## _centre_fan() note on why recentre_yaw_reference() must not run every
## tick once the fade is done.
func _centre_fan() -> void:
	_fan_centred = true
	var before: float = player.rotation.y
	player.rotation.y = _target_yaw
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(wrapf(_target_yaw - before, -PI, PI))
		player.camera_rig.recentre_yaw_reference(_target_yaw)
	player.pin_visual_yaw(_target_yaw)

# --- read by the HUD, Task 4 and the tests ---------------------------------

func swing_theta() -> float:
	return _theta

func swing_omega() -> float:
	return _omega

func tangential_speed() -> float:
	return _omega * cfg.pendulum_length

func swing_forward() -> Vector3:
	return _forward

## Task 4 fills this with the lenient forward-swing window; declared here so
## the HUD line (Task 5) has one source.
func jump_window_open() -> bool:
	return _omega > cfg.jump_min_omega or _window_grace > 0.0

## -1 (S), 0, or +1 (W): the pump the last tick actually applied.
func pump_direction() -> int:
	return int(signf(_last_pump))

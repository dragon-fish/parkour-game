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
	_theta = clampf(atan2(offset.dot(_forward), -offset.y), -0.44, 0.44)
	_omega = approach.dot(_forward) / cfg.pendulum_length
	player.velocity = Vector3.ZERO
	_fade = 0.0
	_entry_pos = player.global_position
	# Turned ACROSS the fade below, not here -- see _turn_body_to()/
	# _centre_fan(). Snapping the yaw in this one tick was the review's
	# second finding.
	_entry_yaw = player.rotation.y
	_target_yaw = atan2(-_forward.x, -_forward.z)
	_fan_centred = false

func physics_update(delta: float, input: MoveInput) -> StringName:
	if _aborted or not is_instance_valid(_line):
		return FALLING
	player.set_grounded(false)
	# The bar supports the body the way the ground does -- the fall the
	# landing charges for starts where the hands let go (same rule the
	# zipline settled).
	player.fall_tracker.reset(player.global_position.y)

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
	_omega += (-config.pawn.gravity / cfg.pendulum_length) * sin(_theta) * delta \
		+ pump * delta
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
	return KEEP

func exit() -> void:
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
	return _omega > cfg.jump_min_omega

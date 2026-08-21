class_name SkillRollMove
extends Move

# The original's TdMove_SkillRoll: the roll out of a landing that would
# otherwise have cost the player everything.
#
# It is the counterpart to LandingMove, and the two are mutually exclusive by
# construction -- AirborneMove.landing_destination() sends a hard landing to
# one or the other depending on whether the crouch was pressed in time. Rolling
# is how the player buys their way out of the two-second lockout.
#
# NOT STEERABLE ONCE IT STARTS, and that is from the source: ControllerState is
# PlayerGrabbing, MovementGroup is MG_TwoHandsBusy, and bDisableFaceRotation is
# set. The hands are busy and the facing is pinned; the direction is decided at
# touchdown and the player has no say in it afterwards.
#
# But it is AIMED, and that part is the owner's find from the original: the
# direction comes from where the CAMERA points at touchdown, not from the
# momentum -- even if the player spun 180 degrees in the air on the way down.
# A deliberate break with physics, and their reading of why is convincing: a
# roll is a second of lost control, and letting the view aim it hands that
# second back. See enter().

var _elapsed: float = 0.0
## Fixed at touchdown, from the VIEW rather than from the momentum -- see
## enter(). Zero only if the facing is degenerate, which nothing produces.
var _direction: Vector3 = Vector3.ZERO
var _speed: float = 0.0
## True once the ground has run out mid-roll. The roll does NOT end there -- see
## physics_update().
var _airborne: bool = false
## How far the view turns over this roll, captured at touchdown. NOT a constant:
## it is one full turn ADJUSTED by wherever the view already was, so the roll
## always finishes level. See enter().
var _spin_total: float = 0.0

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_airborne = false
	# FIXED. NOT A FLOOR, AND NOT SCALED BY WHAT YOU ARRIVED WITH.
	#
	# ✅ The owner tested it directly in the original -- a roll from a standstill
	# and a roll at 80 km/h both travel the same 3 m. What speed buys is not
	# distance: it is the share of the energy budget that survives (energy_keep
	# below), so you get back up to pace faster afterwards.
	#
	# This project had it as maxf(carried * speed_scale, forced), which was my
	# reading of "3 m" as a minimum rather than the whole answer. That invention
	# is also what the owner measured as an over-long 3.2 m roll: the momentum
	# term, not the 3 m.
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_speed = cfg.forced_distance / maxf(cfg.duration, 0.001)
	# ALONG THE VIEW, NOT ALONG THE MOMENTUM.
	#
	# ✅ The owner, from the original: the forced travel follows where the CAMERA
	# is pointing at the instant the roll begins -- even if the player spun 180
	# degrees in mid-air on the way down. It is a deliberate break with physics,
	# and their reading of why is convincing: a roll is a second of lost control,
	# and letting the view aim it hands that second back. You steer the landing
	# instead of being carried by whatever the fall happened to leave you with.
	#
	# So this is NOT a fallback for a heading-less drop, which is what it was.
	# The heading is never consulted; only the facing is.
	# ⚠️ Catalyst rolls the other way -- along the momentum, with four directional
	# variants. See SkillRollConfig.aim_with_view for why this is a choice
	# between two shipped games rather than a fact about one.
	var aim: Vector3 = horizontal
	if cfg.aim_with_view:
		aim = -player.global_transform.basis.z
	aim.y = 0.0
	if aim.length_squared() > 0.0001:
		_direction = aim.normalized()
	else:
		# Nothing to aim by at all: a dead drop with the facing degenerate.
		var facing: Vector3 = -player.global_transform.basis.z
		facing.y = 0.0
		_direction = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO

	# THE ROLL STARTS FROM WHEREVER THE VIEW IS, AND ALWAYS ENDS LEVEL.
	#
	# ✅ The owner, from the original: the pitch is not forced to zero on entry;
	# the roll begins at the current pitch and finishes at zero, so looking UP
	# travels more than a full turn and looking DOWN travels less.
	#
	# CameraRig composes this as `rotation.x = pitch - roll_spin`, so a spin of
	# one full turn ends back at the pitch it started from -- which is what ours
	# did, and why it never levelled out. Adding the starting pitch to the total
	# makes the finish land on -TAU, which is level, and makes the DISTANCE
	# travelled TAU + pitch: more when looking up, less when looking down,
	# exactly as described.
	var pitch_at_start: float = 0.0
	if player.camera_rig != null:
		pitch_at_start = float(player.camera_rig.look_debug()["pitch"])
	_spin_total = cfg.camera_spin + pitch_at_start

	player.speed_energy.energy *= cfg.energy_keep
	player.set_capsule_height(config.crouch.crouch_capsule_height)

## Same REQUEST, not an unconditional restore, that Slide and Crouch use: a
## roll can end under something low, and standing up into a ceiling would put
## the capsule inside it. Player owes the restore and performs it as soon as
## there is room.
func exit() -> void:
	player.request_standing_capsule()
	if player.camera_rig != null:
		player.camera_rig.set_roll_spin(0.0)
		player.camera_rig.set_crouch_amount(0.0)

func physics_update(delta: float, _input: MoveInput) -> StringName:
	_elapsed += delta

	# Input is ignored entirely -- see the file header. The roll carries the
	# body along the heading it landed on.
	if _direction != Vector3.ZERO:
		player.velocity.x = _direction.x * _speed
		player.velocity.z = _direction.z * _speed
	else:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	# ROLLING OFF AN EDGE DOES NOT END THE ROLL.
	#
	# ✅ The owner, from the original: "if the ground runs out half way through,
	# the roll animation still plays out -- the body is obviously falling by
	# then, but the move finishes." Ours cut to a standing fall the instant the
	# floor disappeared, and the camera went from mid-tumble to upright in one
	# frame. Their word for it: a poor experience.
	#
	# The distinction is between the body and the ANIMATION. Gravity takes the
	# body immediately, which is honest; the roll keeps its own clock and its own
	# camera until it is done. This is the movement-side counterpart of
	# docs/camera-authority.md -- a manoeuvre interrupted by terrain plays out,
	# it does not swap the player for a different one mid-frame.
	if _airborne:
		player.velocity.y -= config.pawn.gravity * delta
		player.velocity.y = maxf(player.velocity.y, -config.pawn.terminal_velocity)
		player.move_and_slide()
		# Landing again mid-roll simply resumes the grounded path.
		_airborne = not player.is_on_floor()
		player.set_grounded(not _airborne)
	else:
		player.velocity.y = -config.pawn.floor_snap_speed
		var rise: float = player.try_step_up(delta)
		if rise > 0.0 and player.camera_rig != null:
			player.camera_rig.add_step_offset(rise)
		player.move_and_slide()
		var stepped_down: bool = player.try_step_down()
		player.set_grounded(player.is_on_floor() or stepped_down)
		if not player.grounded:
			# First tick off the edge. Hand the vertical channel to gravity from
			# here on; the floor snap above would otherwise keep driving the body
			# down at a fixed rate, which is not a fall.
			_airborne = true
			player.velocity.y = 0.0

	_drive_camera()

	if _elapsed < cfg.duration:
		return KEEP
	# The roll is spent. WHERE it leaves the player is a separate question from
	# whether it finished, and the answer is simply where the body is.
	return WALKING if player.grounded else FALLING

## The roll itself: the view goes ALL THE WAY OVER, and the eye drops through
## the middle of it.
##
## A sink-and-return was tried first and was indistinguishable from the hard
## landing this move exists to avoid -- which is the whole problem, since the
## two are the opposite outcome of the same moment. The original's own look
## clamp for this move reaches +180 degrees; going over is the manoeuvre.
##
## Eased at both ends (smoothstep) rather than linear, so the view is not
## yanked into the spin and does not stop dead at the end of it.
func _drive_camera() -> void:
	if player.camera_rig == null:
		return
	var t: float = clampf(_elapsed / maxf(cfg.duration, 0.001), 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	player.camera_rig.set_roll_spin(eased * _spin_total)
	# The eye dips through the middle and comes back: zero at both ends, so it
	# hands over to ordinary walking without a step.
	player.camera_rig.set_crouch_amount(sin(PI * t) * cfg.camera_crouch)

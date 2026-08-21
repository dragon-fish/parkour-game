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

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	# maxf, so the measured 3 m is a FLOOR rather than a replacement: a fast
	# landing still converts its momentum forward through speed_scale, and a
	# straight drop -- which arrives with no horizontal speed at all -- still
	# travels the distance the original travels. See SkillRollConfig.
	var forced: float = cfg.forced_distance / maxf(cfg.duration, 0.001)
	_speed = maxf(horizontal.length() * cfg.speed_scale, forced)
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
	player.velocity.y = -config.pawn.floor_snap_speed

	var rise: float = player.try_step_up(delta)
	if rise > 0.0 and player.camera_rig != null:
		player.camera_rig.add_step_offset(rise)
	player.move_and_slide()
	var stepped_down: bool = player.try_step_down()
	player.set_grounded(player.is_on_floor() or stepped_down)

	_drive_camera()

	if not player.grounded:
		# Rolled off an edge. The roll is over; the fall is what matters now.
		player.velocity.y = 0.0
		return FALLING
	if _elapsed >= cfg.duration:
		return WALKING
	return KEEP

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
	player.camera_rig.set_roll_spin(eased * cfg.camera_spin)
	# The eye dips through the middle and comes back: zero at both ends, so it
	# hands over to ordinary walking without a step.
	player.camera_rig.set_crouch_amount(sin(PI * t) * cfg.camera_crouch)

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
# [ME:CONFIRMED] NOT STEERABLE ONCE IT STARTS: ControllerState is
# PlayerGrabbing, MovementGroup is MG_TwoHandsBusy, and bDisableFaceRotation is
# set. The hands are busy and the facing is pinned; the direction is decided at
# touchdown and the player has no say in it afterwards.
#
# [ME:CONFIRMED] But it is AIMED: the direction comes from where the CAMERA
# points at touchdown, not from the momentum -- even if the player spun 180
# degrees in the air on the way down. A deliberate break with physics: a roll
# is a second of lost control, and letting the view aim it hands that second
# back. See enter().

var _elapsed: float = 0.0
## Fixed at touchdown, from the VIEW rather than from the momentum -- see
## enter(). Zero only if the facing is degenerate, which nothing produces.
var _direction: Vector3 = Vector3.ZERO
## Where the model is being walked round to -- see enter().
var _model_yaw_target: float = 0.0
var _speed: float = 0.0
## True once the ground has run out mid-roll. The roll does NOT end there -- see
## physics_update().
var _airborne: bool = false
## How far the view turns over this roll, captured at touchdown. NOT a constant:
## it is one full turn ADJUSTED by wherever the view already was, so the roll
## always finishes level. See enter().
var _spin_total: float = 0.0
## Where the spin begins: the negation of the pitch landed with, so the first
## frame of the roll reads as exactly that pitch. See enter().
var _spin_from: float = 0.0

func enter(_previous: StringName) -> void:
	_elapsed = 0.0
	_airborne = false
	# FIXED. NOT A FLOOR, AND NOT SCALED BY WHAT YOU ARRIVED WITH.
	#
	# [ME:CONFIRMED] A roll from a standstill and a roll at 80 km/h travel the
	# same 3 m in the original. What speed buys is not distance: it is the share
	# of the energy budget that survives (energy_keep below), so you get back up
	# to pace faster afterwards.
	#
	# DO NOT scale the forced distance by carried speed (e.g.
	# maxf(carried * speed_scale, forced)) -- the momentum term alone stretches
	# the roll to a measured 3.2 m instead of the confirmed 3 m.
	#
	# [ME:INFERRED] The original's travel is not at a constant rate: watched at
	# 1/8 speed it runs slow-fast-slow, on an animation curve. Deliberately not
	# copied here -- that curve exists to keep the travel under a body model's
	# feet, and this project has no body model for it to serve. An eased
	# translation with nothing visible driving it just reads as drifting.
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	_speed = cfg.forced_distance / maxf(cfg.duration, 0.001)
	# ALONG THE VIEW, NOT ALONG THE MOMENTUM.
	#
	# [ME:CONFIRMED] The forced travel follows where the CAMERA is pointing at
	# the instant the roll begins -- even if the player spun 180 degrees in
	# mid-air on the way down. It is a deliberate break with physics: a roll is
	# a second of lost control, and letting the view aim it hands that second
	# back. You steer the landing instead of being carried by whatever the fall
	# happened to leave you with.
	#
	# This is NOT a fallback for a heading-less drop. The heading is never
	# consulted; only the facing is.
	# Catalyst rolls the other way -- along the momentum, with four directional
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

	# THE MODEL IS TURNED TO FACE THE ROLL, and it has to be said here because
	# nothing else will say it. In third person the model only turns while a
	# direction key is held, so a body that lands, swings the view round and
	# rolls without touching a key rolls along its new facing while still
	# pointing the old way -- it reads as rolling backwards. The roll is a
	# scripted displacement along the view, not a continuation of momentum, so
	# the model owes the direction the same as the capsule does.
	#
	# SWUNG, NOT PINNED. Setting it outright is a 180 degree turn inside one
	# frame, which reads as the model being replaced rather than turning.
	# physics_update() walks it round at model_turn_speed_deg instead.
	_model_yaw_target = player.visual_yaw()
	if _direction != Vector3.ZERO:
		_model_yaw_target = atan2(-_direction.x, -_direction.z)

	# THE ROLL TAKES THE PITCH OVER, rather than offsetting it.
	#
	# [ME:CONFIRMED] FROM THE ORIGINAL'S OWN PANEL: at the instant SkillRoll
	# begins, P reads 0. Everything after that is camera performance. The general
	# principle behind it -- in the original the AUTHORITATIVE state and the
	# DISPLAYED one are allowed to disagree. The gameplay pitch is level from the
	# first frame; the visible rotation still starts from the pitch that was
	# landed with and travels more than a full turn when looking up, less when
	# looking down. Both are true because they are different channels.
	#
	# DO NOT drive only the spin and leave the pitch alone -- it breaks three
	# ways at once:
	#
	#   * the view SPRINGS BACK the frame after the roll ends -- the spin is a
	#     temporary offset over a pitch that never moved, so the roll never
	#     actually turned the view at all.
	#   * a roll entered at -50 STARTS at -11, because this move's own look
	#     clamp has a confirmed floor there and takes effect immediately.
	#   * and it then ENDS at -320, because the arithmetic used the -50 read
	#     before that clamp while the view was already at -11.
	#
	# Pinning the pitch to level and carrying the landing pitch in the SPIN
	# instead avoids all three -- and the panel reading above says this is not a
	# workaround but what the original itself does. The clamp then has nothing
	# to fight (level is inside every constraint), the visible start is still
	# the landing pitch because the spin begins at its negation, and releasing
	# the spin at the end leaves the view where the roll put it rather than
	# where it found it.
	var pitch_at_start: float = 0.0
	if player.camera_rig != null:
		pitch_at_start = float(player.camera_rig.look_debug()["pitch"])
		player.camera_rig.set_pitch(0.0)
	# rotation.x = pitch - spin, so a spin of -pitch_at_start reads as exactly
	# the pitch landed with, and one of camera_spin reads as level.
	_spin_from = -pitch_at_start
	_spin_total = cfg.camera_spin

	# DRIVEN ONCE HERE, not left to the first physics tick.
	#
	# THE CAMERA FLICKER. MoveManager calls enter() mid-tick and does NOT call
	# this move's own physics_update() on that same tick, so the spin was first
	# written a frame later -- while update_effects() at the end of the entry tick
	# already saw the pitch pinned to level with no spin to offset it. One frame
	# of the view snapping level before the roll's rotation took over.
	#
	# Proportional to the angle and invisible at small ones, so it only shows up
	# on an extreme-pitch roll.
	#
	# [ME:CONFIRMED] The original very likely hit the same race and paid it off
	# differently: watched at 1/8 speed, its P does not snap to zero but runs
	# down linearly over about ELEVEN FRAMES. We do not copy that -- one tenth
	# of a second of ramp is a workaround for a single-frame gap, and closing
	# the gap is the smaller fix. Recorded in docs/feel-backlog.md 40 so the
	# measurement is not lost if this ever needs revisiting.
	_drive_camera()

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
	var swing: float = deg_to_rad(cfg.model_turn_speed_deg) * delta
	var owed: float = wrapf(_model_yaw_target - player.visual_yaw(), -PI, PI)
	if absf(owed) > 0.0001:
		player.pin_visual_yaw(player.visual_yaw() + clampf(owed, -swing, swing))

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
	# [ME:CONFIRMED] In the original, if the ground runs out mid-roll the roll
	# animation still plays out -- the body is obviously falling by then, but
	# the move finishes anyway. DO NOT cut to a standing fall the instant the
	# floor disappears: the camera snaps from mid-tumble to upright in one
	# frame, which reads as broken.
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
	if not player.grounded:
		return FALLING
	# DO NOT hand a roll that ends without headroom to Walking -- a roll carries
	# real speed and travels while it plays, so where it ENDS is not somewhere
	# anyone chose, and rolling under a pipe or into a crawlspace is ordinary.
	# Walking would ask for a standing capsule that will not fit, so the request
	# is deferred and the player runs at full speed in a crouched body: a
	# measured 7.2 m/s, an unintended speed boost.
	#
	# Crouch costs nothing to enter from here: enter() already shrank the capsule
	# to config.crouch.crouch_capsule_height -- the very same height -- so this
	# hand-off changes no geometry at all, only who owns the body.
	if not player.has_headroom():
		return CROUCH
	return WALKING

## The roll itself: the view goes ALL THE WAY OVER, and the eye drops through
## the middle of it.
##
## DO NOT sink-and-return: it reads as indistinguishable from the hard landing
## this move exists to avoid, even though the two are the opposite outcome of
## the same moment. [ME:CONFIRMED] The original's own look clamp for this move
## reaches +180 degrees; going over is the manoeuvre.
##
## Eased at both ends (smoothstep) rather than linear, so the view is not
## yanked into the spin and does not stop dead at the end of it.
func _drive_camera() -> void:
	if player.camera_rig == null:
		return
	var t: float = clampf(_elapsed / maxf(cfg.duration, 0.001), 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	player.camera_rig.set_roll_spin(lerpf(_spin_from, _spin_total, eased))
	# The eye dips through the middle and comes back: zero at both ends, so it
	# hands over to ordinary walking without a step.
	player.camera_rig.set_crouch_amount(sin(PI * t) * cfg.camera_crouch)

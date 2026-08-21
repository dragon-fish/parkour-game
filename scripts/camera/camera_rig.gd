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
## The body height the eye is currently sitting at, chasing the body's real one.
##
## SMOOTHED FOLLOW, not an event-driven offset. try_step_up() moves the body in
## jumps, and between those jumps move_and_slide() and the floor snap pull it
## back down, so a stair is climbed as a rapid series of ups and downs. An
## offset pushed once per step-up cannot cancel that -- it only knows about the
## ups -- and the result was a camera that shook its way up every staircase.
##
## Following the height instead is indifferent to how jagged the body's path
## is: whatever the body does, the eye eases toward it at one rate.
var _eye_ground_y: float = 0.0
var _has_eye_ground: bool = false
var _wall_side: int = 0
var _roll: float = 0.0
## An additive downward pitch owned by LandingMove. Separate from _dip because
## dip is a spring driven by impact speed and recovers on its own schedule;
## this one is driven explicitly by a state that knows how long it has left.
var _landing_pitch: float = 0.0

## A full rotation about the pitch axis, owned by SkillRollMove. Applied
## OUTSIDE the pitch clamp, unlike _landing_pitch: the clamp exists to stop the
## landing sink pushing the view past vertical, but a roll is SUPPOSED to go
## past vertical -- the original's own MaxLookConstraint for TdMove_SkillRoll
## is +180 degrees, which is the manoeuvre going over.
var _roll_spin: float = 0.0

## The active move's look clamp, in radians, or "no clamp" when
## _has_look_constraint is false. Driven by MoveManager every tick; consumed
## by apply_look() from Task 15 onward.
var _look_min: Vector3 = Vector3(-PI, -PI, -PI)
var _look_max: Vector3 = Vector3(PI, PI, PI)
var _look_absolute_yaw: bool = false
var _look_pitch_relaxes: bool = false
var _look_pitch_min_turned: float = -PI
var _look_pitch_relax_threshold: float = 0.0
var _look_pitch_recover_speed: float = 14.0
## How far the view has turned from the facing the constraint was captured at,
## as a fraction of the yaw range: 0 facing forward, 1 at either edge. Written
## by apply_look() and read by its own pitch clamp a few lines later.
var _look_yaw_fraction: float = 0.0
var _has_look_constraint: bool = false
## The body's yaw at the instant a look constraint first became active,
## captured once by set_look_constraint() (not refreshed on the repeat calls
## MoveManager makes every tick) so an absolute-yaw fan stays pinned to the
## facing the move began with instead of drifting with the player.
var _yaw_reference: float = 0.0

## How far the view has turned from _yaw_reference, ACCUMULATED rather than
## re-derived each frame.
##
## Deriving it wrapped the difference into [-PI, PI], which a fast flick walks
## straight through: swing 200 degrees in one tick against a 170 degree fan and
## the wrap reports -160, which is inside the fan, so the clamp passes it. The
## faster the mouse, the easier the fence is to climb -- reported in play as
## being able to turn a full circle while hanging.
##
## Accumulating cannot be fooled that way: the clamp is applied to the running
## total, so a turn that would leave the fan is simply cut off at its edge
## however fast it arrives.
var _look_relative_yaw: float = 0.0

## How far the eye is still lagging behind a turn a MOVE made on the body's
## behalf, in radians. Bled off every frame.
##
## Only scripted turns land here -- the player's own mouse goes straight
## through, because a view that lags the mouse is intolerable. Moves report
## their own turns via absorb_body_yaw(); nothing is inferred.
var _scripted_yaw_lag: float = 0.0

## The attached body's head/neck node position, in THIS rig's PARENT's
## (Player's) local space -- i.e. Player.to_local(head_node.global_position)
## -- as of the most recent set_head_position() call. Meaningless whenever
## _has_head is false. Driven by Player every physics tick, mirroring
## set_wall_side()/set_crouch_amount(); see update_effects()'s own use of it
## for the head-follow camera.
var _head_local_position: Vector3 = Vector3.ZERO
## True only for ticks Player actually supplied a head position -- i.e. a
## body is attached AND Player._find_head_node() matched something visible
## in it. update_effects() must gate on this rather than comparing
## _head_local_position against a sentinel: Vector3.ZERO is itself a
## perfectly legitimate head position, so treating it as "no head" would
## silently misread a real, if centred, head as absent.
var _has_head: bool = false

## True while a level-owned cutscene (DeathSequence, currently the only
## caller) has taken the camera over. update_effects() yields entirely in
## this state -- see its own comment -- so bob/dip/crouch/look cannot fight
## the cutscene for the same transform.
var _cinematic: bool = false
var _cinematic_offset: Vector3 = Vector3.ZERO
var _cinematic_roll: float = 0.0
var _cinematic_pitch: float = 0.0

func setup(cfg: MovementConfig) -> void:
	_config = cfg
	position.y = cfg.camera.eye_height
	if camera != null:
		camera.fov = cfg.camera.fov_base

## 0 = standing, 1 = fully crouched. Driven by Player each tick.
func set_crouch_amount(amount: float) -> void:
	_crouch_amount = clampf(amount, 0.0, 1.0)

## -1 wall on the left, +1 on the right, 0 none. Driven by Player each tick
## from Player.wall_side, itself set by WallRunMove. update_effects() eases
## rotation.z toward the corresponding tilt every frame.
## Retained as a no-op so callers that announce a step-up do not have to change
## shape. The camera no longer needs telling: it follows the body's height (see
## _eye_ground_y), which covers step-ups, floor snaps and everything else the
## body does to its own altitude without any of them having to report in.
func add_step_offset(_amount: float) -> void:
	pass


func set_wall_side(side: int) -> void:
	_wall_side = side

## Sets the additive downward pitch LandingMove drives every tick of its
## lockout. `radians` is a plain magnitude (>= 0 in normal use); this rig
## SUBTRACTS it from the ordinary look pitch in update_effects() below, so a
## positive value tips the view down -- the same "sink and look at the
## ground" read as the original's knee-clutch animation, expressed here as an
## input constraint's camera instead of root motion. LandingMove is expected
## to call this every tick with its own value ramping 0 -> peak -> 0 across
## the lockout; this rig holds no timer of its own for it.
func set_landing_pitch_offset(radians: float) -> void:
	_landing_pitch = radians

## Sets the roll's own rotation about the pitch axis, in radians, measured from
## upright. Driven every tick by SkillRollMove; see _roll_spin for why this is
## a separate channel from the landing sink rather than more of the same.
func set_roll_spin(radians: float) -> void:
	_roll_spin = radians

## Told by a move that it has just turned the body by `radians`, so the eye can
## lag behind and catch up rather than being cut through the turn.
##
## The move still turns the body immediately -- physics, probes and the look
## clamp all work from the real facing. Only the EYE is behind, and only for as
## long as it takes to catch up.
func absorb_body_yaw(radians: float) -> void:
	if is_zero_approx(radians):
		return
	# HELD SHORT. A lag is a softening, not a detour: past a certain size the
	# eye is no longer trailing the turn, it is pointing somewhere else
	# entirely -- in first person, at the inside of whatever the body is
	# pressed against. Reported in play as the view lunging into the wall and
	# then snapping back to the ledge.
	#
	# Anything bigger than this is better taken as a cut: the turn was too
	# large to hide, and half-hiding it looks worse than not trying.
	const MAX_LAG := 0.35
	_scripted_yaw_lag = clampf(_scripted_yaw_lag - radians, -MAX_LAG, MAX_LAG)

## The attached body's head/neck node position, in Player's local space
## (Player.to_local(head_node.global_position)) -- see _head_local_position's
## own comment. Called by Player every tick a head is available.
func set_head_position(local_position: Vector3) -> void:
	_head_local_position = local_position
	_has_head = true

## Called by Player every tick NO head is available -- no body attached, or
## the attached body has nothing _find_head_node() could match. Must be
## called explicitly rather than relying on a timeout: a stale _has_head left
## true from a body that has since gone away would otherwise keep blending
## toward a head position nothing is updating any more.
func clear_head_position() -> void:
	_has_head = false

## Stores the active move's look clamp. Driven by MoveManager every tick from
## the active move's current_config() -- including every tick a move STAYS
## constrained, not just the tick it becomes constrained. Only the
## unconstrained-to-constrained transition captures _yaw_reference: repeat
## calls while already constrained must leave it alone, or an absolute-yaw
## fan would drift to follow the player instead of staying pinned to the
## facing the move began with.
func set_look_constraint(min_c: Vector3, max_c: Vector3, absolute_yaw: bool, \
		pitch_relaxes: bool = false, pitch_min_turned: float = -PI, \
		relax_threshold: float = 0.0, recover_speed: float = 14.0) -> void:
	if not _has_look_constraint:
		var body := get_parent()
		if body is Node3D:
			_yaw_reference = body.rotation.y
		# The running total starts where the body already is, which is zero by
		# definition since the reference was just taken from it.
		_look_relative_yaw = 0.0
	# NOT reset here. MoveManager calls this every tick, so clearing the lag
	# would wipe it on the frame a constraint takes hold -- which is exactly
	# when the reach has just handed over a turn to smooth, so the eye snapped
	# back the instant it entered the hang. The lag belongs to the camera's own
	# smoothing, not to whichever move happens to be constraining the view; it
	# is cleared on a full reset_state() and bled off every frame otherwise.
	_look_min = min_c
	_look_max = max_c
	_look_absolute_yaw = absolute_yaw
	_look_pitch_relaxes = pitch_relaxes
	_look_pitch_min_turned = pitch_min_turned
	_look_pitch_relax_threshold = relax_threshold
	_look_pitch_recover_speed = recover_speed
	_has_look_constraint = true

## Re-centres the yaw fan on a direction the MOVE knows about, rather than on
## whatever the body happened to be facing when the constraint took hold.
##
## Hanging is the case: the fan belongs to the WALL. A ledge caught at a
## 70 degree angle left the fan skewed 70 degrees off it, so "turn 90 degrees
## from straight-on" meant something different on every grab. Called once the
## body has been aligned, so the running total starts from its real facing.
func recentre_yaw_reference(yaw: float) -> void:
	_yaw_reference = yaw
	var body := get_parent()
	if not (body is Node3D):
		_look_relative_yaw = 0.0
		return
	var offset: float = wrapf((body as Node3D).rotation.y - yaw, -PI, PI)
	# A re-centre can find the view OUTSIDE the fan it has just been measured
	# against -- attaching to a wall at an angle is exactly that case, since the
	# approach can be up to 57 degrees off the wall's own line while the fan is
	# a quarter turn on one side of it.
	#
	# LEFT OUTSIDE THE FAN if that is where it lands, deliberately. apply_look's
	# own clamp eases the fan's edge in to meet it (see there), carrying the
	# view round over several ticks instead of cutting it to the edge in one.
	# This is a scripted view change -- the wall moved the fan, not the player's
	# hand -- so it eases. See docs/camera-authority.md.
	#
	# This used to clamp here and hand the correction to absorb_body_yaw's lag.
	# That worked for small corrections and failed for the ones that matter: the
	# lag is capped at 0.35 rad, and attaching at the forward branch's full 57
	# degrees is nearly twice that, so most of the turn arrived as a cut anyway.
	_look_relative_yaw = offset

## Diagnostics for the debug HUD: how far the view has turned from the fan's
## centre, and the pitch floor currently in force. Both in radians.
func look_debug() -> Dictionary:
	return {
		"constrained": _has_look_constraint,
		"relative_yaw": _look_relative_yaw,
		"pitch_floor": _relaxed_pitch_floor() if (_has_look_constraint and _look_pitch_relaxes) 			else (_look_min.x if _has_look_constraint else -PI),
		"pitch": _pitch,
	}

func clear_look_constraint() -> void:
	_has_look_constraint = false
	_look_pitch_relaxes = false
	_look_yaw_fraction = 0.0
	_look_relative_yaw = 0.0

## Hands the camera to a level-owned cutscene. Called once when the cutscene
## starts; the caller drives the pose every tick via set_cinematic_pose()
## from then on. See update_effects()'s own comment for why this yields the
## whole function rather than composing with bob/dip/crouch.
func begin_cinematic() -> void:
	_cinematic = true

## Sets this tick's cutscene pose. `offset` is a local offset from the resting
## eye position; `roll` is rotation.z and `pitch` is rotation.x, both radians.
## Meaningless unless begin_cinematic() has been called and end_cinematic() has
## not.
##
## Pitch is driven here rather than left at whatever the player was looking at,
## because they were probably looking DOWN: watching the ground come up is the
## reflex on a fatal fall, and a topple animation played from a face-down view
## reads as nonsense.
func set_cinematic_pose(offset: Vector3, roll: float, pitch: float = 0.0) -> void:
	_cinematic_offset = offset
	_cinematic_roll = roll
	_cinematic_pitch = pitch

## Hands the camera back. Resets the cutscene offset/roll to neutral so a
## stale pose cannot linger into the next update_effects() call before that
## call has a chance to recompute its own transform.
func end_cinematic() -> void:
	_cinematic = false
	_cinematic_offset = Vector3.ZERO
	_cinematic_roll = 0.0
	_cinematic_pitch = 0.0

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
	_has_eye_ground = false
	_wall_side = 0
	_roll = 0.0
	_landing_pitch = 0.0
	_roll_spin = 0.0
	_has_head = false
	_has_look_constraint = false
	_look_relative_yaw = 0.0
	# The one place the scripted-turn lag IS cleared: a reset is a new life,
	# and a turn half-smoothed from the old one has nothing to catch up to.
	_scripted_yaw_lag = 0.0
	end_cinematic()
	rotation.x = 0.0
	rotation.y = 0.0
	rotation.z = 0.0
	if camera != null:
		camera.position.y = 0.0

## Yaw turns the body so movement follows the view; pitch stays on the rig.
##
## The ACTIVE MOVE's own clamp wins over the global pitch limit when it
## declares one. The original makes this per-move data (MinLookConstraint /
## MaxLookConstraint, 06 §6.2) and it is a genuine input constraint: on a wall
## the view is locked into a +-90 degree yaw fan and cannot look back, which
## is where that whole sensation comes from.
func apply_look(look_delta: Vector2, body: Node3D, delta: float = 0.0) -> void:
	if _cinematic:
		return
	if _config == null:
		return
	var yaw_delta := -look_delta.x * _config.camera.mouse_sensitivity
	# A scripted sweep is added to the same channel the mouse drives, so the
	# body ends up facing exactly where the same flick by hand would have put
	# it. The owner's test for this feature is that Q and space should feel like
	# turning by hand and pressing space, which only holds if the two paths are
	# literally the same one.
	yaw_delta += _advance_look_sweep(yaw_delta, delta)
	if _has_look_constraint:
		# Absolute yaw: measured against the facing captured when the move
		# began, so the fan stays pinned to the wall rather than drifting with
		# the player. Source: 04 §4.1 bUseAbsoluteYawConstraint = True.
		var reference: float = _yaw_reference if _look_absolute_yaw else body.rotation.y
		var relative: float
		if _look_absolute_yaw:
			# Accumulated, never re-derived -- see _look_relative_yaw for why a
			# wrapped difference lets a fast flick through the fence.
			#
			# The fan's EDGE is eased in to meet a view already outside it,
			# rather than that view being cut to the edge. Exactly the treatment
			# the pitch floor gets a few lines down, and for the same reason:
			# what is being softened is the FAN MOVING out from under the
			# player, which is what a wall run does when it re-centres on the
			# wall it just attached to, and again as it carries the fan round a
			# curve. A player pushing against an edge that has NOT moved is
			# clamped hard, as always.
			#
			# Told apart by the PREVIOUS value, the same trick the pitch uses:
			# the clamp runs every tick, so the player can never come to BE
			# outside the fan. If the running total is outside it, the fan moved.
			var low: float = _look_min.y
			var high: float = _look_max.y
			if delta > 0.0:
				var settle: float = clampf(_config.camera.look_settle_speed * delta, 0.0, 1.0)
				if _look_relative_yaw < low:
					low = lerpf(_look_relative_yaw, low, settle)
				elif _look_relative_yaw > high:
					high = lerpf(_look_relative_yaw, high, settle)
			_look_relative_yaw = clampf(_look_relative_yaw + yaw_delta, low, high)
			relative = _look_relative_yaw
		else:
			# Relative clamps measure against the CURRENT facing, so there is
			# no running total to keep: this is a per-tick rate limit by
			# construction, which is what the original's non-absolute clamps
			# are.
			relative = clampf(yaw_delta, _look_min.y, _look_max.y)
		body.rotation.y = reference + relative
		# How far round the view has come, for the pitch clamp below.
		var yaw_span: float = maxf(absf(_look_max.y if relative >= 0.0 else _look_min.y), 0.0001)
		_look_yaw_fraction = clampf(absf(relative) / yaw_span, 0.0, 1.0)
	else:
		body.rotate_y(yaw_delta)

	var pitch_min: float = -deg_to_rad(_config.camera.pitch_limit_deg)
	var pitch_max: float = deg_to_rad(_config.camera.pitch_limit_deg)
	var floor_pitch: float = -PI
	if _has_look_constraint:
		floor_pitch = _relaxed_pitch_floor() if _look_pitch_relaxes else _look_min.x
		pitch_min = maxf(pitch_min, floor_pitch)
		pitch_max = minf(pitch_max, _look_max.x)
	var wanted: float = _pitch - look_delta.y * _config.camera.mouse_sensitivity
	# The floor is EASED UP to meet a view already below it, rather than that
	# view being yanked up to meet the floor.
	#
	# Only that case. A player actively dragging the view down against a floor
	# that has not moved is clamped hard, as always. What is being softened is
	# the floor RISING out from under them, which happens when they look down
	# from a one-handed hang and then turn back toward the wall; clamping there
	# puts the view at level in a single frame.
	#
	# Told apart by the PREVIOUS pitch rather than the requested one: if _pitch
	# was already below the floor then the floor moved, whereas if only
	# `wanted` is below it then the player is pulling.
	var effective_floor: float = pitch_min
	if _has_look_constraint and _look_pitch_relaxes and _pitch < floor_pitch and delta > 0.0:
		effective_floor = lerpf(_pitch, floor_pitch, \
			clampf(_look_pitch_recover_speed * delta, 0.0, 1.0))
	_pitch = clampf(wanted, effective_floor, pitch_max)
	rotation.x = _pitch

## The pitch floor for a constraint that relaxes as the view turns away.
##
## SEGMENTED, not a straight ramp. Under pitch_relax_yaw_threshold the declared
## floor applies unchanged; past it the floor opens toward pitch_min_turned_away
## across whatever yaw range is left.
##
## Hanging is what this is shaped for: the original switches to a ONE-HANDED
## hold once the player has turned far enough round, and only that hold can
## look down. Below the threshold both hands are on the ledge and the view
## stays up, which a single ramp from zero cannot express -- it would let the
## player peek downward from a two-handed hang.
func _relaxed_pitch_floor() -> float:
	# A STEP, not a ramp. This models a change of GRIP -- two hands on the ledge
	# or one -- and a grip does not half-change. Ramping it across the rest of
	# the yaw range meant turning to 100 degrees bought 8 degrees of downward
	# view, which in play is indistinguishable from still being locked at
	# level; only turning all the way to the fan's edge opened it properly.
	if absf(_look_relative_yaw) <= _look_pitch_relax_threshold:
		return _look_min.x
	return _look_pitch_min_turned

func update_effects(delta: float, horizontal_speed: float, grounded: bool) -> void:
	if _config == null or camera == null:
		return

	# While cinematic, this function yields entirely: bob, dip, crouch and the
	# head-follow blend all step aside, and the pose comes straight from
	# whatever the cutscene last passed to set_cinematic_pose(). Without this
	# the death sequence would fight running sway for the same transform.
	if _cinematic:
		position = Vector3(0.0, _config.camera.eye_height, 0.0) + _cinematic_offset
		rotation.z = _cinematic_roll
		rotation.x = _cinematic_pitch
		return

	# Where the rig would sit this frame with NO head-follow applied,
	# recomputed from scratch every call rather than read back from last
	# frame's `position`. This is what makes camera_head_follow_strength mean
	# the same thing on every axis: previously only Y got a fresh base (via
	# the eye_height re-apply below) while X/Z inherited whatever the PREVIOUS
	# frame's lerp already blended them to, so the head-follow lerp at the
	# bottom of this function was blending toward the head from an
	# ever-more-converged starting point on X/Z -- an exponential approach to
	# the head regardless of how small `strength` was, even though Y (reset
	# fresh every frame) genuinely held at the configured fraction. Composing
	# every other contribution below into `base_position` instead of `position`
	# keeps that guarantee on all three axes: `position` itself is written
	# exactly once, at the very end of this function.
	var base_position := Vector3.ZERO
	base_position.y = _config.camera.eye_height

	var speed_ratio := clampf(horizontal_speed / maxf(_config.camera.fov_speed_ref, 0.001), 0.0, 1.0)

	var target_fov := lerpf(_config.camera.fov_base, _config.camera.fov_max, speed_ratio)
	camera.fov = lerpf(camera.fov, target_fov, clampf(_config.camera.fov_lerp_speed * delta, 0.0, 1.0))

	var bob_target := 1.0 if grounded else 0.0
	_bob_weight = move_toward(_bob_weight, bob_target, _config.camera.bob_fade_speed * delta)

	if grounded:
		_bob_phase += delta * _config.camera.bob_frequency * horizontal_speed
	# The phase freezes while airborne, so the offset it produces here holds
	# steady from the moment of leaving the ground; _bob_weight is what fades
	# it toward zero instead of letting it vanish in a single frame.
	var bob := sin(_bob_phase) * _config.camera.bob_amplitude * speed_ratio * _bob_weight

	_dip = move_toward(_dip, 0.0, _config.camera.land_dip_recover * delta)
	camera.position.y = bob - _dip

	# Tracked as an offset independent of base_position.y (mirroring _dip
	# above) rather than lerping base_position.y toward a target directly:
	# base_position.y is freshly set to the live eye_height a few lines up,
	# every frame, so the F1 panel's slider stays instant. Lerping
	# base_position.y itself would get reset to eye_height before move_toward
	# ever got a chance to build on the previous frame's progress, capping the
	# visible drop at a single frame's worth of movement no matter how long
	# the slide lasted. A persistent offset (_crouch_offset, a plain float
	# member that DOES survive frame to frame, unlike base_position) survives
	# that reset and actually eases across crouch_lerp_speed.
	var target_offset := _config.camera.slide_camera_drop * _crouch_amount
	_crouch_offset = move_toward(_crouch_offset, target_offset, _config.camera.crouch_lerp_speed * delta)
	base_position.y -= _crouch_offset

	# A step-up moves the body's Y in a single tick. Hold the eye behind by that
	# much and ease it up, so clearing a plank reads as a stride rather than a
	# snap. Exponential (like the FOV lerp above) rather than move_toward: the
	# offset should fade fastest right after the step and settle softly.
	#
	# Deliberately NOT folded into _dip: landing and stepping are independent
	# knobs, the same separation camera_config keeps between land_dip_speed_ref
	# and the movement side's land_cost_speed_ref.
	# The eye chases the body's height rather than being told about steps.
	# Clamped to one step so a real fall is never smoothed -- the body drops
	# faster than this could follow, and watching the ground rush up is the
	# whole point of a fall.
	# Bleed off any scripted turn the eye is still behind on. Written to the
	# rig's own yaw, which is otherwise unused: the body carries the real
	# facing, this is only how far the view trails it.
	var catchup: float = clampf(_config.camera.scripted_yaw_catchup_speed * delta, 0.0, 1.0)
	_scripted_yaw_lag = lerpf(_scripted_yaw_lag, 0.0, catchup)
	rotation.y = _scripted_yaw_lag

	var body_y: float = (get_parent() as Node3D).global_position.y if get_parent() is Node3D else 0.0
	if not grounded or not _has_eye_ground:
		# Airborne: no lag at all. Pinned every tick so that the moment the body
		# lands, the eye is already where the body is and nothing springs.
		_eye_ground_y = body_y
		_has_eye_ground = true
	else:
		_eye_ground_y = lerpf(_eye_ground_y, body_y,
				clampf(_config.camera.step_smooth_speed * delta, 0.0, 1.0))
	var cap: float = _config.pawn.max_step_height
	base_position.y += clampf(_eye_ground_y - body_y, -cap, cap)

	# Blend the eye position toward the attached body's head/neck node, LAST
	# among the base_position.* writes above -- lerp(t=0.0) returns
	# `base_position` bit-for-bit (Vector3.lerp is exactly a + (b-a)*t, and
	# any finite delta times 0.0 is exactly 0.0 in IEEE 754), which is what
	# makes camera_head_follow_strength == 0.0 degrade to EXACTLY today's
	# camera rather than merely close to it -- and _has_head being false (no
	# body, or nothing in it matched _find_head_node()) takes the plain
	# `position = base_position` branch below, the same guarantee. Blending
	# FROM base_position (recomputed above, this frame, from nothing) rather
	# than from the previous frame's `position` is what keeps this a one-shot
	# fraction instead of an exponential approach: `position` is read here
	# only as the assignment target, never as an input. Deliberately no
	# move_toward/easing layer of its own: the attached body's own
	# AnimationPlayer already supplies whatever motion this tracks, and the
	# strength dial is meant to scale that directly, not add a second lag on
	# top of it. Clamped independently of whatever range the F1 panel's
	# slider can reach (see CameraConfig.camera_head_follow_strength's own
	# comment on why its range and this clamp can disagree) so a value pushed
	# past 1.0 can never overshoot past the bone's own position.
	if _has_head:
		var strength := clampf(_config.camera.camera_head_follow_strength, 0.0, 1.0)
		position = base_position.lerp(_head_local_position, strength)
	else:
		position = base_position

	# rotation.z, unlike position.y above, is never hard-reset elsewhere in
	# this function, so a plain move_toward accumulates correctly frame to
	# frame instead of needing the offset workaround the crouch drop uses.
	#
	# SIGN: positive rotation.z rotates local up toward -X (verified against
	# this exact Godot build: rotation.z = 10 degrees gives basis.y =
	# (-0.17, 0.98, 0)), which from behind the camera reads as
	# counter-clockwise. A left wall (wall_side = -1) therefore produces a
	# NEGATIVE rotation.z here, i.e. clockwise -- which is what the owner
	# reports as correct in play.
	#
	# This REVERSES the earlier intent. The previous code negated this
	# deliberately, and both its comment and its (now archived) test declared
	# the goal as "roll toward the wall". The research offers no ruling either
	# way: 09 §9.1 calls the direction correct, but the same section records
	# that the original has NO VALUE for this field at all, so that was the
	# researcher's judgement rather than extracted data. The owner is playing
	# it; the owner wins.
	#
	# tests/legacy/test_camera_rig.gd's test_the_camera_rolls_toward_the_wall_
	# side still asserts the OLD (now-reversed) intent -- it is ARCHIVED by
	# Task 1 and NOT in the running suite, so it does not fail the build, but
	# it will need rewriting to match this new intent whenever the
	# behavioural suite is restored.
	var target_roll := deg_to_rad(_config.camera.wall_camera_roll_deg) * float(_wall_side)
	_roll = move_toward(_roll, target_roll, deg_to_rad(_config.camera.wall_camera_roll_speed) * delta)
	rotation.z = _roll

	# Layered on top of the ordinary look pitch, same relationship _dip has to
	# bob above: apply_look() already wrote rotation.x = _pitch for this tick's
	# mouse input, and this recombines it with whatever LandingMove has since
	# asked for via set_landing_pitch_offset() (0.0 the overwhelming majority
	# of ticks, when nothing is driving it). Recomputed every frame rather than
	# accumulated, so the sink tracks LandingMove's own severity curve exactly
	# instead of drifting from it.
	#
	# Clamped, because apply_look() only ever bounded _pitch on its own. Landing
	# leaves pitch to the global limit (LandingConfig says why), so a player who
	# was already looking almost straight down on impact would otherwise have
	# the sink push the combined angle past vertical and roll the horizon over.
	var pitch_limit: float = deg_to_rad(_config.camera.pitch_limit_deg)
	# The spin is added AFTER the clamp, on purpose -- see _roll_spin.
	rotation.x = clampf(_pitch - _landing_pitch, -pitch_limit, pitch_limit) - _roll_spin

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.camera.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.camera.land_dip_max)

# --- scripted look sweep ------------------------------------------------------
#
# The eye being carried across the fan under its own power, with the body left
# alone. Q during a wall run is the only caller: the owner's account is that it
# "only changes the view, it does not pin the character in place", and that
# doing the same thing by hand with the mouse should feel identical -- which is
# only true if this drives exactly the value the mouse drives.

## Target for _look_relative_yaw while a sweep is running, and whether one is.
var _sweep_to: float = 0.0
var _sweeping: bool = false

## Starts carrying the view to `relative_yaw`, measured in the same frame as
## _look_relative_yaw: radians from the fan's own centre.
##
## Silently does nothing with no constraint in force. A sweep is expressed in a
## fan's coordinates, and without a fan there is no target to name.
func sweep_look_to(relative_yaw: float) -> void:
	if not _has_look_constraint:
		return
	_sweep_to = clampf(relative_yaw, _look_min.y, _look_max.y)
	_sweeping = true

func is_sweeping() -> bool:
	return _sweeping

func cancel_look_sweep() -> void:
	_sweeping = false

## Advances a running sweep. Returns the yaw delta to apply this tick, or 0.
##
## THE PLAYER'S OWN HAND WINS. Any real mouse movement cancels the sweep on the
## spot rather than fighting it: this is a convenience for a flick the player
## could have done themselves, and a convenience that resists being overridden
## is worse than none.
func _advance_look_sweep(mouse_yaw_delta: float, delta: float) -> float:
	if not _sweeping:
		return 0.0
	if absf(mouse_yaw_delta) > 0.0001:
		_sweeping = false
		return 0.0
	var remaining: float = _sweep_to - _look_relative_yaw
	var step: float = _config.camera.look_sweep_speed * delta
	if absf(remaining) <= step or delta <= 0.0:
		_sweeping = false
		return remaining
	return signf(remaining) * step

## Moves the fan's CENTRE without re-deriving how far the view has turned from
## it, and carries the view part of the way with it.
##
## For a constraint whose reference is not fixed for the move's whole life --
## wall running along a curve is the case, and so far the only one. The wall's
## own line is what the fan is measured against, so when the wall turns, the
## fan has to turn too or the clamp ends up policing a direction the wall
## stopped pointing in some metres ago.
##
## NOT recentre_yaw_reference(). That one re-derives the running total from the
## body, which is exactly what the accumulator exists to avoid (see
## _look_relative_yaw: a re-derived difference is wrapped, and a wrap is a hole
## in the fence). This one leaves the total alone and moves only the origin it
## is measured from, so the fence travels intact.
##
## `assist` is how much of the wall's turn the VIEW is carried through, 0 to 1:
##   1  the view follows the wall exactly, keeping the same angle to it
##   0  the view holds its world direction and the fan slides underneath it,
##      shoving it only once an edge catches up
## In between reads as the run guiding the player's eyes rather than steering
## them.
func shift_yaw_reference(yaw: float, assist: float) -> void:
	if not _has_look_constraint:
		return
	var moved: float = wrapf(yaw - _yaw_reference, -PI, PI)
	if is_zero_approx(moved):
		return
	_yaw_reference = yaw
	# The body's facing is rebuilt from reference + relative every tick, so
	# leaving the total alone would carry the view through the WHOLE of the
	# wall's turn. Backing it off by the un-assisted share is what leaves only
	# `assist` of the turn actually reaching the eye.
	var carried: float = moved * (1.0 - clampf(assist, 0.0, 1.0))
	# Unclamped, same as recentre_yaw_reference(): a fan that has travelled past
	# the view is eased back over it by apply_look rather than snapping it.
	_look_relative_yaw -= carried

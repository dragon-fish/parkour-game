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
## How far the eye is still lagging behind a step-up. Persistent member for the
## same reason _crouch_offset is: base_position.y is rebuilt from eye_height
## every frame, so anything easing over time has to live outside it.
var _step_offset: float = 0.0
var _wall_side: int = 0
var _roll: float = 0.0
## An additive downward pitch owned by LandingMove. Separate from _dip because
## dip is a spring driven by impact speed and recovers on its own schedule;
## this one is driven explicitly by a state that knows how long it has left.
var _landing_pitch: float = 0.0

## The active move's look clamp, in radians, or "no clamp" when
## _has_look_constraint is false. Driven by MoveManager every tick; consumed
## by apply_look() from Task 15 onward.
var _look_min: Vector3 = Vector3(-PI, -PI, -PI)
var _look_max: Vector3 = Vector3(PI, PI, PI)
var _look_absolute_yaw: bool = false
var _has_look_constraint: bool = false
## The body's yaw at the instant a look constraint first became active,
## captured once by set_look_constraint() (not refreshed on the repeat calls
## MoveManager makes every tick) so an absolute-yaw fan stays pinned to the
## facing the move began with instead of drifting with the player.
var _yaw_reference: float = 0.0

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
## Called when the body was lifted over a low obstacle. Accumulates, so two
## steps in quick succession do not cancel each other out.
func add_step_offset(amount: float) -> void:
	_step_offset += amount


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
func set_look_constraint(min_c: Vector3, max_c: Vector3, absolute_yaw: bool) -> void:
	if not _has_look_constraint:
		var body := get_parent()
		if body is Node3D:
			_yaw_reference = body.rotation.y
	_look_min = min_c
	_look_max = max_c
	_look_absolute_yaw = absolute_yaw
	_has_look_constraint = true

func clear_look_constraint() -> void:
	_has_look_constraint = false

## Hands the camera to a level-owned cutscene. Called once when the cutscene
## starts; the caller drives the pose every tick via set_cinematic_pose()
## from then on. See update_effects()'s own comment for why this yields the
## whole function rather than composing with bob/dip/crouch.
func begin_cinematic() -> void:
	_cinematic = true

## Sets this tick's cutscene pose. `offset` is a local offset from the
## resting eye position; `roll` is rotation.z in radians. Meaningless unless
## begin_cinematic() has been called and end_cinematic() has not.
func set_cinematic_pose(offset: Vector3, roll: float) -> void:
	_cinematic_offset = offset
	_cinematic_roll = roll

## Hands the camera back. Resets the cutscene offset/roll to neutral so a
## stale pose cannot linger into the next update_effects() call before that
## call has a chance to recompute its own transform.
func end_cinematic() -> void:
	_cinematic = false
	_cinematic_offset = Vector3.ZERO
	_cinematic_roll = 0.0

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
	_step_offset = 0.0
	_wall_side = 0
	_roll = 0.0
	_landing_pitch = 0.0
	_has_head = false
	_has_look_constraint = false
	end_cinematic()
	rotation.x = 0.0
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
func apply_look(look_delta: Vector2, body: Node3D) -> void:
	if _cinematic:
		return
	if _config == null:
		return
	var yaw_delta := -look_delta.x * _config.camera.mouse_sensitivity
	if _has_look_constraint:
		# Absolute yaw: measured against the facing captured when the move
		# began, so the fan stays pinned to the wall rather than drifting with
		# the player. Source: 04 §4.1 bUseAbsoluteYawConstraint = True.
		var reference: float = _yaw_reference if _look_absolute_yaw else body.rotation.y
		var next_yaw: float = body.rotation.y + yaw_delta
		var relative: float = wrapf(next_yaw - reference, -PI, PI)
		relative = clampf(relative, _look_min.y, _look_max.y)
		body.rotation.y = reference + relative
	else:
		body.rotate_y(yaw_delta)

	var pitch_min: float = -deg_to_rad(_config.camera.pitch_limit_deg)
	var pitch_max: float = deg_to_rad(_config.camera.pitch_limit_deg)
	if _has_look_constraint:
		pitch_min = maxf(pitch_min, _look_min.x)
		pitch_max = minf(pitch_max, _look_max.x)
	_pitch = clampf(_pitch - look_delta.y * _config.camera.mouse_sensitivity, pitch_min, pitch_max)
	rotation.x = _pitch

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
	_step_offset = lerpf(_step_offset, 0.0,
			clampf(_config.camera.step_smooth_speed * delta, 0.0, 1.0))
	base_position.y -= _step_offset

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
	rotation.x = _pitch - _landing_pitch

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.camera.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.camera.land_dip_max)

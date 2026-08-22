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
## A bank owned by SpeedVaultMove, added on top of the wall-run tilt rather than
## fighting it for rotation.z. The owner's description of the original: "a
## stylish vault, the camera tilting slightly as it traces a graceful arc over
## the obstacle." A vault is a scripted motion, so the eye is entitled to be
## moved by it -- see docs/camera-authority.md.
var _vault_roll: float = 0.0
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

## How far the attached body's head/neck node has moved FROM ITS REST POSE,
## in this rig's parent's (Player's) local space, as of the most recent
## set_head_offset() call. Meaningless whenever _has_head is false.
##
## A DISPLACEMENT, not a position, and that distinction is the whole point.
## This used to hold the head's absolute local position and update_effects()
## lerped the eye toward it, which conflated two unrelated things: where the
## eye belongs, and how the head moves. The eye's resting place is a decision
## (eye_height, and in practice a little ahead of the neck, as first-person
## games place it); the head node's origin is wherever the model's author put
## it. Blending between them dragged the eye toward the second and, at any
## strength below 1, still left the head sliding through the view -- while at
## strength 1 it threw the first away entirely and parked the camera inside
## the neck.
##
## Carrying the displacement instead lets both be true at once: the eye keeps
## its own resting place AND rides the head exactly, which is what stops the
## body reaching the camera at all.
var _head_local_offset: Vector3 = Vector3.ZERO
## True only for ticks Player actually supplied a head offset -- i.e. a body is
## attached AND Player._resolve_head_node() matched something in it.
## update_effects() must gate on this rather than comparing _head_local_offset
## against a sentinel: Vector3.ZERO is exactly what a head at rest reports, so
## treating it as "no head" would misread a perfectly attached, momentarily
## still body as absent.
var _has_head: bool = false

## True while the eye is pulled back behind the body. Presentational only, in
## the strictest sense: nothing in the game reads it, no move behaves
## differently, and the rig's rotation, look clamp, bob, spin and head-follow
## all keep running exactly as they do in first person. Only the camera CHILD
## moves. See update_effects().
var third_person: bool = false

## Which side the third-person eye sits on, cycled with a middle click.
enum Shoulder { RIGHT, LEFT, CENTRED }
var _shoulder: int = Shoulder.RIGHT

## Wheel-adjusted distance, in metres. Negative until the first update seeds it
## from third_person_back, so a config change is picked up rather than being
## frozen at whatever the default was when the rig was built.
var _tp_distance: float = -1.0

## Middle-drag offset, in metres: x to the right, y up. On top of whatever the
## preset and the tuning panel say, so dragging never fights them.
var _tp_drag: Vector2 = Vector2.ZERO

## True while a level-owned cutscene (DeathSequence, currently the only
## caller) has taken the camera over. update_effects() yields entirely in
## this state -- see its own comment -- so bob/dip/crouch/look cannot fight
## the cutscene for the same transform.
var _cinematic: bool = false

## Whether a level-owned cutscene currently owns the eye. Exposed so a caller
## that decided NOT to take it -- a third-person death, which lets the body's
## own clip do the falling -- can be told apart from one that did.
func in_cinematic() -> bool:
	return _cinematic

var _cinematic_offset: Vector3 = Vector3.ZERO
var _cinematic_roll: float = 0.0
var _cinematic_pitch: float = 0.0

func setup(cfg: MovementConfig) -> void:
	_config = cfg
	position.y = cfg.camera.eye_height
	if camera != null:
		camera.fov = cfg.camera.fov_base
	# NOT loaded here. setup() runs in tests too, and a preference file left
	# by an earlier run then decides what a test starts in -- which is exactly
	# what happened: every first-person assertion failed because a previous
	# run had saved third person. A preference belongs to a session and a test
	# is not one. Arena loads it instead; see Arena._ready().

## 0 = standing, 1 = fully crouched. Driven by Player each tick.
## Metres to raise the eye by while the body is low. Player decides WHEN this is
## nonzero -- see Player.body_slide_eye_lift -- and this rig only applies it, so
## nothing here has to know which move is running.
##
## Eased the same way the crouch DROP is, and for the same reason: it is scaled
## by an amount Player sets as a hard 0 or 1, so taking it raw would jump the
## eye the moment the capsule shrank.
var _eye_lift: float = 0.0
var _eye_lift_current: float = 0.0

func set_eye_lift(metres: float) -> void:
	_eye_lift = metres

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
## The bank a vault leans through, in radians. Driven every tick by
## SpeedVaultMove across its own arc; this rig holds no timer for it.
func set_vault_roll(radians: float) -> void:
	_vault_roll = radians

## Sets the look pitch outright.
##
## For a move that TAKES OVER the pitch rather than offsetting it. SkillRoll is
## the case and so far the only one: it pins the pitch to level and carries the
## landing pitch in its own spin instead, so that when the spin is released at
## the end there is nothing left to spring back to. See SkillRollMove.enter().
func set_pitch(radians: float) -> void:
	_pitch = radians

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

## How far the attached body's head/neck node has moved from its rest pose, in
## Player's local space -- see _head_local_offset. Called by Player every tick
## a head is available.
func set_head_offset(local_offset: Vector3) -> void:
	_head_local_offset = local_offset
	_has_head = true

## Called by Player every tick NO head is available -- no body attached, or
## the attached body has nothing _resolve_head_node() could match. Must be
## called explicitly rather than relying on a timeout: a stale _has_head left
## true from a body that has since gone away would otherwise keep offsetting
## the eye by a displacement nothing is updating any more.
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
		# The presentational half of the pitch. Exposed because the two channels
		# are only correct TOGETHER -- the view shows pitch minus spin -- and a
		# test that can only see one of them cannot tell a consistent pair from a
		# flicker. See docs/camera-authority.md.
		"roll_spin": _roll_spin,
	}

func clear_look_constraint() -> void:
	# A SWEEP CANNOT OUTLIVE THE FAN IT WAS AIMED AT. Left running, it keeps
	# asking for the same step forever: a sweep is expressed in the fan's own
	# coordinates, and with no fan apply_look takes its unconstrained branch,
	# which rotates the body without ever updating _look_relative_yaw. The
	# remaining distance therefore never shrinks. Reported in play as pressing Q
	# just before a wall run ends and spinning on the spot indefinitely.
	_sweeping = false
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
	_eye_lift_current = 0.0
	_crouch_offset = 0.0
	_has_eye_ground = false
	_wall_side = 0
	_roll = 0.0
	_vault_roll = 0.0
	_landing_pitch = 0.0
	_roll_spin = 0.0
	_has_head = false
	_has_look_constraint = false
	_look_relative_yaw = 0.0
	# The one place the scripted-turn lag IS cleared: a reset is a new life,
	# and a turn half-smoothed from the old one has nothing to catch up to.
	_scripted_yaw_lag = 0.0
	_sweeping = false
	end_cinematic()
	rotation.x = 0.0
	rotation.y = 0.0
	rotation.z = 0.0
	# ONLY IN FIRST PERSON. Zeroing it while the eye is behind the body puts the
	# camera inside the head for exactly one frame -- update_effects() puts it
	# back on the very next tick, so the preference survives, but the blink
	# reads as the view having reverted. Same shape as the roll's entry flicker
	# in docs/feel-backlog.md 40: a single frame of a state nobody asked for.
	if camera != null and not third_person:
		camera.position = Vector3.ZERO
	# third_person deliberately NOT reset. It is a VIEWING PREFERENCE, not
	# movement state: someone who chose to watch their own body did not choose
	# it for one life. The owner reported dying and being put back in first
	# person, which is this line's fault and nobody else's.

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
	# The third-person pull-back is applied to the camera CHILD, on top of the
	# bob and dip rather than instead of them -- those two own position.y, and
	# overwriting it here would silently delete the walk bob whenever the view
	# was behind the body.
	var back := Vector3.ZERO
	if third_person:
		back = _third_person_position()
	camera.position = Vector3(back.x, bob - _dip + back.y, back.z)
	_apply_body_layers()

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
	# YIELDS TO THE MODEL. This drop is a stand-in for a body that is not there:
	# with no attached body the eye has to be told it went low, because nothing
	# else knows. With one, the ANIMATION knows, in more detail and with better
	# timing than a single eased number can carry.
	#
	# The owner's rule, and it reverses an earlier fix of mine: "the camera
	# serves the PICTURE, not the correctness of the numbers -- the model's neck
	# during a slide is well below the collision capsule, and that is fine."
	# Both at once was the bug (the eye reached 43 cm UNDER the floor); the
	# first fix silenced the model, which is the wrong one of the two to
	# silence.
	#
	# Scaled by how much of the head-follow is actually reaching the eye, so a
	# strength of 0 -- or no body at all -- restores this drop in full, and a
	# strength of 1 hands the whole job over.
	var follow: float = 0.0
	if _has_head:
		follow = clampf(_config.camera.camera_head_follow_strength, 0.0, 1.0)
	var target_offset: float = 		_config.camera.slide_camera_drop * _crouch_amount * (1.0 - follow)
	_crouch_offset = move_toward(_crouch_offset, target_offset, _config.camera.crouch_lerp_speed * delta)
	base_position.y -= _crouch_offset
	# The per-model lift, eased on the same clock. Applied whether or not a
	# model is driving the eye: a body low enough to need it is exactly the
	# case where the head-follow has taken over, and this is the correction for
	# where that lands.
	# ASYMMETRIC. Going down into the slide it follows the crouch like
	# everything else here; LETTING GO it takes eye_lift_release_time, because
	# the eye snapping back the instant the key comes up is a cut in the middle
	# of a half-second stand-up. See that field for why it is a time and not a
	# rate.
	var lift_target: float = _eye_lift * _crouch_amount
	var lift_rate: float = _config.camera.crouch_lerp_speed
	if lift_target < _eye_lift_current:
		lift_rate = maxf(_eye_lift, 0.0001) / maxf(_config.camera.eye_lift_release_time, 0.001)
	_eye_lift_current = move_toward(_eye_lift_current, lift_target, lift_rate * delta)
	base_position.y += _eye_lift_current

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

	# ADD the head's displacement to the eye, LAST among the base_position.*
	# writes above. Not a blend toward the head's position -- see
	# _head_local_offset for why that conflated two different things and could
	# not be made to work at any strength.
	#
	# The owner found this from a symptom rather than from the code: with a
	# body attached, its NECK kept passing through the view during a run, while
	# standing still looked perfectly fine. Their reading is exactly right --
	# if the eye rode the head, the head could never reach it, so the clipping
	# IS the measurement that it did not. Anything the eye fails to follow
	# becomes relative motion between it and the skull it is supposed to sit
	# inside, and geometry moving 9 cm past a camera that moved 1 cm is what
	# that looks like.
	#
	# Multiplying rather than lerping also keeps the degrade-to-nothing
	# guarantee that mattered before: strength 0.0 contributes exactly
	# Vector3.ZERO (any finite vector times 0.0 is exactly 0.0 in IEEE 754), so
	# it is bit-for-bit the camera this project has without a body, as is
	# _has_head being false. Clamped independently of whatever range the F1
	# panel's slider reaches, so a value pushed past 1.0 cannot overshoot the
	# head's own motion.
	if _has_head:
		var strength := clampf(_config.camera.camera_head_follow_strength, 0.0, 1.0)
		# THE MODEL OWNS THE EYE'S HEIGHT, in full. The procedural crouch drop
		# that would otherwise double-count is scaled away where it is written,
		# further up, rather than here: one of the two has to yield, and the
		# animation is the one that knows what the body is actually doing.
		position = base_position + _head_local_offset * strength
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
	rotation.z = _roll + _vault_roll

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
	#
	# AND ONLY IN FIRST PERSON. A roll turns the eye through a full revolution,
	# which is the manoeuvre when you are inside the head and nauseating when
	# you are watching from behind -- the owner's word for it was 晕. From
	# outside, the BODY doing the roll is the whole show; the camera tumbling as
	# well is the same event performed twice, once by each.
	var spin: float = 0.0 if third_person else _roll_spin
	rotation.x = clampf(_pitch - _landing_pitch, -pitch_limit, pitch_limit) - spin

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
	# Belt and braces against the same thing clear_look_constraint() guards: a
	# sweep is only meaningful while there is a fan to sweep across, and any
	# other route to losing one must not leave this running either.
	if not _has_look_constraint:
		_sweeping = false
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


## Puts the eye behind the body, pulled in if anything is in the way.
##
## The ray runs from the rig's own origin -- the head -- out to where the eye
## wants to be, so what it finds is exactly what would be between the two. The
## PLAYER is excluded: it is always in the way, being what the camera is
## looking at.
func _third_person_position() -> Vector3:
	var camera_config: CameraConfig = _config.camera
	if _tp_distance < 0.0:
		_tp_distance = camera_config.third_person_back
	# The preset decides the SIDE; third_person_right decides how far over, so
	# the panel slider still means something with a preset selected.
	var across: float = camera_config.third_person_right
	match _shoulder:
		Shoulder.LEFT:
			across = -absf(across)
		Shoulder.CENTRED:
			across = 0.0
		_:
			across = absf(across)
	var wanted := Vector3( 		across + _tp_drag.x, 		camera_config.third_person_up + _tp_drag.y, 		_tp_distance)
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var query := PhysicsRayQueryParameters3D.create( 		global_position, to_global(wanted))
	var body := get_parent()
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	# Back off from the surface by the same fraction rather than sitting exactly
	# on it: a camera flush against a wall has that wall's near plane clipping
	# through it.
	var reached: float = global_position.distance_to(hit["position"])
	var full: float = wanted.length()
	var fraction: float = clampf(reached / maxf(full, 0.001), 		_config.camera.third_person_min_fraction, 1.0)
	return wanted * fraction

## Flips between the first-person eye and the pulled-back one. Called from
## Player's own debug-key handling, alongside noclip.
func toggle_third_person() -> void:
	third_person = not third_person
	if not third_person and camera != null:
		camera.position = Vector3.ZERO


## Picks which of the body's two mesh variants this camera renders.
##
## A VRM imported with head hiding set to Layers carries both a full body and a
## generated headless one, on separate render layers. A camera renders every
## layer by default, so without this BOTH draw -- and the face and hair are
## exactly where the eye is, which is the clipping the owner reported as the
## neck passing through the view.
##
## Only the two configured layers are ever touched. Everything else, layer 1
## included, is left alone -- so the world still draws, and a body with no layer
## split at all (every non-VRM model) is completely unaffected.
	save_preferences()

func _apply_body_layers() -> void:
	if camera == null:
		return
	var first: int = _config.camera.first_person_body_layers
	var third: int = _config.camera.third_person_body_layers
	var hide: int = third if not third_person else first
	var show: int = first if not third_person else third
	camera.cull_mask = (camera.cull_mask | show) & ~hide


## Wheel: pulls the third-person eye in or pushes it out, within the configured
## range. `notches` is positive to move away.
func zoom_third_person(notches: float) -> void:
	var camera_config: CameraConfig = _config.camera
	if _tp_distance < 0.0:
		_tp_distance = camera_config.third_person_back
	_tp_distance = clampf( 		_tp_distance + notches * camera_config.third_person_zoom_step,
		camera_config.third_person_min_distance,
		camera_config.third_person_max_distance)
	save_preferences()

## Middle-drag: shifts the eye sideways and vertically, by a mouse delta in
## pixels. Deliberately UNBOUNDED except by the drag itself -- this is the
## escape hatch for a framing the presets do not cover, and clamping it would
## make it useless for exactly that.
func nudge_third_person(relative: Vector2) -> void:
	var sensitivity: float = _config.camera.third_person_drag_sensitivity
	_tp_drag.x += relative.x * sensitivity
	# Screen y grows downward; dragging DOWN should lower the eye.
	_tp_drag.y -= relative.y * sensitivity

## Middle-click: right shoulder, left shoulder, straight behind, and round
## again. Clears the drag, so the presets stay reachable however far the eye has
## been dragged -- otherwise a heavy drag makes every preset land somewhere
## else and the cycle stops meaning anything.
func cycle_third_person_shoulder() -> void:
	_shoulder = (_shoulder + 1) % Shoulder.size()
	_tp_drag = Vector2.ZERO

## Diagnostics for tests and the debug HUD.
	save_preferences()

func third_person_debug() -> Dictionary:
	return {
		"on": third_person,
		"shoulder": _shoulder,
		"distance": _tp_distance,
		"drag": _tp_drag,
	}


## Where the viewing preference is remembered between sessions.
##
## user:// rather than the project, because it is one person's preference about
## one machine's screen, not a fact about the game. Nothing here affects
## movement, so a missing or corrupt file just means the defaults.
const PREFS_PATH := "user://camera_prefs.cfg"

## Writes the third-person framing out. Called whenever it changes rather than
## on quit: a crash or a kill from the editor's stop button should not lose it,
## and the file is three numbers.
func save_preferences() -> void:
	var file := ConfigFile.new()
	file.set_value("third_person", "on", third_person)
	file.set_value("third_person", "shoulder", _shoulder)
	file.set_value("third_person", "distance", _tp_distance)
	file.set_value("third_person", "drag", _tp_drag)
	file.save(PREFS_PATH)

## Reads it back. Silently keeps the defaults when there is nothing to read,
## which is every first run.
func load_preferences() -> void:
	var file := ConfigFile.new()
	if file.load(PREFS_PATH) != OK:
		return
	third_person = bool(file.get_value("third_person", "on", third_person))
	_shoulder = int(file.get_value("third_person", "shoulder", _shoulder))
	_tp_distance = float(file.get_value("third_person", "distance", _tp_distance))
	_tp_drag = file.get_value("third_person", "drag", _tp_drag)

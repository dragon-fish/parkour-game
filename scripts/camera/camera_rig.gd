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
## Additive lift while dying -- see set_death_lift().
var _death_lift: float = 0.0
## A shake the LEVEL asked for -- see add_shake(). Amplitude and frequency are
## the original's raw numbers; CameraConfig scales them.
var _shake_amplitude: float = 0.0
var _shake_frequency: float = 0.0
## Seconds it still has to run at full, and how far in or out it currently is.
var _shake_hold: float = 0.0
var _shake_strength: float = 0.0
var _shake_phase: float = 0.0
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

## Fed every tick by BalanceMove: the roll the lost balance asks for, in
## RADIANS, already scaled by that move's own limit; and how many degrees of
## FOV the squeeze wants. Values only, like every other channel here -- this
## rig does not know what a beam is.
var _balance_roll: float = 0.0
var _balance_squeeze: float = 0.0

## The speed-driven FOV, held on its OWN field rather than read back from
## camera.fov. camera.fov also carries the balance squeeze (see
## update_effects()), and reading a squeezed value back as this lerp's own
## previous state would compound the subtraction every tick it stays applied:
## held for N ticks it converges toward target - squeeze / lerp_rate, not
## toward target - squeeze, and at the shipped fov_lerp_speed a sustained full
## lean walks the FOV straight past Camera3D's 1-degree floor. Keeping the two
## separate makes the squeeze a pure per-frame display offset with no memory
## of its own.
var _speed_fov: float = 90.0

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
## How far ahead of the capsule's axis the first-person eye sits, in metres.
## Per-model, pushed by Player from the body profile.
##
## DO NOT PUSH THE MODEL BACK OFF THE AXIS to keep the head mesh out of the
## camera instead: that leaves the body standing well short of every wall it
## faces, since the capsule -- not the model -- is what the world collides
## with. Keeping the model ON the axis and pushing the EYE forward by the same
## amount keeps the eye-to-head relation identical while the body meets the
## world where it looks like it does.
var eye_forward: float = 0.0
## A dynamic addition to eye_forward, driven per tick by moves whose visual
## lean would otherwise sweep the body through the eye (the swing). Hard-set
## by the mover, zeroed on its exit.
var extra_eye_forward: float = 0.0
## Its vertical twin -- see the swing's eye_lift_lean.
var extra_eye_lift: float = 0.0
## Its SIDEWAYS twin, positive to the body's right -- see the wall run's
## eye_off_wall. Eased rather than hard-set, because unlike the swing's two
## there is no lean easing home behind it to ride: entering and leaving a wall
## run would step the eye a third of a metre in one frame.
var extra_eye_lateral: float = 0.0
var _extra_eye_lateral_target: float = 0.0

var _head_local_offset: Vector3 = Vector3.ZERO
## Per-move scaling of the head follow (wall run halves it -- see
## WallRunConfig.head_follow_scale). Eased on the same clock the scripted
## eye weight uses, so state changes never snap the eye.
var _head_follow_scale: float = 1.0
var _head_follow_scale_target: float = 1.0
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

## A level's override of the viewing preference, or View.NONE.
##
## SEPARATE FROM third_person ON PURPOSE. toggle_third_person() writes the
## preference to disk every time it changes, so an override that shared the
## field would permanently rewrite what the player chose the first time they
## walked into a room that forces first person. Fed by Player each tick from
## the status list; nothing here reads the status list itself.
var forced_view: int = Status.View.NONE

## Which view is actually being rendered: the override if there is one, the
## saved preference otherwise. EVERY internal read of the view goes through
## this -- `third_person` alone means "what the player chose", which is not
## the same question.
## Moves the blend one frame toward the view currently in force.
##
## DO NOT snap this on a change of view: the whole point is that a level
## forcing first person, or the V key, reads as the camera travelling rather
## than cutting. It DOES snap once, on the first frame of a life, so a spawn
## does not play a blend nobody asked for.
func _advance_view_blend(delta: float) -> void:
	var wanted: float = 1.0 if in_third_person() else 0.0
	if _view_blend < 0.0:
		_view_blend = wanted
		_view_from = wanted
		_view_to = wanted
		_view_progress = 1.0
		return
	if not is_equal_approx(wanted, _view_to):
		# RESTARTED FROM WHERE THE EYE ACTUALLY IS, not from the end it was
		# heading for. A view flipped back half way has to ease out of the
		# position it had reached, or it jumps to the far end first.
		_view_from = _view_blend
		_view_to = wanted
		_view_progress = 0.0
	var seconds: float = maxf(_config.camera.view_blend_time, 0.001)
	_view_progress = move_toward(_view_progress, 1.0, delta / seconds)
	_view_blend = lerpf(_view_from, _view_to, _curve(_view_progress))

## The shape of a view change. Quintic ease-in: the eye clings to where it
## was and then leaves in a rush.
##
## Takes PROGRESS, never position -- see _view_progress. One line to change,
## and worth changing as a pair with view_blend_time, since a curve that
## spends longer near its start wants a shorter duration to read the same.
func _curve(progress: float) -> float:
	return pow(progress, 5.0)

## Where the view sits between the eye and the seat, curve already applied.
## _view_blend IS that position now -- the curve is spent in
## _advance_view_blend(), on the journey rather than on the destination.
func _eased_view_blend() -> float:
	return _view_blend

## How much screen blur the view change wants right now. Fed to ScreenEffects
## by Player -- this rig is handed values and never reaches for a node.
##
## PEAKED WHERE THE SEAM IS, not in the middle of the journey. The blur is
## here to cover the body swapping its mesh, and that lands at
## view_blend_body_swap -- which sits near the first-person end, because
## that is where the camera is close enough to the head for the swap to be
## visible at all. A blur peaking at the midpoint is heaviest out in open
## air where there was nothing to hide.
##
## Two quarter-sines meeting at that point, so it is still zero at both
## rest states and still needs no state of its own to know whether a
## transition is running. Driven off the EASED blend, the same value the
## swap itself is judged on, so the two cannot drift apart.
func view_blur() -> float:
	if _view_blend < 0.0:
		return 0.0
	var eased: float = _eased_view_blend()
	var seam: float = clampf(_config.camera.view_blend_body_swap, 0.01, 0.99)
	var rise: float = eased / seam if eased <= seam else (1.0 - eased) / (1.0 - seam)
	return sin(PI * 0.5 * rise) * _config.camera.view_blend_blur

## Where the view sits between the two seats right now: 0 is the eye, 1 is the
## third-person chair, and everything between is the journey.
##
## For anything that must COMPOSE with a view change rather than merely know
## which end it is heading for. DeathSequence is the case: asking
## in_third_person() the instant a death forces the view gets `true` while the
## eye is still in the socket, so a death framing chosen from it snapped into
## place a tenth of a second before the camera it was framing for arrived.
##
## Reads the same eased value the swap itself is judged on, so nothing driven
## off this can drift out of step with the camera.
func view_blend() -> float:
	if _view_blend < 0.0:
		return 1.0 if in_third_person() else 0.0
	return _eased_view_blend()

func in_third_person() -> bool:
	if forced_view == Status.View.FIRST:
		return false
	if forced_view == Status.View.THIRD:
		return true
	return third_person

## Which side the third-person eye sits on, cycled with a middle click.
enum Shoulder { RIGHT, LEFT, CENTRED }
var _shoulder: int = Shoulder.RIGHT
## How far across the camera actually IS, eased toward what the shoulder asks
## for. INF until the first frame seeds it, so the camera does not slide in
## from the centre when third person is first switched on.
##
## EASED, not snapped. It matters most for the wall run, which swaps sides on
## its own -- a shot that jumps across the body reads as a cut -- but the
## manual shoulder cycle benefits from it too.
var _shoulder_across: float = INF

## Where the view actually is between the eye (0) and the pulled-back seat
## (1), as opposed to which one is currently chosen. Negative means "not
## seeded yet" -- the first frame of a life snaps to whichever view is in
## force, because a blend played on spawn is a blend nobody asked for.
var _view_blend: float = -1.0

## The journey currently under way: where it started, where it is going, and
## how far through it is.
##
## THE CURVE HAS TO RIDE THIS, NOT THE POSITION. Easing an absolute 0..1
## blend looks right in one direction and backwards in the other: pow(t, 5)
## climbing from 0 starts slow, but the same expression on a t falling from
## 1 drops fastest immediately. Progress always runs 0 -> 1 whichever way
## the view is going, so a slow start is a slow start both ways.
var _view_from: float = 0.0
var _view_to: float = 0.0
var _view_progress: float = 1.0

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
## Whether the mouse still reaches the view while a cinematic runs. Off by
## default and cleared on both ends of every cinematic, so a caller that wants
## it has to ask for it inside the one it is driving.
var _cinematic_look: bool = false

## Whether a level-owned cutscene currently owns the eye. Exposed so a caller
## that decided NOT to take it -- a third-person death, which lets the body's
## own clip do the falling -- can be told apart from one that did.
func in_cinematic() -> bool:
	return _cinematic

var _cinematic_offset: Vector3 = Vector3.ZERO
var _cinematic_roll: float = 0.0
var _cinematic_pitch: float = 0.0
## The yaw the cutscene holds the rig at, radians. SEEDED FROM THE RIG's OWN
## rotation.y by begin_cinematic(), so a cutscene that never asks for a yaw is
## frozen exactly where it started -- which is what a cinematic that simply
## never wrote rotation.y already did. Only a caller that wants the camera
## AIMED somewhere other than along the body sets it.
var _cinematic_yaw: float = 0.0

func setup(cfg: MovementConfig) -> void:
	_config = cfg
	position.y = cfg.camera.eye_height
	position.z = -eye_forward
	_speed_fov = cfg.camera.fov_base
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
## The last lift actually ASKED FOR, kept after `_eye_lift` returns to zero.
##
## THE RELEASE RATE CANNOT BE COMPUTED FROM `_eye_lift`. That looks perfectly
## reasonable and is wrong: Player sets the lift to 0 the same frame the slide
## stops being the current move, so by the time the release branch below runs,
## `_eye_lift` is BY DEFINITION zero -- the rate came out at 0.0001 / 0.5 s, the
## eye came down at 0.2 mm per second, and a 0.15 m lift never visibly cleared
## again: sliding even once left the eye permanently raised.
var _eye_lift_full: float = 0.0

func set_eye_lift(metres: float) -> void:
	_eye_lift = metres
	# Only ever grows from a real request. Zero is the release signal, not a
	# new scale to release at.
	if metres > 0.0:
		_eye_lift_full = metres

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
## Lifts the eye while dying, so a head resting on the floor does not put the
## camera inside it. See CameraConfig.death_eye_lift.
func set_death_lift(metres: float) -> void:
	_death_lift = metres

func set_vault_roll(radians: float) -> void:
	_vault_roll = radians

## Sets this tick's balance lean, already converted to radians and scaled by
## the move's own limit -- see the fields this feeds. Called every tick
## BalanceMove is active; the move zeroes both on exit() so the roll and the
## squeeze cannot follow the player off the beam.
func set_balance_lean(roll_radians: float, squeeze_deg: float) -> void:
	_balance_roll_target = roll_radians
	_balance_squeeze_target = squeeze_deg

## What set_balance_lean() last asked for; _balance_roll / _balance_squeeze
## are eased toward these in update_effects() on
## CameraConfig.balance_recover_time.
var _balance_roll_target: float = 0.0
var _balance_squeeze_target: float = 0.0

## Pulls the third-person camera off the shoulder to the centre, or lets it
## back out. Pushed every tick by MoveManager from the active move's
## MoveConfig.centre_shoulder; eased by _shoulder_across's own move_toward
## in update_effects(), the same slide the shoulder cycle makes.
func set_shoulder_centred(centred: bool) -> void:
	_shoulder_centred_by_move = centred

var _shoulder_centred_by_move: bool = false

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
	# HELD SHORT IN FIRST PERSON, and the reason is a first-person one: a lag
	# is a softening, not a detour. Past a certain size the eye is no longer
	# trailing the turn, it is pointing somewhere else entirely -- at the inside
	# of whatever the body is pressed against. Reported in play as the view
	# lunging into the wall and then snapping back to the ledge.
	#
	# AND IT IS NOT A FIRST-PERSON RULE, WHICH IS WHAT TWO ATTEMPTS AT AN
	# EXCEPTION FOR THIRD PERSON ESTABLISHED. Holding a third-person camera
	# still through a ninety-degree ledge corner works exactly as intended and
	# is unplayable anyway: the player steers the BODY with the camera, so a
	# view left a quarter-turn off the wall means their next mouse movement
	# turns the body away from it -- straight into the one-handed lock, which
	# then refuses the shimmy they were trying to continue. Without the eye
	# following the turn, that lock triggers on almost every corner past 45
	# degrees, which reads as the game refusing input for no reason.
	#
	# The eye's facing during a hang is not a viewing preference. It is an INPUT
	# to the move.
	var cap: float = _config.camera.scripted_yaw_max_lag
	_scripted_yaw_lag = clampf(_scripted_yaw_lag - radians, -cap, cap)

## How far the attached body's head/neck node has moved from its rest pose, in
## Player's local space -- see _head_local_offset. Called by Player every tick
## a head is available.
## Sets where the head follow is headed, per move -- 1.0 everywhere except
## the states that ask for less. Eased in update_effects().
## Slides the first-person eye sideways, positive to the body's right. Set
## every tick by whoever wants it and to zero by everyone else, exactly like
## set_head_follow_scale() beside it.
func set_eye_lateral(target: float) -> void:
	_extra_eye_lateral_target = target

func set_head_follow_scale(target: float) -> void:
	_head_follow_scale_target = clampf(target, 0.0, 1.0)

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
## Scales one tick of look input down as it runs out of room, so a limit is
## felt before it is reached instead of arriving as a stop.
##
## `room` is how far the view may still travel THE WAY IT IS GOING. Negative
## room means the view is already outside -- which never happens by pushing,
## only by the limit itself moving (a fan re-centring on a wall, a pitch floor
## rising). Those cases have their own easing and must not be damped on top:
## damping there would fight the very motion bringing the view back, so the
## input is passed through untouched.
func _damped_look(step: float, room: float) -> float:
	if step == 0.0 or _config == null:
		return step
	var half: float = deg_to_rad(_config.camera.look_damp_half_deg)
	# Negative room is passed through: see this function's own note.
	if half <= 0.0 or room < 0.0:
		return step
	return step * (room / (room + half))

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
	# DO NOT CLAMP HERE and hand the correction to absorb_body_yaw's lag instead:
	# that only works for small corrections, because the lag is capped at
	# 0.35 rad, and attaching at the forward branch's full 57 degrees is nearly
	# twice that, so most of the turn would arrive as a cut anyway.
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
## Lets the mouse turn the view during the cinematic this rig is already in.
## The POSE stays the caller's -- offset, roll and pitch keep arriving through
## set_cinematic_pose(); only the player's own yaw and pitch come back.
func allow_cinematic_look(allowed: bool) -> void:
	_cinematic_look = allowed

func begin_cinematic() -> void:
	_cinematic = true
	_cinematic_look = false
	_cinematic_yaw = rotation.y

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

## Aims the cutscene camera sideways: `radians` is rotation.y, measured in the
## body's own frame. A shot that looks AT the body rather than along it needs
## this -- the rig otherwise faces wherever the body faces, so an offset alone
## puts the camera beside her looking past her.
func set_cinematic_yaw(radians: float) -> void:
	_cinematic_yaw = radians

## Hands the camera back. Resets the cutscene offset/roll to neutral so a
## stale pose cannot linger into the next update_effects() call before that
## call has a chance to recompute its own transform.
func end_cinematic() -> void:
	_cinematic_look = false
	_cinematic = false
	_cinematic_offset = Vector3.ZERO
	_cinematic_roll = 0.0
	_cinematic_pitch = 0.0
	_cinematic_yaw = 0.0

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
	_eye_lift_full = 0.0
	_crouch_offset = 0.0
	_has_eye_ground = false
	_wall_side = 0
	_shoulder_centred_by_move = false
	_roll = 0.0
	_vault_roll = 0.0
	_balance_roll = 0.0
	_balance_squeeze = 0.0
	_balance_roll_target = 0.0
	_balance_squeeze_target = 0.0
	if _config != null:
		_speed_fov = _config.camera.fov_base
	_death_lift = 0.0
	_landing_pitch = 0.0
	_roll_spin = 0.0
	clear_shake()
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
	if camera != null and not in_third_person():
		camera.position = Vector3.ZERO
	# Re-seeded, not eased: a respawn must not play the journey between views.
	_view_blend = -1.0
	_view_progress = 1.0
	# third_person deliberately NOT reset. It is a VIEWING PREFERENCE, not
	# movement state: someone who chose to watch their own body did not choose
	# it for one life. The owner reported dying and being put back in first
	# person, which is this line's fault and nobody else's.

## Yaw turns the body so movement follows the view; pitch stays on the rig.
##
## The ACTIVE MOVE's own clamp wins over the global pitch limit when it
## declares one. The original makes this per-move data (MinLookConstraint /
## MaxLookConstraint) [ME:CONFIRMED 06 §6.2], and it is a genuine input
## constraint: on a wall the view is locked into a +-90 degree yaw fan
## [ME:CONFIRMED 04 §4.1] and cannot look back, which is where that whole
## sensation comes from.
func apply_look(look_delta: Vector2, body: Node3D, delta: float = 0.0) -> void:
	# A cinematic normally owns the view outright. The exception is a body that
	# has finished falling and is lying there -- see DeathSequence, which hands
	# the mouse back for that stretch while keeping its own pose.
	if _cinematic and not _cinematic_look:
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
		# the player. [ME:CONFIRMED 04 §4.1] bUseAbsoluteYawConstraint = True.
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
			# Damped against the edge the view is heading FOR, and against the
			# EASED edge rather than the declared one, so a fan still moving in to
			# meet the view is not also resisting it.
			var room: float = high - _look_relative_yaw
			if yaw_delta <= 0.0:
				room = _look_relative_yaw - low
			yaw_delta = _damped_look(yaw_delta, room)
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
	var pitch_step: float = -look_delta.y * _config.camera.mouse_sensitivity
	# Damped the same way as the yaw above, against the DECLARED floor: the
	# eased floor is computed below, and _damped_look() passes negative room
	# through untouched, so a floor still rising to meet the view resists
	# nothing.
	var pitch_room: float = pitch_max - _pitch
	if pitch_step <= 0.0:
		pitch_room = _pitch - pitch_min
	pitch_step = _damped_look(pitch_step, pitch_room)
	var wanted: float = _pitch + pitch_step
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

## `stride_speed` is how fast the body is WALKING, for the bob: the same as
## `horizontal_speed` on its feet, 0 on a slide (MoveConfig.footfall_bob).
## Negative means "the same", which is what every caller that knows nothing
## of strides wants.
func update_effects(delta: float, horizontal_speed: float, grounded: bool, stride_speed: float = -1.0) -> void:
	if _config == null or camera == null:
		return

	# While cinematic, this function yields entirely: bob, dip, crouch and the
	# head-follow blend all step aside, and the pose comes straight from
	# whatever the cutscene last passed to set_cinematic_pose(). Without this
	# the death sequence would fight running sway for the same transform.
	if _cinematic:
		position = Vector3(0.0, _config.camera.eye_height, -eye_forward) + _cinematic_offset
		rotation.z = _cinematic_roll
		rotation.x = _cinematic_pitch
		rotation.y = _cinematic_yaw
		return

	# Where the rig would sit this frame with NO head-follow applied,
	# recomputed from scratch every call rather than read back from last
	# frame's `position`. This is what makes camera_head_follow_strength mean
	# the same thing on every axis: DO NOT let X/Z inherit whatever the
	# PREVIOUS frame's lerp already blended them to while giving Y a fresh base
	# every frame (via the eye_height re-apply below) -- that asymmetry lets
	# the head-follow lerp at the bottom of this function blend toward the head
	# from an ever-more-converged starting point on X/Z, which is an
	# exponential approach to the head regardless of how small `strength` is,
	# while Y (reset fresh every frame) genuinely holds at the configured
	# fraction. Composing every other contribution below into `base_position`
	# instead of `position` keeps that guarantee on all three axes: `position`
	# itself is written exactly once, at the very end of this function.
	# Advanced BEFORE anything reads it, so every offset composed this frame
	# describes one consistent point on the journey rather than two.
	_advance_view_blend(delta)

	var base_position := Vector3.ZERO
	base_position.y = _config.camera.eye_height + extra_eye_lift
	# Faded rather than switched. At blend 0 this is exactly the old
	# first-person expression and at blend 1 it is exactly the old
	# third-person zero, so neither end moved; the eye simply retreats to the
	# head as the seat pulls back, instead of teleporting there.
	base_position.z = -(eye_forward + extra_eye_forward) * (1.0 - _eased_view_blend())
	# Faded out of third person for the same reason the forward offset is: it
	# exists to put the FIRST-PERSON eye where the model's head already is, and
	# the pulled-back seat is looking at that head from outside.
	base_position.x = extra_eye_lateral * (1.0 - _eased_view_blend())

	var speed_ratio := clampf(horizontal_speed / maxf(_config.camera.fov_speed_ref, 0.001), 0.0, 1.0)

	var target_fov := lerpf(_config.camera.fov_base, _config.camera.fov_max, speed_ratio)
	_speed_fov = lerpf(_speed_fov, target_fov, clampf(_config.camera.fov_lerp_speed * delta, 0.0, 1.0))
	# Balance's own tension cue -- simulated fear of heights, tied to how far the
	# lean has gone rather than to a constant on entry. SUBTRACTED here, after
	# the speed lerp above rather than folded into it: that channel OPENS the
	# view as speed rises, and the squeeze must survive a state that stays slow
	# the whole time, so leaving it to the speed curve would widen the view at
	# exactly the moment lost balance should be closing it in.
	#
	# APPLIED TO A DISPLAY VALUE, NOT FED BACK INTO _speed_fov's OWN LERP.
	# _speed_fov must hold the UNSQUEEZED value across ticks -- subtracting into
	# the same field the lerp reads back next frame compounds every tick the
	# squeeze stays applied, and at this rig's own fov_lerp_speed a lean held
	# for a third of a second walks the FOV past Camera3D's 1-degree floor,
	# where set_fov() starts silently rejecting the write. floored at 1.0 for
	# the same reason: a larger fov_squeeze_deg than today's must still miss
	# that floor rather than trip it.
	# EASED, on their own clock -- see CameraConfig.balance_recover_time for
	# the exit snap this exists to remove. Exponential rather than
	# move_toward, so the roll and the squeeze arrive together whatever their
	# sizes.
	var balance_ease: float = 1.0 - exp(-delta / maxf(_config.camera.balance_recover_time, 0.001))
	_balance_roll = lerpf(_balance_roll, _balance_roll_target, balance_ease)
	_balance_squeeze = lerpf(_balance_squeeze, _balance_squeeze_target, balance_ease)
	camera.fov = maxf(_speed_fov - _balance_squeeze, 1.0)

	var bob_target := 1.0 if grounded else 0.0
	_bob_weight = move_toward(_bob_weight, bob_target, _config.camera.bob_fade_speed * delta)

	var stride: float = horizontal_speed if stride_speed < 0.0 else stride_speed
	var stride_ratio := clampf(stride / maxf(_config.camera.fov_speed_ref, 0.001), 0.0, 1.0)
	if grounded:
		_bob_phase += delta * _config.camera.bob_frequency * stride
	# The phase freezes while airborne, so the offset it produces here holds
	# steady from the moment of leaving the ground; _bob_weight is what fades
	# it toward zero instead of letting it vanish in a single frame.
	var bob := sin(_bob_phase) * _config.camera.bob_amplitude * stride_ratio * _bob_weight

	_dip = move_toward(_dip, 0.0, _config.camera.land_dip_recover * delta)
	# The third-person pull-back is applied to the camera CHILD, on top of the
	# bob and dip rather than instead of them -- those two own position.y, and
	# overwriting it here would silently delete the walk bob whenever the view
	# was behind the body.
	var back := Vector3.ZERO
	if _view_blend > 0.0:
		# EASED HERE, where there is a delta -- _third_person_position() is also
		# reached from tests and from the debug readout, and neither has one.
		var wanted_across: float = _wanted_shoulder_across()
		if is_inf(_shoulder_across):
			_shoulder_across = wanted_across
		else:
			var span: float = maxf(absf(_config.camera.third_person_right), 0.0001)
			var rate: float = (span * 2.0) / maxf(_config.camera.third_person_shoulder_time, 0.001)
			_shoulder_across = move_toward(_shoulder_across, wanted_across, rate * delta)
		back = _third_person_position() * _eased_view_blend()
	camera.position = Vector3(back.x, bob - _dip + back.y, back.z)
	# The eye looks wherever the view looks: this rig sets camera.position and
	# never its rotation. Every third-person move keeps the camera on the
	# view's own axis, behind the body, so there is nothing to re-aim.
	camera.rotation = Vector3.ZERO
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
	# THE PICTURE WINS OVER THE NUMBERS: the model's neck sitting well below the
	# collision capsule during a slide is fine on its own. What is NOT fine is
	# the eye ALSO tracking that same low number -- that was the actual bug (the
	# eye reached 43 cm UNDER the floor). DO NOT fix a recurrence of this by
	# hiding the model; the eye is the one of the two that has to give.
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
		# _eye_lift_full, NOT _eye_lift -- see that field. A CONSTANT rate, so a
		# full lift takes exactly eye_lift_release_time and a slide abandoned
		# half way down takes proportionally less; a 2 cm remainder crawling
		# for the same half second would read as a stall, not a release.
		lift_rate = maxf(_eye_lift_full, 0.0001) / maxf(_config.camera.eye_lift_release_time, 0.001)
	_eye_lift_current = move_toward(_eye_lift_current, lift_target, lift_rate * delta)
	base_position.y += _eye_lift_current
	# Straight addition, not eased: the death is a cut into a cutscene anyway,
	# and half a second of the eye rising out of the floor is worse than being
	# in the right place from the first frame.
	base_position.y += _death_lift

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
		# A moving platform carries the eye 1:1. The lag below is for the
		# body's OWN changes of height, a step up or a floor snap; a lift is
		# something else moving the body (docs/camera-authority.md), and a
		# lift at speed lagged by the whole step cap put the eye in the neck.
		var body := get_parent() as CharacterBody3D
		if body != null:
			_eye_ground_y += body.get_platform_velocity().y * delta
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
	var scale_t: float = 1.0 - exp(-delta / maxf(
		_config.camera.scripted_eye_offset_blend_time, 0.001))
	_head_follow_scale = lerpf(_head_follow_scale, _head_follow_scale_target, scale_t)
	extra_eye_lateral = lerpf(extra_eye_lateral, _extra_eye_lateral_target, scale_t)
	if _has_head:
		var strength := clampf(_config.camera.camera_head_follow_strength, 0.0, 1.0) \
			* _head_follow_scale
		# THE MODEL OWNS THE EYE'S HEIGHT, in full. The procedural crouch drop
		# that would otherwise double-count is scaled away where it is written,
		# further up, rather than here: one of the two has to yield, and the
		# animation is the one that knows what the body is actually doing.
		position = base_position + _head_local_offset * strength
	else:
		position = base_position
	# LAST, and added to whatever the rest of this function settled on: a shake
	# is a displacement of the finished eye, not one more thing for the head
	# follow and the step smoothing to chase.
	position += _shake_offset(delta)

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
	# The direction is [ME:INFERRED 09 §9.1]: that section judges "roll toward
	# the wall" correct, but also records that the original defines NO VALUE for
	# this field at all, so the direction is the researcher's inference rather
	# than extracted data. Played both ways, this direction (clockwise on a left
	# wall) is the one that reads correctly, and it stands over the inference.
	#
	# tests/legacy/test_camera_rig.gd's test_the_camera_rolls_toward_the_wall_
	# side asserts the OPPOSITE direction -- it is ARCHIVED and NOT in the
	# running suite, so it does not fail the build, but rewrite it to match this
	# direction if the legacy suite is ever restored.
	var target_roll := deg_to_rad(_config.camera.wall_camera_roll_deg) * float(_wall_side)
	_roll = move_toward(_roll, target_roll, deg_to_rad(_config.camera.wall_camera_roll_speed) * delta)
	# Softened in third person: the horizon tipping IS the balance feedback in
	# first person, but seen from outside the same roll tips the whole world
	# around a character who is already visibly leaning, which reads as nausea
	# rather than information. The body's own lean carries the signal there.
	var balance_roll: float = _balance_roll
	if in_third_person():
		balance_roll *= _config.camera.third_person_balance_roll_scale
	rotation.z = _roll + _vault_roll + balance_roll

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
	# you are watching from behind. From outside, the BODY doing the roll is the
	# whole show; the camera tumbling as well is the same event performed
	# twice, once by each.
	var spin: float = 0.0 if in_third_person() else _roll_spin
	rotation.x = clampf(_pitch - _landing_pitch, -pitch_limit, pitch_limit) - spin

## Drops the landing dip on the floor, unrecovered.
##
## A DEATH SKIPS THE ORDINARY LANDING CUSHION. A fatal fall lands like any
## other -- punch_landing() has already fired by the time the death is known,
## because died_from_fall is deferred a frame -- and the eye would otherwise
## ease up out of a flinch nobody is going to walk away from. In first person
## the cinematic pose overwrites it anyway; in third person, which does not
## take the cinematic, this is what stops it being the only thing still moving.
func clear_landing_dip() -> void:
	_dip = 0.0
	_landing_pitch = 0.0

## Called on landing. `speed` is the downward speed at the moment of impact.
func punch_landing(speed: float) -> void:
	if _config == null:
		return
	var strength := clampf(speed / maxf(_config.camera.land_dip_speed_ref, 0.001), 0.0, 1.0)
	_dip = maxf(_dip, strength * _config.camera.land_dip_max)


## The level asking the eye to shake: something heavy is passing close.
##
## `amplitude` and `frequency` are the ORIGINAL's own numbers, unconverted --
## CameraConfig.shake_amplitude_scale and shake_frequency_scale turn them into
## metres and hertz. `hold` is how long it runs at full before dying away.
##
## THE LEVEL IS MOVING THE EYE, not the player, so it eases in and out rather
## than switching (docs/camera-authority.md). A louder shake arriving mid-shake
## takes over; a quieter one does not cut the first one short.
func add_shake(amplitude: float, frequency: float, hold: float) -> void:
	if amplitude <= 0.0 or frequency <= 0.0:
		return
	if amplitude >= _shake_amplitude:
		_shake_amplitude = amplitude
		_shake_frequency = frequency
	_shake_hold = maxf(_shake_hold, hold)


## Kills the shake without easing. For a respawn, where the eye is elsewhere
## and nothing that was passing is passing any more.
func clear_shake() -> void:
	_shake_hold = 0.0
	_shake_strength = 0.0
	_shake_amplitude = 0.0
	_shake_frequency = 0.0
	_shake_phase = 0.0


## The eye's displacement from the shake this tick, in the camera's own frame,
## advanced by `delta`. Zero and free when nothing is shaking.
func _shake_offset(delta: float) -> Vector3:
	if _shake_hold <= 0.0 and _shake_strength <= 0.0:
		return Vector3.ZERO
	var rising := _shake_hold > 0.0
	_shake_hold = maxf(_shake_hold - delta, 0.0)
	var seconds: float = _config.camera.shake_attack if rising else _config.camera.shake_release
	var step := 1.0 if seconds <= 0.0 else delta / seconds
	_shake_strength = clampf(_shake_strength + (step if rising else -step), 0.0, 1.0)
	if _shake_strength <= 0.0:
		clear_shake()
		return Vector3.ZERO
	var hz: float = _shake_frequency * _config.camera.shake_frequency_scale
	_shake_phase += delta * hz
	var metres: float = _shake_amplitude * _config.camera.shake_amplitude_scale * _shake_strength
	# Two axes at rates that do not divide into each other, so the eye traces a
	# wandering figure rather than a line: a single sine reads as the camera
	# being dragged, not as the ground shaking.
	return Vector3(sin(_shake_phase * TAU) * metres,
		sin(_shake_phase * TAU * 1.37 + 1.1) * metres, 0.0)

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
## Radians per second this sweep crosses at. See sweep_look_to().
var _sweep_speed: float = 0.0
## How far the mouse has turned the view since this sweep began, radians,
## either way. See _advance_look_sweep().
var _sweep_hand: float = 0.0

## Starts carrying the view to `relative_yaw`, measured in the same frame as
## _look_relative_yaw: radians from the fan's own centre.
##
## Silently does nothing with no constraint in force. A sweep is expressed in a
## fan's coordinates, and without a fan there is no target to name.
##
## `speed` in radians per second; CameraConfig.look_sweep_speed when not given.
func sweep_look_to(relative_yaw: float, speed: float = -1.0) -> void:
	if not _has_look_constraint:
		return
	_sweep_to = clampf(relative_yaw, _look_min.y, _look_max.y)
	_sweep_speed = speed if speed > 0.0 else _config.camera.look_sweep_speed
	_sweep_hand = 0.0
	_sweeping = true

## Q where Q is a mouse flick: the view carried half a turn clockwise at
## CameraConfig.q_flick_time's pace, stopping at the fan's edge as a hand
## would. Asked by MoveManager for a move that says so (Move.can_flick_view()).
func flick_half_turn() -> void:
	if not _has_look_constraint or _config == null:
		return
	sweep_look_to(_look_relative_yaw - PI, PI / maxf(_config.camera.q_flick_time, 0.001))

func is_sweeping() -> bool:
	return _sweeping

func cancel_look_sweep() -> void:
	_sweeping = false

## Advances a running sweep. Returns the yaw delta to apply this tick, or 0.
##
## THE PLAYER'S OWN HAND WINS, once it means it. A deliberate movement -- more
## than CameraConfig.look_sweep_hand_deg since the sweep began -- cancels it on
## the spot rather than fighting it: this is a convenience for a flick the
## player could have done themselves, and a convenience that resists being
## overridden is worse than none. Less than that rides along on top of it.
##
## DO NOT go back to cancelling on any movement at all. A hand on a mouse is
## never perfectly still: one count of drift, 0.13 degrees, stopped a wall
## run's quarter-turn sweep at 14 degrees, nearly every time.
func _advance_look_sweep(mouse_yaw_delta: float, delta: float) -> float:
	if not _sweeping:
		return 0.0
	# Belt and braces against the same thing clear_look_constraint() guards: a
	# sweep is only meaningful while there is a fan to sweep across, and any
	# other route to losing one must not leave this running either.
	if not _has_look_constraint:
		_sweeping = false
		return 0.0
	_sweep_hand += absf(mouse_yaw_delta)
	if _sweep_hand > deg_to_rad(_config.camera.look_sweep_hand_deg):
		_sweeping = false
		return 0.0
	var remaining: float = _sweep_to - _look_relative_yaw
	var step: float = _sweep_speed * delta
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
## Where the shoulder preset -- or a wall run's borrowed one -- wants the
## camera, before easing. The PRESET decides the side; third_person_right
## decides how far over, so the panel slider still means something.
func _wanted_shoulder_across() -> float:
	# A move standing beside a wall asks for the centre -- see
	# MoveConfig.centre_shoulder. Eased there by the caller's move_toward, so
	# the slide in and back out is the shoulder cycle's own.
	if _shoulder_centred_by_move:
		return 0.0
	var across: float = _config.camera.third_person_right
	# A WALL RUN BORROWS THE OTHER SHOULDER: on a left-hand wall, the camera
	# takes the preset RIGHT shoulder for the duration, and the other way round
	# -- otherwise the view sits inside the wall the whole time.
	#
	# The collision probe in _third_person_position() already pulls the camera
	# in when something is between it and the body, but pulling in is the wrong
	# answer here: it gives a shot pressed flat against a surface that is going
	# to be there for the whole manoeuvre. Standing on the other side of the
	# body is.
	#
	# DO NOT WRITE THIS INTO _shoulder. That is the player's own preference and
	# it is persisted -- borrowing it here would leave a wall run quietly
	# rewriting a setting, and cycling it mid-run would fight this. wall_side is
	# cleared on exit, so the preference comes back on its own.
	var shoulder: int = _shoulder
	if _wall_side != 0:
		# wall_side > 0 is a RIGHT-hand wall (WallRunMove's own look-fan code
		# says so), so the camera wants the left.
		shoulder = Shoulder.LEFT if _wall_side > 0 else Shoulder.RIGHT
	match shoulder:
		Shoulder.LEFT:
			return -absf(across)
		Shoulder.CENTRED:
			return 0.0
	return absf(across)

func _third_person_position() -> Vector3:
	var camera_config: CameraConfig = _config.camera
	if _tp_distance < 0.0:
		_tp_distance = camera_config.third_person_back
	# EASED, not switched -- see _shoulder_across. Seeded on the first frame so
	# switching to third person does not slide the camera in from the centre.
	if is_inf(_shoulder_across):
		_shoulder_across = _wanted_shoulder_across()
	var across: float = _shoulder_across
	var wanted := Vector3( 		across + _tp_drag.x, 		camera_config.third_person_up + _tp_drag.y, 		_tp_distance)
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	# A SPHERE, NOT A RAY. A ray asks whether the camera's exact centre is clear,
	# and the camera is not a point: the near plane has width, so a centre
	# resting on a surface puts half the shot inside it. Worse, a ray threads
	# gaps -- through a corner seam or a railing -- and reports the far side
	# clear while the camera lands wholly inside the geometry it slipped past.
	# CameraConfig.third_person_probe_radius is the sphere, and the clearance.
	#
	# cast_motion, not intersect_ray plus a hand-rolled pull-back: it returns
	# the SAFE fraction, stopping the sphere short of contact rather than on it,
	# which is exactly the margin wanted here. Same call and the same reading of
	# it as Probes._plant_top(), which has the pothole notes.
	var sphere := SphereShape3D.new()
	sphere.radius = _config.camera.third_person_probe_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = to_global(wanted) - global_position
	query.collision_mask = _config.camera.third_person_probe_mask
	var body := get_parent()
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var fractions: PackedFloat32Array = space.cast_motion(query)
	# An EMPTY result means the sphere started already overlapping something --
	# the head itself is against a wall. Treated as "no room at all" rather than
	# as "all clear": the min_fraction clamp below is what keeps the camera off
	# the head, and it is the same answer a ray hitting immediately gave.
	if fractions.size() < 2:
		return wanted * _config.camera.third_person_min_fraction
	if fractions[0] >= 1.0:
		return wanted
	var fraction: float = clampf(fractions[0], 		_config.camera.third_person_min_fraction, 1.0)
	return wanted * fraction

## Flips between the first-person eye and the pulled-back one. Called from
## Player's V key. Saved, because the choice outlives the life it was made in.
func toggle_third_person() -> void:
	# Refused rather than queued: a level that forces a view is mid-scripted
	# moment, and a preference silently changed under the player would surface
	# only after they leave, which reads as the key having been eaten.
	if forced_view != Status.View.NONE:
		return
	third_person = not third_person
	# DO NOT zero camera.position here. update_effects() owns it, and it
	# places it from the view blend every frame. Writing it directly puts
	# the eye inside the head for the one frame before the blend is next
	# evaluated, which reads as the view snapping in and flashing back out
	# before the transition plays.
	save_preferences()


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
## Whether the third-person body is the one on screen: the same point in the
## view blend as the layer swap below, where the camera is furthest from both.
func shows_third_person_body() -> bool:
	return _eased_view_blend() >= _config.camera.view_blend_body_swap

func _apply_body_layers() -> void:
	if camera == null:
		return
	var first: int = _config.camera.first_person_body_layers
	var third: int = _config.camera.third_person_body_layers
	# Judged on the BLEND, not on which view is chosen: the swap is a pop
	# wherever it lands, so it belongs at the point in the journey where the
	# camera is furthest from the head it is revealing or hiding.
	var behind: bool = _eased_view_blend() >= _config.camera.view_blend_body_swap
	var hide: int = third if not behind else first
	var show: int = first if not behind else third
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
		"forced_view": forced_view,
		"shoulder": _shoulder,
		"distance": _tp_distance,
		"drag": _tp_drag,
	}


## Where the viewing preference is remembered between sessions.
##
## user:// rather than the project, because it is one person's preference about
## one machine's screen, not a fact about the game. Nothing here affects
## movement, so a missing or corrupt file just means the defaults.
##
## Injectable rather than a const, the same way SettingsStore.path is: a test
## points this at its own file so the suite never reads, writes or deletes the
## player's real preferences.
static var prefs_path := "user://camera_prefs.cfg"

## Writes the third-person framing out. Called whenever it changes rather than
## on quit: a crash or a kill from the editor's stop button should not lose it,
## and the file is three numbers.
func save_preferences() -> void:
	var file := ConfigFile.new()
	file.set_value("third_person", "on", third_person)
	file.set_value("third_person", "shoulder", _shoulder)
	file.set_value("third_person", "distance", _tp_distance)
	file.set_value("third_person", "drag", _tp_drag)
	file.save(prefs_path)

## Reads it back. Silently keeps the defaults when there is nothing to read,
## which is every first run.
func load_preferences() -> void:
	var file := ConfigFile.new()
	if file.load(prefs_path) != OK:
		return
	third_person = bool(file.get_value("third_person", "on", third_person))
	_shoulder = int(file.get_value("third_person", "shoulder", _shoulder))
	_tp_distance = float(file.get_value("third_person", "distance", _tp_distance))
	_tp_drag = file.get_value("third_person", "drag", _tp_drag)

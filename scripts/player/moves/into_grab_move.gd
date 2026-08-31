class_name IntoGrabMove
extends Move

# [ME:CONFIRMED] The original's TdMove_IntoGrab: the reach between catching a
# ledge and hanging from it.
#
# The body is carried to a FIXED pose relative to the edge at a FIXED rate,
# [ME:CONFIRMED] IntoGrabAlignSpeed = 3 m/s. The pose itself is NOT the
# original's raw GrabDesiredLedgeOffset taken literally -- see
# IntoGrabConfig.ledge_back_offset and .eye_below_ledge for why both numbers
# had to be re-derived for this project's own capsule and eye height. Every
# hang ends up looking identical however it was caught, and a reach that has
# further to travel takes proportionally longer: the duration is a
# consequence of the geometry, not a setting.
#
# DO NOT let the body simply freeze wherever it made contact -- that leaves
# the player hanging in mid-air a long way out from the wall.
#
# Deliberately NOT a ScriptedMove: that base interpolates over a fixed
# DURATION, and the whole character of this manoeuvre is a fixed SPEED with the
# duration falling out of the distance.

var _aborted: bool = false
var _target: Vector3 = Vector3.ZERO
## The yaw that faces the wall. The body turns to it during the reach, and the
## view's fan is re-centred on it once there.
var _target_yaw: float = 0.0
var _reach_time: float = 0.0
## False until a hand actually reaches the wall. Until then this move runs the
## APPROACH phase and does not touch the body at all -- see
## docs/contact-drives-movement.md.
var _touched: bool = false
## Where the wall's face was when the reach was committed. See Move.touching().
var _face_point: Vector3 = Vector3.ZERO

func enter(_previous: StringName) -> void:
	# Declared, not read: this move drives the body directly and never calls
	# move_and_slide(), so is_on_floor() would report whatever the previous
	# move left behind. Same reasoning as SpeedVaultMove and GrabMove.
	player.set_grounded(false)
	_aborted = false
	_reach_time = 0.0
	_touched = false
	# NO velocity = ZERO here, deliberately. The commit has been made and the
	# reach is winding up, but nothing has been touched yet, so the body keeps
	# its own arc. Killing it here is what made a grab read as a magnet: from
	# the instant the probe SAW the ledge, the body was being dragged toward it
	# through open air. See docs/contact-drives-movement.md.

	var query: Dictionary = player.probes.ledge_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query["valid"]:
		# Nothing to reach for. There is no safe position to invent here, so
		# invent none -- physics_update() hands straight back to Falling.
		_aborted = true
		return
	# TOO FAR EVEN TO COMMIT. The approach phase below will wait for contact,
	# but there has to be a bound on how far away that wait may start from, or
	# a ledge merely visible across a courtyard begins a reach that then spends
	# max_duration failing to arrive.
	#
	# Measured to the WALL, matching AirborneMove._within_reach() -- `edge` sits
	# on the ledge's top and can be well behind the face the body would touch.
	if float(query.get("face_distance", INF)) > cfg.max_reach_distance:
		_aborted = true
		return
	query = _slid_into_the_safe_zone(query)
	var gap: Vector3 = query["edge"] - player.global_position
	gap.y = 0.0
	_target = hanging_pose(player, config, query)
	# Square to the WALL's face, not toward the edge point.
	#
	# DO NOT face the edge point -- it is wrong whenever the ledge was
	# approached at an angle: the edge is a point on the ledge's TOP, off to
	# one side of the wall it belongs to, so aiming at it leaves the body
	# skewed by exactly the angle it arrived at. This shows up in the HUD as
	# the view reporting square (yaw -1) while the wall is visibly tens of
	# degrees off.
	var face_normal: Vector3 = query.get("face_normal", Vector3.ZERO)
	face_normal.y = 0.0
	if face_normal.length_squared() > 0.0001:
		# The normal points back at the body, so facing the wall means facing
		# the way it came from.
		face_normal = face_normal.normalized()
		_target_yaw = atan2(face_normal.x, face_normal.z)
	elif gap.length_squared() > 0.0001:
		_target_yaw = atan2(-gap.x, -gap.z)
	else:
		_target_yaw = player.rotation.y
	# Handed to GrabMove rather than re-queried there: once this reach
	# finishes, the body can no longer see the edge it is hanging from.
	player.pending_ledge = query
	_face_point = query.get("face_point", Vector3.ZERO)


## The lateral offsets to try, nearest first and alternating sides.
##
## Nearest-first is the whole rule: a grab aimed at the bleed zone should move
## the SHORTEST distance that makes it legal, never to the middle of the ledge.
## Alternating sides so an equal distance either way is a coin toss rather than
## a bias toward one hand.
static func search_offsets(limit: float, samples: int) -> Array[float]:
	var out: Array[float] = [0.0]
	if limit <= 0.0 or samples <= 0:
		return out
	var step: float = limit / float(samples)
	for i in range(1, samples + 1):
		out.append(step * float(i))
		out.append(-step * float(i))
	return out

## How many offsets are tried on each side. Four puts a candidate every 0.1 m
## across a 0.4 m bleed zone, which is finer than the hands can be aimed.
const SAFE_ZONE_SAMPLES: int = 4

## Slides the caught edge along the wall to the nearest place a hanging body
## actually fits, and hands back the query pointing there.
##
## EVERY GRABBABLE LIP HAS A SAFE ZONE AND TWO BLEED ZONES, and the bleed is
## ONE CAPSULE RADIUS wide. That is not a chosen number: the safe zone is where
## the body's centre line can sit, so it ends exactly a radius short of each
## corner. A 1.15 m duct mouth against a 0.8 m body leaves 0.35 m of safe zone
## and 0.4 m of bleed either side.
##
## DO NOT USE shimmy_body_half_width HERE, which was tried. It measures how far
## a MOVING hand reaches past the shoulder it hangs from -- 0.55, deliberately
## wider than the body -- so demanding it either side wanted 1.1 m of lip and
## found no legal spot on the very openings this exists for. Travelling and
## arriving are not the same question.
##
## Jumping at the bleed is allowed; landing the hands there is not. A body that
## catches a duct's corner hangs with half a hand inside the wall, unable to
## shimmy and unable to pull up.
##
## CORRECTED IN THE AIR, WHICH COSTS NOTHING NEW. IntoGrab already slides the
## body to hanging_pose() over align_speed, so moving the TARGET is the whole
## implementation -- no motion code, no snap.
##
## THE SEARCH REACHES EXACTLY ONE RADIUS, which is all it ever needs: the
## furthest a legal grab can sit from the safe zone is the width of the bleed,
## and that is the same radius. Correcting further would
## drag a player who deliberately aimed at a corner into the middle, and
## docs/feel-backlog.md 22 records what over-helping feels like here: the owner
## called an earlier alignment "被磁铁吸过去".
##
## Asks ledge_beside() a radius out on each side -- is there still lip under
## the hands -- and then whether a pull-up would be admitted, because hanging somewhere that refuses
## the climb is the complaint this exists to fix. It does NOT ask the shimmy's
## second, face-still-there probe: that one guards outside corners, and the
## openings this is for are inside ones. Add it if an outside corner starts
## reading as safe.
##
## Finding nothing leaves the query alone. An awkward hang beats a refused one.
func _slid_into_the_safe_zone(query: Dictionary) -> Dictionary:
	if player.probes == null:
		return query
	var face_normal: Vector3 = query.get("face_normal", Vector3.ZERO)
	face_normal.y = 0.0
	if face_normal.length_squared() < 0.0001:
		return query
	face_normal = face_normal.normalized()
	# ALONG the ledge is ACROSS the wall, the same quarter turn the shimmy takes.
	var sideways: Vector3 = (-face_normal).cross(Vector3.UP)
	var edge: Vector3 = query["edge"]
	var reach: float = player.current_capsule_radius()
	if reach <= 0.0:
		# A player built without a collision shape -- tests do this. There is
		# nothing to measure a safe zone against, so there is nothing to fix.
		return query
	for offset in search_offsets(reach, SAFE_ZONE_SAMPLES):
		var candidate: Vector3 = edge + sideways * offset
		if not _hangable(candidate, sideways, face_normal, reach):
			continue
		var moved: Dictionary = query.duplicate()
		moved["edge"] = candidate
		moved["top"] = candidate
		return moved
	return query

func _hangable(edge: Vector3, sideways: Vector3, face_normal: Vector3, reach: float) -> bool:
	for side in [1.0, -1.0]:
		var beside: Dictionary = player.probes.ledge_beside(edge, sideways * (side * reach),
			face_normal, Probes.LEDGE_ANCHOR_MARGIN,
			config.grab.shimmy_probe_lift, config.grab.shimmy_edge_tolerance)
		if not beside.get("valid", false):
			return false
	return player.fits_at(edge, config.crouch.crouch_capsule_height)

## Where the body ends up, given the ledge it caught.
##
## Static, and taking everything it needs as arguments, so the debug markers
## can draw the very same pose this aims for rather than a copy of the maths --
## a marker that drifts from the behaviour it illustrates is worse than none.
##
## BACK ALONG THE WALL'S NORMAL, not along the approach. Backing off along the
## approach leaves the hang skewed by whatever angle the ledge was caught at,
## which is the same mistake the facing made (see enter()).
static func hanging_pose(body: Node3D, cfg_all: MovementConfig, hit: Dictionary) -> Vector3:
	var edge: Vector3 = hit["edge"]
	var back: Vector3 = hit.get("face_normal", Vector3.ZERO)
	back.y = 0.0
	if back.length_squared() < 0.0001:
		# No wall normal to work from: fall back to the approach.
		back = edge - body.global_position
		back.y = 0.0
		back = -back
	if back.length_squared() < 0.0001:
		back = body.global_transform.basis.z
	# Placed by where the EYE ends up, not the body centre -- see
	# IntoGrabConfig.eye_below_ledge. The centre goes wherever puts the eye
	# there.
	var centre_below: float = cfg_all.into_grab.eye_below_ledge + cfg_all.camera.eye_height
	var stand_off: Vector3 = back.normalized() * cfg_all.into_grab.ledge_back_offset
	return edge + stand_off - Vector3.UP * centre_below

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return FALLING

	# [ME:CONFIRMED 11 §11.2] IntoGrab is one of the six states holding
	# bCheckExitToUncontrolledFalling, alongside Falling and Coil -- the other
	# two this project has, both of which check. A reach cannot save a body
	# that has already dropped too far.
	#
	# DO NOT read this as a tickbox copied for completeness. The approach phase
	# below carries the body under its own gravity while it waits for a hand to
	# arrive, and touching() measures HORIZONTAL distance only -- so a body
	# dropping fast down the face of a wall stays "still approaching" all the
	# way down without ever arriving. Measured on a 40 m block: committed at
	# y = 18.75 and still here at y = 1.15, an unsurvivable drop arriving
	# survivable in a grab pose, because this state tested nothing.
	#
	# STRAIGHT TO UNCONTROLLED, with no soft-landing branch of its own:
	# [ME:CONFIRMED 11 §11.2] ForSoftLanding is held by 180TurnInAir, Falling,
	# FallingUncontrolled and SoftLanding, and IntoGrab is in none of them.
	if player.fall_tracker.fall_height >= config.pawn.falling_uncontrolled_height:
		return advance_and_hand_off(FALL_UNCONTROLLED)

	_reach_time += delta

	# THE APPROACH. Nothing has been touched, so nothing moves the body but the
	# body. See docs/contact-drives-movement.md.
	if not _touched:
		if _reach_time >= cfg.max_duration:
			# Jumped short, or something got in the way. Falling is the honest
			# outcome; hanging in the air waiting to touch is not.
			return FALLING
		if not touching(_face_point):
			carry_ballistically(delta)
			# A jump too weak to reach the wall can trigger an infinite IntoGrab
			# -> Falling loop if the check below is dropped.
			#
			# THE REACH NEVER ASKS WHETHER THE BODY IS STILL IN THE AIR.
			# carry_ballistically() runs move_and_slide() and sets grounded every
			# tick, so DO NOT drop the check below: without it, a jump
			# too weak to get the hands to the lip drops the body back onto the
			# floor, where it then spends the rest of max_duration (1.5 s) with
			# its input frozen, pretending to reach for something above it.
			#
			# ledge_query()'s height gate is measured from the FEET, so a ledge
			# inside [min_wall_height, ledge_max_height] of the floor stays
			# "valid and within reach" from a standing start forever. That is
			# what closes the loop -- AirborneMove asks the grab question before
			# its own landing question, so the tick this hands back to Falling,
			# Falling sends it straight here again.
			#
			# FALLING, not WALKING: whether that landing costs the 2 s Landing
			# lockout is AirborneMove.landing_destination()'s to judge, and
			# short-circuiting to Walking here would turn a reach at any passing
			# ledge into a way to cancel a hard landing. Breaking the loop is
			# IntoGrabConfig.redo_move_time's job, not this line's.
			if player.grounded and player.velocity.y <= 0.0:
				return FALLING
			return KEEP
		# CONTACT. The reach starts HERE, from wherever the body has actually
		# got to -- not from where it was when the ledge was first seen.
		_touched = true
		_reach_time = 0.0

	player.set_grounded(false)
	player.velocity = Vector3.ZERO

	var to_target: Vector3 = _target - player.global_position

	# The facing finishes WITH the reach, not before it.
	#
	# DO NOT use a fixed turn rate here. At any rate fast enough to square up
	# on a short reach, it squares up on a long one in two or three ticks
	# while the translation is still ten ticks from done -- a whip followed by
	# a glide, not one alignment -- and it saturates the camera's trailing lag
	# on the way, so the eye spends the rest of the reach being handed that
	# saturated lag back: the view swings off one way and then returns.
	#
	# Spreading the turn over the translation's own remaining time makes the
	# whole manoeuvre a single continuous motion, which is what the camera's
	# smoothing was written to soften and what IntoGrabAlignSpeed governing
	# the alignment implies in the first place.
	var remaining_time: float = maxf(to_target.length() / cfg.align_speed, delta)
	var remaining_turn: float = absf(wrapf(_target_yaw - player.rotation.y, -PI, PI))
	# Floored, so a reach with no distance left to spread the turn over still
	# turns at a sane rate rather than stalling.
	var turn_floor: float = cfg.min_align_turn_speed * delta
	var turn_step: float = maxf(remaining_turn * delta / remaining_time, turn_floor)
	_turn_body_toward(_target_yaw, turn_step)
	# THE MODEL COMES ROUND WITH THE CAPSULE. Turning only the capsule leaves
	# the body hanging at whatever angle the reach began at, because in third
	# person the model follows the view only while a direction key is held --
	# and a grab is the case where nobody is holding one. The capsule is
	# already being eased round, so borrowing its heading gives the model the
	# same easing for free. See docs/capsule-leads-presentation.md.
	player.pin_visual_yaw(player.rotation.y)
	to_target = _target - player.global_position
	# BOTH have to have arrived. DO NOT finish on position alone: correcting
	# the facing afterward in one lump via _settle() hands the camera a lag
	# the size of the whole remaining turn, and a lag that big does not read
	# as softening -- it reads as the view lunging off into the wall before
	# snapping back.
	var facing_error: float = absf(wrapf(_target_yaw - player.rotation.y, -PI, PI))
	if to_target.length() <= cfg.arrive_distance and facing_error < 0.03:
		player.global_position = _target
		return _settle()
	if _reach_time >= cfg.max_duration:
		# Something is in the way and the reach is never going to land. Falling
		# is the honest outcome -- better than hanging in the air mid-reach.
		return FALLING

	var stepped: float = cfg.align_speed * delta
	if stepped >= to_target.length():
		player.global_position = _target
		# Position is there; the turn may not be. Hold until it is, so the
		# facing is never corrected in one lump.
		if facing_error < 0.03:
			return _settle()
		return KEEP
	player.global_position += to_target.normalized() * stepped
	return KEEP

## Finishes the reach: square the body up to the wall exactly, and tell the
## camera its fan is centred there rather than on whatever the jump was aimed
## at. Without the re-centring the hang's own look clamp inherits the approach
## angle, and every grab has a differently skewed fan.
func _settle() -> StringName:
	# REFUSED HERE, not in MoveManager.can_enter(). The two lines below snap
	# the body square to the wall and re-centre the camera's fan before GRAB
	# is ever announced, so a refusal at the transition would leave a body
	# planted against a wall it is not holding, waiting out cfg.max_duration
	# before it finally falls. Same class as JUMP, SLIDE and SKILL_ROLL.
	# Falling is the honest outcome, exactly as it is when the reach runs out.
	if player.statuses.is_move_blocked(GRAB):
		return FALLING
	# Set directly, NOT through _turn_body_toward(): by here the facing is
	# already within a rounding error of the target, and reporting that sliver
	# to the camera as a lag is noise.
	player.rotation.y = _target_yaw
	# Square the model to the wall on the same tick, so the hands and the hips
	# agree about which way the ledge runs.
	player.pin_visual_yaw(_target_yaw)
	if player.camera_rig != null:
		player.camera_rig.recentre_yaw_reference(_target_yaw)
	return GRAB

## Turns the body toward `to`, at most `step` this tick, and tells the camera
## how far it moved so the eye can trail rather than being cut through it.
func _turn_body_toward(to: float, step: float) -> void:
	var before: float = player.rotation.y
	player.rotation.y = _turn_toward(before, to, step)
	if player.camera_rig != null:
		player.camera_rig.absorb_body_yaw(player.rotation.y - before)

## Rotates `from` toward `to` by at most `step`, the short way round.
static func _turn_toward(from: float, to: float, step: float) -> float:
	var difference: float = wrapf(to - from, -PI, PI)
	if absf(difference) <= step:
		return to
	return from + signf(difference) * step

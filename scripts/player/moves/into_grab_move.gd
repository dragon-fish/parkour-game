class_name IntoGrabMove
extends Move

# The original's TdMove_IntoGrab: the reach between catching a ledge and
# hanging from it.
#
# The body is carried to a FIXED pose relative to the edge -- 0.30 m back,
# 0.928 m down (GrabDesiredLedgeOffset) -- at a FIXED rate (IntoGrabAlignSpeed,
# 3 m/s). Everything the owner reported about the manoeuvre falls out of those
# two numbers: every hang ends up looking identical however it was caught, and
# a reach that has further to travel takes proportionally longer. The duration
# is a consequence of the geometry, not a setting.
#
# Before this existed the body simply froze wherever it made contact, which is
# what left the player hanging in mid-air a long way out from the wall.
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

func enter(_previous: StringName) -> void:
	# Declared, not read: this move drives the body directly and never calls
	# move_and_slide(), so is_on_floor() would report whatever the previous
	# move left behind. Same reasoning as SpeedVaultMove and GrabMove.
	player.set_grounded(false)
	_aborted = false
	_reach_time = 0.0
	player.velocity = Vector3.ZERO

	var query: Dictionary = player.probes.ledge_query() if player.probes != null else Probes.NO_HIT.duplicate()
	if not query["valid"]:
		# Nothing to reach for. There is no safe position to invent here, so
		# invent none -- physics_update() hands straight back to Falling.
		_aborted = true
		return
	# TOO FAR TO REACH. Letting the body close a large gap here is what made
	# grabbing read as a magnet -- jump vaguely wallward and get hauled in
	# across open air. The original touches the wall first.
	# Measured to the WALL, matching AirborneMove._within_reach() -- `edge` sits
	# on the ledge's top and can be well behind the face the body would touch.
	if float(query.get("face_distance", INF)) > cfg.max_reach_distance:
		_aborted = true
		return
	var gap: Vector3 = query["edge"] - player.global_position
	gap.y = 0.0
	_target = hanging_pose(player, config, query)
	# Square to the WALL's face, not toward the edge point.
	#
	# Facing the edge was the first attempt and is wrong whenever the ledge was
	# approached at an angle: the edge is a point on the ledge's TOP, off to
	# one side of the wall it belongs to, so aiming at it leaves the body
	# skewed by exactly the angle it arrived at. Measured in play with the HUD
	# reporting the view as square (yaw -1) while the wall was visibly some
	# 30 degrees off.
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
	return edge + back.normalized() * cfg_all.into_grab.ledge_back_offset 		- Vector3.UP * centre_below

func physics_update(delta: float, _input: MoveInput) -> StringName:
	if _aborted:
		return FALLING
	_reach_time += delta
	player.set_grounded(false)
	player.velocity = Vector3.ZERO

	# Turned toward the wall alongside the move, at its own rate.
	_turn_body_toward(_target_yaw, cfg.align_turn_speed * delta)

	var to_target: Vector3 = _target - player.global_position
	# BOTH have to have arrived. Finishing on position alone left the facing
	# to be corrected in one lump by _settle(), which handed the camera a lag
	# the size of the whole remaining turn -- and a lag that big does not read
	# as softening, it reads as the view lunging off into the wall before
	# snapping back.
	var facing_error: float = absf(wrapf(_target_yaw - player.rotation.y, -PI, PI))
	if to_target.length() <= cfg.min_adjust_distance and facing_error < 0.03:
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
	# Set directly, NOT through _turn_body_toward(): by here the facing is
	# already within a rounding error of the target, and reporting that sliver
	# to the camera as a lag is noise.
	player.rotation.y = _target_yaw
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

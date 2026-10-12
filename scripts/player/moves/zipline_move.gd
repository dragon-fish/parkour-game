class_name ZiplineMove
extends PhysicsMove

# The original's TdMove_ZipLine, ported. [ME:CONFIRMED decompile N5 §17;
# PrePhysics emulated; script TdMove_ZipLine]
#
# Every frame, before the physics, the native rebuilds Velocity from the
# cable: from the hand point (90 uu above the centre) it finds the first
# spline point at least max(|Velocity|, MinZipVelocity) * dt away and aims the
# hands at the point of that chord exactly that far off -- so the body follows
# the polyline and cannot leave it sideways. The acceleration is along the
# velocity at max(MinZipAcceleration, |GravityZ * slope|), and the flying
# physics integrates both: the speed grows with the grade, decays by 0.15/s and
# is capped at AirSpeed. Running off the last point is a fall; a wall within
# 600 uu ahead, then within 20, is the impact.
#
# The cable is this project's ZIPLINE InterestLine, its points the original's
# SplineLocations (MovementSpline). The ride runs in the curve's own point
# order, as the original's runs in its spline's.

## The original's 1P sequence lengths. [ME:CONFIRMED anims]
const ZIPLINE_HIT_WALL_LENGTH := 1.167

enum Status { MOVING, CLOSE_TO_END, IMPACT }

## Look-ahead of the impact probe while moving, close to the end, and at the
## impact: 600, 20 and 2 uu. The probe starts 40 uu below the hands.
const IMPACT_PROBE_MOVING := 600.0 * UU
const IMPACT_PROBE_CLOSE := 20.0 * UU
const IMPACT_PROBE_IMPACT := 2.0 * UU
const IMPACT_PROBE_DROP := 40.0 * UU
## ZipLine's look assist aims this far down the velocity from the probe start.
const LOOK_AHEAD := 600.0 * UU

## TdMove_ZipLine.ZipLine: the cable, handed over by IntoZipLine.
var zip_line: InterestLine = null
var current_param_on_curve: float = 0.0
var zip_line_status: int = Status.MOVING
var current_look_at_point: Vector3 = Vector3.ZERO
var zip_line_look_assist: bool = false

var _spline: MovementSpline = MovementSpline.new()
var _anim := MoveAnim.new()

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_GRABBING
	disable_movement_time = -1.0
	# [ME:CONFIRMED decompile] bDisableFaceRotation.
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## TdMove_ZipLine.HandleDeath: Falling, and the death.
func handle_death(damage: float) -> float:
	player.move_manager.set_move(FALLING)
	return damage

func can_do_move() -> bool:
	return td_can_do_move()

# --- the spline (TdMovementVolume) ----------------------------------------------

## GetSlopeOnSpline at a parameter in segments, as the zipline moves ask it:
## divided by SplineLocations.Length - 1.
static func slope_at(spline: MovementSpline, param: float) -> Vector3:
	return spline.slope_at(param / float(maxi(spline.locations.size() - 1, 1)))

## TdMovementVolume.MoveDirection for a cable. [ME:INFERRED N7 §2] a zipline
## volume's MoveDirection is its own X axis, which an InterestLine does not
## carry; the cable's first point to its last stands in.
static func move_direction(line: InterestLine) -> Vector3:
	var spline := MovementSpline.of(line)
	if spline.locations.size() < 2:
		return Vector3.FORWARD
	return PawnPhysics.safe_normal(spline.end - spline.start)

# --- StartMove / StopMove --------------------------------------------------------

func enter(_previous: StringName) -> void:
	player.set_grounded(false)
	zip_line_status = Status.MOVING
	_spline = MovementSpline.of(zip_line)
	var start: Vector3 = player.global_position + Vector3.UP * cfg.hang_offset
	current_param_on_curve = _spline.find_closest(start)[1]
	zip_line_look_assist = true
	# The fan centres on the heading the reach turned the pawn to.
	if player.camera_rig != null:
		player.camera_rig.recentre_yaw_reference(player.pawn_yaw)

func exit() -> void:
	_anim.stop()
	zip_line = null
	zip_line_status = Status.MOVING
	# [ME:CONFIRMED decompile] StopMove: PHYS_Falling, and the fall counted from
	# 80 uu below where the hands let go.
	player.set_physics(PHYS_FALLING)
	player.enter_falling_height -= 80.0 * UU
	zip_line_look_assist = false

# --- the frame -------------------------------------------------------------------

## Native PrePhysics. The base TdPhysicsMove PrePhysics is NOT run for the
## player.
func pre_physics(delta: float) -> void:
	if zip_line == null or not is_instance_valid(zip_line) or _spline.locations.size() < 2:
		return
	var points: PackedVector3Array = _spline.locations
	var nz: float = PawnPhysics.safe_normal(player.velocity).y
	player.velocity.y += absf(nz) * player.gravity_z() * delta
	var hand: Vector3 = player.global_position + Vector3.UP * cfg.hang_offset
	current_param_on_curve = _spline.find_closest(hand, int(current_param_on_curve))[1]
	var index: int = int(current_param_on_curve)
	var step: float = maxf(player.velocity.length(), cfg.min_zip_velocity) * delta
	while true:
		index += 1
		if index >= points.size():
			player.move_manager.set_move(FALLING)
			return
		if (points[index] - hand).length() >= step:
			break
	var a: Vector3 = points[index - 1]
	var b: Vector3 = points[index]
	var seg: Vector3 = b - a
	var to_b: Vector3 = b - hand
	var perp: Vector3 = to_b - seg * (to_b.dot(seg) / seg.length_squared())
	var h: float = sqrt(maxf(0.0, step * step - perp.length_squared()))
	player.velocity = (perp + PawnPhysics.safe_normal(seg) * h) / delta
	if player.velocity.length() < cfg.min_zip_velocity:
		player.velocity = PawnPhysics.safe_normal(player.velocity) * cfg.min_zip_velocity
	var along: Vector3 = PawnPhysics.safe_normal(player.velocity)
	player.acceleration = along * maxf(cfg.min_zip_acceleration, absf(player.gravity_z() * along.y))
	var probe: Vector3 = hand - Vector3.UP * IMPACT_PROBE_DROP
	var extent := Vector3(player.collision_radius(), player.collision_half_height() * 0.5,
		player.collision_radius())
	var reach: float = IMPACT_PROBE_MOVING
	if zip_line_status == Status.CLOSE_TO_END:
		reach = IMPACT_PROBE_CLOSE
	elif zip_line_status == Status.IMPACT:
		reach = IMPACT_PROBE_IMPACT
	if player.phys.trace_blocked(probe + along * reach, probe, extent):
		match zip_line_status:
			Status.MOVING:
				prepare_for_forward_impact()
			Status.CLOSE_TO_END:
				play_forward_impact()
			Status.IMPACT:
				player.velocity = Vector3.ZERO
				player.acceleration = Vector3.ZERO
	current_look_at_point = probe + along * LOOK_AHEAD

func prepare_for_forward_impact() -> void:
	if zip_line_status == Status.MOVING:
		_anim.play(&"ziplineintohitwall", 2.0)
		zip_line_status = Status.CLOSE_TO_END

## The hands hit: input off for 0.8 s, and Falling when it runs out.
func play_forward_impact() -> void:
	_anim.play(&"ziplinehitwall", ZIPLINE_HIT_WALL_LENGTH)
	zip_line_status = Status.IMPACT
	player.set_ignore_look_input(0.8)
	player.set_ignore_move_input(0.8)
	set_timer(0.8)

func on_timer() -> void:
	player.move_manager.set_move(FALLING)

## HitWall: a floor-ish face is a stumble, struck from 10 uu back along the
## ride; otherwise, at speed, the ride stops dead against it. Only the
## instigator's location is written: the damage type and location are left as
## the last hit had them, as the original leaves them (damageMomentum, the
## velocity's direction, is read by nothing but a debug draw).
func hit_wall(normal: Vector3, _collider: Object) -> void:
	if normal.y > 0.1 and player.move_manager.can_do(STUMBLE):
		var stumble: StumbleMove = player.move_manager.move_for(STUMBLE)
		stumble.instigator_location = player.global_position \
			- 10.0 * UU * PawnPhysics.safe_normal(player.velocity)
		player.move_manager.set_move(STUMBLE)
	elif Vector2(player.velocity.x, player.velocity.z).length() > 100.0 * UU:
		player.velocity = Vector3.ZERO
		player.acceleration = Vector3.ZERO

func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_anim.advance(delta)

## UpdateViewRotation: the base, then the look assist -- the view drawn down
## the cable 600 uu ahead until the first yaw input, which ends it for the
## ride.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	var result: Array = super.update_view_rotation(view, dt, delta_rot, now)
	var through: Vector2i = result[1]
	if through.y != 0:
		abort_look_at_target()
		zip_line_look_assist = false
	elif zip_line_look_assist:
		set_look_at_target_location(current_look_at_point, 0.2, -1.0)
	return result

# --- read by the HUD -------------------------------------------------------------

func line() -> InterestLine:
	return zip_line

func ride_speed() -> float:
	return player.velocity.length()

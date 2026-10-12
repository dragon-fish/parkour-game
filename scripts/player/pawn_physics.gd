class_name PawnPhysics
extends RefCounted

# The original's native pawn physics, ported from the decompile: how
# Pawn.Acceleration becomes Velocity and Velocity becomes Location, in the
# walking and the falling modes, and how the two hand over to each other.
#
#   ATdPawn::performPhysics -> startNewPhysics -> physWalking / physFalling
#   [ME:CONFIRMED decompile N1, N2; CalcVelocity, the walk-friction opening,
#    the falling acceleration bound, the sub-step schedule, the velocity
#    rebuild and the slide vector are ME:CONFIRMED emulated]
#
# MoveActor is CharacterBody3D.move_and_collide(); a UE3 line or extent trace
# is test_move() or a shape cast. Everything is metric: 1 uu = 0.01 m. Formulas
# and their order are the original's, including the parts that look
# accidental -- the falling integrator that doubles every acceleration, the
# walking velocity rebuilt from displacement, the unit-length acceleration
# left by a landing. DO NOT tidy them: the feel is made of them.
#
# Only the moves ported from the original (Move.is_ported()) are moved through
# here. The others still drive the body with move_and_slide() themselves.

const UU := 0.01

## 0.05 s: the longest physics sub-step; a longer remainder is halved down to
## it. [ME:CONFIRMED emulated] Both physWalking and physFalling.
const MAX_SUB_STEP := 0.05
## Iterations shared by one frame's physics, across the hand-offs between
## modes. [ME:CONFIRMED emulated]
const MAX_ITERATIONS := 8
## startNewPhysics ignores a remainder shorter than this.
const MIN_REMAINING := 0.0003
## MAXSTEPHEIGHTFUDGE: every step and floor test reaches MaxStepHeight + 2 uu.
const STEP_FUDGE := 2.0 * UU
## The walking body hovers between these above its floor, aiming for the
## middle one. [ME:CONFIRMED decompile N1 §2.3]
const MIN_FLOOR_DIST := 1.9 * UU
const FLOOR_DIST := 2.15 * UU
const MAX_FLOOR_DIST := 2.4 * UU
## Above this Floor.Z a forward move is tried before the step-up.
const FLOOR_Z_DIRECT_MOVE := 0.98
## MAXSTEPSIDEZ: below this a blocking normal is a wall to the step-up.
const MAX_STEP_SIDE_Z := 0.08
## MINSTEPSIZESQUARED, 144 uu^2.
const MIN_STEP_SIZE_SQUARED := 144.0 * UU * UU
## The corner slip's sideways reach and its look-ahead.
const CORNER_SLIP_REACH := 32.0 * UU
const CORNER_SLIP_PROBE := 34.0 * UU
## The original's IsNearlyZero(1e-4) on a uu vector.
const NEARLY_ZERO := 1e-4 * UU
## CalcVelocity's braking slices, and the speed under which braking stops the
## body outright (|V|^2 < 100 uu^2/s^2).
const BRAKING_SLICE := 0.03
const BRAKING_STOP_SPEED_SQUARED := 100.0 * UU * UU
## The falling acceleration bound below this horizontal speed grows so a body
## at rest can start drifting. 10 uu/s.
const AIR_LOW_SPEED := 10.0 * UU
## The falling bound once the horizontal speed reaches GroundSpeed: 1 uu/s^2.
const AIR_FAST_BOUND := 1.0 * UU
## A falling landing rebuilds the velocity from the displacement only when the
## step got this far: Hit.Time > 0.1 and Hit.Time * tick > 0.003.
const LANDING_REBUILD_TIME := 0.1
const LANDING_REBUILD_SECONDS := 0.003
## ComputeSlideVector shoves 1 % off a wall whose normal z is under this.
const SLIDE_PUSH_NORMAL_Z := 0.087
const SLIDE_PUSH_FRACTION := 0.01

## The Player. Untyped for the same reason Move.player is.
var pawn

## Set inside a frame when a move teleported the body (the corner slip) or the
## physics must not rebuild the velocity from displacement.
var _just_teleported: bool = false

func _init(owner_pawn) -> void:
	pawn = owner_pawn

# --- pure functions, pinned against the original -------------------------------

## FVector::SafeNormal.
static func safe_normal(v: Vector3) -> Vector3:
	var sq: float = v.length_squared()
	if sq == 1.0:
		return v
	if sq < 1e-8 * UU * UU:
		return Vector3.ZERO
	return v / sqrt(sq)

## FVector::SafeNormal2D, on Godot's horizontal plane.
static func safe_normal_2d(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return safe_normal(flat)

static func is_nearly_zero(v: Vector3, tolerance: float = NEARLY_ZERO) -> bool:
	return absf(v.x) < tolerance and absf(v.y) < tolerance and absf(v.z) < tolerance

## The slope-dependent multiplier physWalking puts on GroundFriction, from the
## velocity and floor of the PREVIOUS tick. [ME:CONFIRMED emulated N1 §2.1]
##
## uphill = -(Floor2D . Vel2D); slope = sin(floor angle) * uphill.
## A slide (`sliding`) takes the slide scales and is NOT clamped -- downhill
## it can go negative, which turns braking into acceleration. Everything else
## takes the walk scales, clamped to [MinWalkFrictionModify,
## MaxWalkFrictionModify]. uphill exactly 0 counts as upward.
static func walk_friction_modifier(velocity: Vector3, floor_normal: Vector3, sliding: bool,
		friction_modifier: float, p: PawnConfig) -> float:
	var v2: Vector3 = safe_normal_2d(velocity)
	var n2: Vector3 = safe_normal_2d(floor_normal)
	var uphill: float = -(n2.x * v2.x + n2.z * v2.z)
	var fz2: float = clampf(floor_normal.y * floor_normal.y, 0.0, 1.0)
	var slope: float = sqrt(1.0 - fz2) * uphill
	if sliding:
		var slide_scale: float = p.downward_slide_friction_scale if uphill < 0.0 \
			else p.upward_slide_friction_scale
		return (slide_scale * slope + 1.0) * friction_modifier
	var walk_scale: float = p.downward_walk_friction_scale if uphill < 0.0 \
		else p.upward_walk_friction_scale
	var m: float = (walk_scale * slope + 1.0) * friction_modifier
	m = maxf(m, p.min_walk_friction_modify)
	m = minf(m, p.max_walk_friction_modify)
	return m

## ATdPawn::CalcVelocity on its non-root-motion path. [ME:CONFIRMED emulated
## N1 §3] Returns [Velocity, Acceleration].
##
## `mobility` is GetMobilityMultiplier() * the move's SpeedModifier.
## `force_max_accel` is bForceMaxAccel || bForceMaxAccelOneFrame; the caller
## clears the one-frame flag. `facing` is Rotation.Vector(), the fallback
## direction when there is neither input nor speed.
##
## There is NO directional (turning) friction here: ATdPawn drops the term
## UE3's APawn::CalcVelocity has. All turning comes from the acceleration
## functions.
static func calc_velocity(velocity: Vector3, acceleration: Vector3, accel_dir: Vector3,
		dt: float, max_speed: float, friction: float, brake: bool, mobility: float,
		accel_rate: float, braking_friction_strength: float, wall_physics: bool,
		precise_location: bool, force_max_accel: bool, facing: Vector3) -> Array:
	var v: Vector3 = velocity
	var a: Vector3 = acceleration
	var max_accel: float = accel_rate * mobility
	var max_spd: float = mobility * max_speed
	if force_max_accel:
		if not is_nearly_zero(a):
			a = accel_dir * max_accel
		else:
			var source: Vector3 = v if not is_nearly_zero(v) else facing
			a = safe_normal(source) * max_accel
	if not precise_location:
		if not brake or a != Vector3.ZERO:
			if a.length_squared() > max_accel * max_accel:
				a = safe_normal(a) * max_accel
			if wall_physics:
				v.x -= v.x * dt * friction
				v.z -= v.z * dt * friction
			else:
				v -= v * dt * friction * 0.1
		else:
			var old: Vector3 = v
			var total := Vector3.ZERO
			var rem: float = dt
			if dt > 0.0:
				while true:
					var slice: float = BRAKING_SLICE if BRAKING_SLICE < rem else rem
					rem -= slice
					v -= v * 2.0 * slice * friction * braking_friction_strength
					if v.dot(old) > 0.0:
						total += v * slice * (1.0 / dt)
					if not rem > 0.0:
						break
			v = total
			if v.dot(old) < 0.0 or v.length_squared() < BRAKING_STOP_SPEED_SQUARED:
				v = Vector3.ZERO
	v = v + a * dt
	if v.length_squared() > max_spd * max_spd:
		v = safe_normal(v) * max_spd
	return [v, a]

## The acceleration bound at the top of ATdPlayerPawn::physFalling, with
## Acceleration.Z already zeroed. [ME:CONFIRMED emulated N2 §2] Returns the
## bounded acceleration.
##
## AccelRate * AirControl (153.6 uu/s^2); under 10 uu/s of horizontal speed it
## grows by (10 - speed) / dt; at GroundSpeed and above it is 1 uu/s^2. The
## integrator doubles whatever comes out of here.
static func falling_accel_bound(velocity: Vector3, acceleration: Vector3, dt: float,
		accel_rate: float, air_control: float, ground_speed: float) -> Vector3:
	var a := Vector3(acceleration.x, 0.0, acceleration.z)
	var max_accel: float = accel_rate * air_control
	var speed2d: float = Vector2(velocity.x, velocity.z).length()
	if speed2d < AIR_LOW_SPEED and air_control > 0.0:
		max_accel += (AIR_LOW_SPEED - speed2d) / dt
	elif speed2d >= ground_speed:
		if air_control <= 0.05:
			max_accel = AIR_FAST_BOUND
	if a.length_squared() > max_accel * max_accel:
		a = safe_normal(a) * max_accel
	return a

## APawn::ComputeSlideVector (through TdPawn's override, whose only addition is
## the uncontrolled-slide material test). [ME:CONFIRMED emulated N2 §2b]
static func compute_slide_vector(delta: Vector3, normal: Vector3, time: float) -> Vector3:
	var proj: Vector3 = normal * delta.dot(normal)
	var push: float = delta.length() * SLIDE_PUSH_FRACTION if absf(normal.y) < SLIDE_PUSH_NORMAL_Z else 0.0
	var out: Vector3 = (delta - proj) * (1.0 - time) - safe_normal(proj) * push
	if out.y > 0.0:
		out.y = minf(out.y, (1.0 - time) * delta.y)
	return out

## AActor::TwoWallAdjust, stock UE3. [ME:CONFIRMED decompile N1 §4.4] The cross
## product's sign flips between UE's left-handed axes and Godot's, but `d`
## appears twice, so the result does not.
static func two_wall_adjust(desired_dir: Vector3, delta: Vector3, hit_normal: Vector3,
		old_hit_normal: Vector3, hit_time: float) -> Vector3:
	var out: Vector3 = delta
	if old_hit_normal.dot(hit_normal) > 0.0:
		out = (out - hit_normal * out.dot(hit_normal)) * (1.0 - hit_time)
		if out.dot(desired_dir) <= 0.0:
			out = Vector3.ZERO
	else:
		var d: Vector3 = safe_normal(hit_normal.cross(old_hit_normal))
		out = d * out.dot(d) * (1.0 - hit_time)
		if desired_dir.dot(out) < 0.0:
			out = -out
	return out

## ATdPawn::UpdateWalkingState's thresholds, strict <. [ME:CONFIRMED emulated
## N1 §5.2] No weapon: Idle 0, Sneak 1, Walk 2, Jog 3, Run 4, Sprint 5.
const WAS_IDLE := 0
const WAS_SNEAK := 1
const WAS_WALK := 2
const WAS_JOG := 3
const WAS_RUN := 4
const WAS_SPRINT := 5
static func walking_state(speed2d: float) -> int:
	if speed2d < 5.0 * UU:
		return WAS_IDLE
	if speed2d < 50.0 * UU:
		return WAS_SNEAK
	if speed2d < 260.0 * UU:
		return WAS_WALK
	if speed2d < 400.0 * UU:
		return WAS_JOG
	if speed2d < 630.0 * UU:
		return WAS_RUN
	return WAS_SPRINT

# --- traces ---------------------------------------------------------------------

## UWorld::MoveActor: sweeps the body's own collider along `delta` and stops at
## the first blocking hit. Returns {time, normal, collider, position}: time is
## the fraction of `delta` travelled, 1 when nothing blocked.
func move_actor(delta: Vector3) -> Dictionary:
	if delta == Vector3.ZERO:
		return _miss()
	if not pawn.collide_world:
		pawn.global_position += delta
		return _miss()
	var before: Vector3 = pawn.global_position
	var collision: KinematicCollision3D = pawn.move_and_collide(delta)
	var length: float = delta.length()
	var time: float = 1.0
	if collision != null and length > 0.0:
		# Along the asked motion only: the travel also carries whatever the
		# recovery below pushed.
		time = clampf(collision.get_travel().dot(delta) / (length * length), 0.0, 1.0)
	_note_recovery(pawn.global_position - before, delta * time)
	if collision == null:
		return _miss()
	return {"time": time, "normal": collision.get_normal(),
		"collider": collision.get_collider(), "position": collision.get_position()}

## Godot's move_and_collide() first pushes a body out of anything it overlaps;
## UE3's MoveActor never moves a body it did not ask to. A push like that is
## not the body's own motion, and the velocity rebuilt from displacement (both
## physics modes do it) must not read it as such -- a body spawned inside a
## floor would otherwise leave it at tens of metres a second. Treated like the
## original's bJustTeleported: the step that saw it keeps its velocity.
const RECOVERY_TOLERANCE := 0.5 * UU
var _recovered: bool = false

func _note_recovery(moved: Vector3, asked: Vector3) -> void:
	if (moved - asked).length() > RECOVERY_TOLERANCE:
		_recovered = true

## SingleLineCheck with the pawn's own cylinder as the extent: where the body
## would stop if moved by `motion`, without moving it.
func sweep(motion: Vector3, from: Transform3D = Transform3D()) -> Dictionary:
	var start: Transform3D = pawn.global_transform if from == Transform3D() else from
	var collision := KinematicCollision3D.new()
	if motion == Vector3.ZERO or not pawn.test_move(start, motion, collision):
		return _miss()
	var length: float = motion.length()
	return {"time": clampf(collision.get_travel().length() / length, 0.0, 1.0),
		"normal": collision.get_normal(), "collider": collision.get_collider(),
		"position": collision.get_position()}

## A zero-extent trace against world geometry, never the pawn itself. Empty
## when nothing is hit.
func line_trace(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = pawn.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [pawn.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var length: float = (to - from).length()
	hit["time"] = (hit["position"] - from).length() / length if length > 0.0 else 0.0
	return hit

## An extent trace from `start` to `end` with a box of half-size `extent`, the
## shape TdMove's traces sweep. {time, position, normal, collider}; time 1 and
## no collider when nothing is hit; time 0 when the box starts inside
## something. `position` is the box centre where it stops.
func box_trace(end: Vector3, start: Vector3, extent: Vector3) -> Dictionary:
	if extent == Vector3.ZERO:
		var line: Dictionary = line_trace(start, end)
		if line.is_empty():
			return {"time": 1.0, "position": end, "normal": Vector3.ZERO, "collider": null}
		return line
	var space: PhysicsDirectSpaceState3D = pawn.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = extent * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.motion = end - start
	query.exclude = [pawn.get_rid()]
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.is_empty():
		return {"time": 0.0, "position": start, "normal": Vector3.ZERO, "collider": null}
	var safe: float = fractions[0]
	var unsafe: float = fractions[1]
	if safe >= 1.0 and unsafe >= 1.0:
		return {"time": 1.0, "position": end, "normal": Vector3.ZERO, "collider": null}
	query.transform = Transform3D(Basis.IDENTITY, start + (end - start) * unsafe)
	query.motion = Vector3.ZERO
	var rest: Dictionary = space.get_rest_info(query)
	var normal: Vector3 = rest.get("normal", Vector3.ZERO)
	var collider: Object = instance_from_id(rest["collider_id"]) if rest.has("collider_id") else null
	return {"time": safe, "position": start + (end - start) * safe, "normal": normal,
		"collider": collider}

## TdMove.MovementTraceForBlocking: true when the box is blocked anywhere on
## the way, including at the start.
func trace_blocked(end: Vector3, start: Vector3, extent: Vector3) -> bool:
	var hit: Dictionary = box_trace(end, start, extent)
	return hit["collider"] != null or float(hit["time"]) < 1.0

static func _miss() -> Dictionary:
	return {"time": 1.0, "normal": Vector3.ZERO, "collider": null, "position": Vector3.ZERO}

# --- the physics tick -----------------------------------------------------------

## APawn::performPhysics as far as the pawn's own motion goes: the frame's
## physics, from iteration 0.
func perform(dt: float) -> void:
	_just_teleported = false
	_recovered = false
	start_new_physics(dt, 0)
	# Grounded is declared for the move the frame ended in, whichever the
	# physics handed the body to on the way (Player.grounded's invariant).
	pawn.set_grounded(pawn.physics == Move.PHYS_WALKING)

## ATdPawn::startNewPhysics. Clears bUncontrolledSlide on every dispatch, so
## the flag is the current physics tick's own finding.
func start_new_physics(dt: float, iterations: int) -> void:
	if dt < MIN_REMAINING or iterations >= MAX_ITERATIONS:
		return
	pawn.uncontrolled_slide = false
	match pawn.physics:
		Move.PHYS_WALKING:
			phys_walking(dt, iterations)
		Move.PHYS_FALLING:
			phys_falling(dt, iterations)
		Move.PHYS_FLYING:
			phys_flying(dt, iterations)

## ATdPawn::setPhysics. [ME:CONFIRMED decompile N2 §4] Entering Falling stamps
## EnterFallingHeight with the body's centre height. Leaving Walking clears the
## ledge timer.
func set_physics(mode: int) -> void:
	if mode == pawn.physics:
		return
	if mode == Move.PHYS_FALLING:
		pawn.enter_falling_height = pawn.global_position.y
	if mode != Move.PHYS_WALKING:
		pawn.base = null
		pawn.clear_slide_off_ledge()
	pawn.physics = mode

## ATdPawn::physWalking. [ME:CONFIRMED decompile N1 §2]
func phys_walking(dt: float, iterations: int) -> void:
	var p: PawnConfig = pawn.config.pawn
	_carry_on_base(dt)
	var move = pawn.move_manager.current_move()
	var move_cfg: MoveConfig = move.current_config() if move != null else null
	var friction_modifier: float = move_cfg.friction_modifier if move_cfg != null else 1.0
	var speed_modifier: float = move_cfg.speed_modifier if move_cfg != null else 1.0
	var name: StringName = pawn.move_manager.current_name
	var sliding: bool = name == Move.SLIDE or name == Move.RAMP_SLIDE or name == Move.MELEE_SLIDE
	var walk_fric: float = walk_friction_modifier(pawn.velocity, pawn.floor_normal, sliding,
		friction_modifier, p)

	pawn.velocity.y = 0.0
	pawn.acceleration.y = 0.0
	var accel_dir: Vector3 = Vector3.ZERO if pawn.acceleration == Vector3.ZERO \
		else safe_normal(pawn.acceleration)
	var force: bool = pawn.force_max_accel_one_frame
	pawn.force_max_accel_one_frame = false
	if pawn.root_motion_active:
		# CalcVelocity's root-motion path hands over to the engine's own
		# APawn::CalcVelocity and scales the result by the move's
		# RootMotionScale. [ME:UNKNOWN] that engine path was not read (N1
		# open question 7); the animation's own velocity is taken as it is.
		pawn.velocity.x = pawn.root_motion_velocity.x
		pawn.velocity.z = pawn.root_motion_velocity.z
	else:
		var r: Array = calc_velocity(pawn.velocity, pawn.acceleration, accel_dir, dt, p.ground_speed,
			p.ground_friction * walk_fric, true, pawn.mobility_multiplier() * speed_modifier,
			p.accel_rate, p.braking_friction_strength, false,
			move != null and move.use_precise_location, force, pawn.facing())
		pawn.velocity = r[0]
		pawn.acceleration = r[1]

	var desired := Vector3(pawn.velocity.x, 0.0, pawn.velocity.z)
	var old_location: Vector3 = pawn.global_position
	var old_y: float = old_location.y
	var step: float = p.max_step_down_height
	var down := Vector3(0.0, -(step + STEP_FUDGE), 0.0)
	var hit: Dictionary = _miss()
	var remaining: float = dt
	while remaining > 0.0 and iterations < MAX_ITERATIONS:
		iterations += 1
		var tick: float = minf(MAX_SUB_STEP, remaining * 0.5) if remaining > MAX_SUB_STEP else remaining
		remaining -= tick
		var delta: Vector3 = desired * tick
		var sub_location: Vector3 = pawn.global_position
		var floor_from_step: Object = null
		var floor_normal_from_step := Vector3.ZERO
		var zero_move: bool = is_nearly_zero(delta)
		if zero_move:
			remaining = 0.0
		else:
			delta = _check_for_ledges(delta)
			var moved_fully: bool = false
			if pawn.floor_normal.y >= FLOOR_Z_DIRECT_MOVE or pawn.floor_normal.dot(delta) >= 0.0:
				hit = move_actor(delta)
				moved_fully = float(hit["time"]) >= 1.0
			else:
				# Uphill on a floor steeper than 11.5 degrees: straight to the
				# step-up, keeping the last floor trace's normal and actor.
				hit["time"] = 0.0
			if not moved_fully:
				var dist: float = delta.length()
				hit = _step_up(delta / dist, delta * (1.0 - float(hit["time"])), hit)
				if pawn.physics == Move.PHYS_FALLING:
					var travelled: float = _flat_distance(pawn.global_position, sub_location)
					remaining += tick * (1.0 - minf(1.0, travelled / dist))
					start_new_physics(remaining, iterations)
					return
				if float(hit["time"]) < 1.0:
					floor_normal_from_step = hit["normal"]
					floor_from_step = hit["collider"]

		var floor_dist: float
		if floor_from_step != null:
			hit = {"time": 0.1, "normal": floor_normal_from_step, "collider": floor_from_step,
				"position": pawn.global_position}
			floor_dist = MAX_FLOOR_DIST
		else:
			hit = sweep(down)
			floor_dist = (step + STEP_FUDGE) * float(hit["time"])
		var floor_normal: Vector3 = hit["normal"]
		pawn.floor_normal = floor_normal
		_check_uncontrolled_slide(hit)

		if floor_normal.y < pawn.walkable_floor_z and not is_nearly_zero(delta) \
				and floor_normal.dot(delta) < 0.0:
			# Walked into a surface too steep to stand on: pushed down along it.
			var d: float = step * floor_normal.y
			hit = move_actor(-(Vector3(0.0, step, 0.0) - floor_normal * d))
			if hit["collider"] != pawn.base and pawn.physics == Move.PHYS_WALKING:
				_set_base(hit["collider"])
			pawn.floor_normal = hit["normal"]
		elif float(hit["time"]) < 1.0 and not (hit["collider"] == pawn.base and floor_dist <= MAX_FLOOR_DIST):
			move_actor(Vector3.DOWN * maxf(floor_dist - FLOOR_DIST, 0.0))
			hit["time"] = 0.0
			if hit["collider"] != null and hit["collider"] != pawn.base \
					and pawn.physics == Move.PHYS_WALKING:
				_set_base(hit["collider"])
		elif floor_dist < MIN_FLOOR_DIST:
			move_actor(Vector3.UP * (FLOOR_DIST - floor_dist))
			hit["time"] = 0.0

		var good_floor: Vector3 = hit["normal"]
		if float(hit["time"]) < 1.0 and good_floor.y >= pawn.walkable_floor_z:
			continue

		# No walkable floor: [ME:CONFIRMED decompile N1 §2.1] the player can
		# always jump (Pawn.bCanJump), so the "refuse to walk off" branch is
		# never taken and the body walks off every ledge.
		var dist2: float = delta.length()
		if dist2 == 0.0:
			remaining = 0.0
		else:
			remaining += tick * (1.0 - minf(1.0, _flat_distance(pawn.global_position, sub_location) / dist2))
		pawn.velocity.y = 0.0
		if pawn.physics != Move.PHYS_WALKING:
			start_new_physics(remaining, iterations)
			return
		set_physics(Move.PHYS_FALLING)
		pawn.move_manager.set_move(Move.FALLING, true)
		start_new_physics(remaining, iterations)
		return

	if pawn.physics == Move.PHYS_WALKING:
		var dz: float = absf(pawn.global_position.y - old_y)
		if dz > 4.0 * UU and dz <= step:
			pawn.on_walking_step(pawn.global_position.y - old_y)
		if not _just_teleported and not _recovered:
			pawn.velocity = (pawn.global_position - old_location) / dt
		pawn.velocity.y = 0.0
	pawn.set_grounded(pawn.physics == Move.PHYS_WALKING)

## TdPlayerPawn's edge constants. [ME:CONFIRMED decompile, TdPlayerPawn CDO]
const EDGE_CHECK_MAX_SPEED := 300.0 * UU
const EDGE_CHECK_DISTANCE := 20.0 * UU
const EDGE_STOP_MIN_HEIGHT := 36.0 * UU
const VERTIGO_EDGE_PROBING_DISTANCE := 70.0 * UU
const VERTIGO_EDGE_PROBING_HEIGHT := 1000.0 * UU
const VERTIGO_EFFECT_THRESHOLD := 0.9
## The edge traces run this far under the feet, and the edge found is
## reported this far above where they hit. [ME:CONFIRMED decompile, 8.0]
const EDGE_FOOT_DROP := 8.0 * UU
## The 45-degree probes reach |Delta| / sqrt(2) + EdgeCheckDistance along an
## unnormalised diagonal. [ME:CONFIRMED decompile, 0.70710677]
const DIAGONAL_SCALE := 0.70710677
## CheckValidFloor's probe: how far past its offset it reaches, the most an
## edge may lie off the travel line, and how far behind the centre an edge
## must be before it counts. [ME:CONFIRMED decompile, 10 / 20 / 10]
const VALID_FLOOR_REACH := 10.0 * UU
const VALID_FLOOR_CREASE := 20.0 * UU
const VALID_FLOOR_MIN_OVERHANG := 10.0 * UU
## The extra reach of a square box past its half-width, 2 (sqrt(2) - 1).
const BOX_CORNER := 0.828427

## ATdPlayerPawn::CheckForLedges (0x012be0f0). [ME:CONFIRMED decompile N1
## §4.2, listing read] Only Crouch is held back at an edge. For every other
## move the clamp EdgeCheck computes is thrown away: it is a detector -- of
## Vertigo here, and of the SlideOffLedge timer inside EdgeCheck itself -- and
## the body walks straight off.
func _check_for_ledges(delta: Vector3) -> Vector3:
	var manager = pawn.move_manager
	var move: Move = manager.current_move()
	if pawn.avoid_ledges and move != null and move.avoid_ledges:
		var checked: Dictionary = edge_check(delta)
		var clamped: Vector3 = checked["delta"]
		if clamped != delta:
			if manager.current_name == Move.CROUCH:
				return clamped
			var dir: Vector3 = safe_normal(delta - clamped)
			var loc: Vector3 = pawn.collision_center()
			var probe: Vector3 = loc + dir * VERTIGO_EDGE_PROBING_DISTANCE
			var below: Dictionary = line_trace(probe, probe - Vector3.UP * VERTIGO_EDGE_PROBING_HEIGHT)
			if below.is_empty():
				_maybe_vertigo(probe - loc, checked["edge"], probe)
				if manager.current_name == Move.VERTIGO:
					return Vector3.ZERO
				return delta
	if manager.current_name == Move.VERTIGO:
		manager.set_move(Move.WALKING)
	return delta

## The Vertigo trigger inside CheckForLedges: facing the drop, walking, slower
## than a run, at an edge at least 2 uu from the last one it fired on, and
## TdPawn.CanDoMove(MOVE_Vertigo). Vertigo's own RedoMoveTime is never asked:
## its CanDoMove does not call the base, so only the edge distance keeps it
## from firing again. CanDoMove is asked BEFORE the new edge is stored, so
## the "edge in front" it checks is the one stored last time -- the zero
## vector, for the first vertigo of a life. Kept.
func _maybe_vertigo(to_probe: Vector3, edge: Vector3, probe: Vector3) -> void:
	var manager = pawn.move_manager
	var vertigo = manager.move_for(Move.VERTIGO)
	if vertigo == null:
		return
	var d: Vector3 = to_probe.normalized() if to_probe.length_squared() > 1e-8 * UU * UU else to_probe
	if absf(d.dot(pawn.pawn_facing())) <= VERTIGO_EFFECT_THRESHOLD:
		return
	if manager.current_name != Move.WALKING:
		return
	if walking_state(pawn.horizontal_speed()) >= WAS_RUN:
		return
	if edge.distance_to(vertigo.last_actual_edge_position) < 2.0 * UU:
		return
	if not manager.pawn_can_do(Move.VERTIGO):
		return
	vertigo.last_edge_position = probe
	vertigo.last_actual_edge_position = edge
	manager.set_move(Move.VERTIGO)

## ATdPawn::EdgeCheck (0x012b8a30). [ME:CONFIRMED decompile, read by W2c:
## constants resolved from the binary] Returns {delta, edge}: the walking
## sub-step's delta, clamped against the edge it is about to cross, and the
## edge point found (ZERO when none).
##
## Three line traces straight down, from the body's centre height to
## EdgeStopMinHeight + 4 uu under the feet: one EdgeCheckDistance past the end
## of the delta, two along the forward diagonals. A probe that lands more than
## MaxStepHeight under the feet, or on an unwalkable face, has no floor.
## Two of the three without floor arm the 0.2 s SlideOffLedge timer. Faster
## than EdgeCheckMaxSpeed, or with the hint forward or back, the delta comes
## back unchanged. Otherwise a horizontal trace just under the feet finds the
## edge's face and the delta loses its component into that face's normal --
## or, at an outside corner, both faces are found and the delta is cut against
## one, the other, or stopped outright.
func edge_check(delta: Vector3) -> Dictionary:
	var p: PawnConfig = pawn.config.pawn
	var loc: Vector3 = pawn.collision_center()
	var h: float = pawn.collision_half_height()
	var r: float = pawn.collision_radius()
	var walkable: float = pawn.walkable_floor_z
	var edge := Vector3.ZERO
	var d: Vector3 = safe_normal_2d(delta)
	var right: Vector3 = d.cross(Vector3.UP)
	var diag_right: Vector3 = d + right
	var diag_left: Vector3 = d - right
	var depth: float = h + EDGE_STOP_MIN_HEIGHT + 4.0 * UU
	var floor_fraction: float = (h + p.max_step_down_height) / depth
	var diagonal_reach: float = Vector2(delta.x, delta.z).length() * DIAGONAL_SCALE + EDGE_CHECK_DISTANCE
	var centre: Dictionary = _edge_probe(loc + delta + d * EDGE_CHECK_DISTANCE, depth)
	var first: Dictionary = _edge_probe(loc + diag_right * diagonal_reach, depth)
	var second: Dictionary = _edge_probe(loc + diag_left * diagonal_reach, depth)
	var gap_centre: int = 1 if _no_floor(centre, floor_fraction, walkable) else 0
	var gap_first: int = 1 if _no_floor(first, floor_fraction, walkable) else 0
	var gap_second: int = 1 if _no_floor(second, floor_fraction, walkable) else 0
	if (gap_centre + gap_first == 2) or (gap_centre + gap_first + gap_second == 2):
		pawn.arm_slide_off_ledge()
	var speed2d_sq: float = pawn.velocity.x * pawn.velocity.x + pawn.velocity.z * pawn.velocity.z
	if speed2d_sq > EDGE_CHECK_MAX_SPEED * EDGE_CHECK_MAX_SPEED \
			or pawn.move_action_hint == Move.MAH_UP or pawn.move_action_hint == Move.MAH_DOWN:
		return {"delta": delta, "edge": edge}
	# For the clamp an edge is a probe that hit nothing at all or hit an
	# unwalkable face -- not the depth threshold above.
	var bad_centre: bool = _missed_or_steep(centre, walkable)
	var bad_first: bool = _missed_or_steep(first, walkable)
	var bad_second: bool = _missed_or_steep(second, walkable)
	if not bad_centre and not bad_first and not bad_second:
		return {"delta": delta, "edge": edge}
	var foot_y: float = loc.y - h - EDGE_FOOT_DROP
	var reach: float = r - 4.0 * UU
	var limit_sq: float = EDGE_CHECK_DISTANCE * EDGE_CHECK_DISTANCE
	if not (bad_second and bad_first):
		var f: Vector3 = d if bad_centre else (diag_left if bad_second else diag_right)
		var face: Dictionary = _edge_face(loc, f, reach, foot_y, walkable)
		if face.is_empty():
			return {"delta": delta, "edge": edge}
		var n: Vector3 = safe_normal_2d(face["normal"])
		var to_face: Vector3 = face["position"] - loc
		var along: float = (to_face.x * n.x + to_face.z * n.z) / maxf(n.length_squared(), 1e-12)
		var plane := Vector2(n.x * along, n.z * along)
		var out: Vector3 = delta
		if plane.length_squared() - (delta.x * delta.x + delta.z * delta.z) <= limit_sq:
			out = delta - n * delta.dot(n)
		edge = face["position"] + Vector3.UP * EDGE_FOOT_DROP
		return {"delta": out, "edge": edge}
	# An outside corner: both diagonals fell away.
	var face_a: Dictionary = _edge_face(loc, diag_left, reach, foot_y, walkable)
	if not face_a.is_empty():
		edge = face_a["position"] + Vector3.UP * EDGE_FOOT_DROP
	var face_b: Dictionary = _edge_face(loc, diag_right, reach, foot_y, walkable)
	if not face_b.is_empty():
		edge = face_b["position"] + Vector3.UP * EDGE_FOOT_DROP
	var raw_a: Vector3 = face_a.get("raw_normal", Vector3.ZERO)
	var raw_b: Vector3 = face_b.get("raw_normal", Vector3.ZERO)
	var clamp_a: Vector3 = delta - raw_a * delta.dot(raw_a)
	var clamp_b: Vector3 = delta - raw_b * delta.dot(raw_b)
	var dist_a: float = _corner_distance(face_a, loc, clamp_a)
	var dist_b: float = _corner_distance(face_b, loc, clamp_b)
	var has_a: bool = not face_a.is_empty()
	var has_b: bool = not face_b.is_empty()
	var out_corner: Vector3 = delta
	if dist_b > limit_sq:
		if dist_a <= limit_sq and has_a:
			out_corner = clamp_a
	elif dist_a <= limit_sq:
		if has_a or has_b:
			out_corner = Vector3.ZERO
	elif has_b:
		out_corner = clamp_b
	return {"delta": out_corner, "edge": edge}

## One of EdgeCheck's downward probes: {time, normal}, time 1 on a miss.
func _edge_probe(from: Vector3, depth: float) -> Dictionary:
	var hit: Dictionary = line_trace(from, from - Vector3.UP * depth)
	if hit.is_empty():
		return {"time": 1.0, "normal": Vector3.ZERO}
	return {"time": float(hit["time"]), "normal": hit["normal"]}

static func _no_floor(probe: Dictionary, floor_fraction: float, walkable: float) -> bool:
	var normal: Vector3 = probe["normal"]
	return floor_fraction < float(probe["time"]) or normal.y < walkable

static func _missed_or_steep(probe: Dictionary, walkable: float) -> bool:
	var normal: Vector3 = probe["normal"]
	return float(probe["time"]) >= 1.0 or normal.y < walkable

## The horizontal trace under the feet that finds an edge's face: from `reach`
## beyond the centre along `f`, back toward the body. Empty unless it hit, did
## not start inside anything, and hit a face too steep to stand on.
func _edge_face(loc: Vector3, f: Vector3, reach: float, foot_y: float, walkable: float) -> Dictionary:
	var start := Vector3(loc.x + f.x * reach, foot_y + f.y * reach, loc.z + f.z * reach)
	var end := Vector3(loc.x - f.x * reach, foot_y - f.y * reach, loc.z - f.z * reach)
	var hit: Dictionary = line_trace(start, end)
	if hit.is_empty():
		return {}
	var t: float = hit["time"]
	var normal: Vector3 = hit["normal"]
	if t >= 1.0 or t <= 0.0 or normal.y >= walkable:
		return {}
	return {"position": hit["position"], "normal": normal, "raw_normal": normal}

## At an outside corner: how far the clamped delta leaves the body from the
## face's plane, squared and horizontal. 0 for a face that was not found.
static func _corner_distance(face: Dictionary, loc: Vector3, clamped: Vector3) -> float:
	if face.is_empty():
		return 0.0
	var n: Vector3 = safe_normal_2d(face["normal"])
	var to_face: Vector3 = face["position"] - loc
	var along: float = (to_face.x * n.x + to_face.z * n.z) / maxf(n.length_squared(), 1e-12)
	var dx: float = along * n.x - clamped.x
	var dz: float = along * n.z - clamped.z
	return dx * dx + dz * dz

## ATdPlayerPawn::CheckValidFloor (0x012b6ac0, with its probe 0x012b5eb0).
## [ME:CONFIRMED decompile, read by W2c] Whether the footing under a body
## arriving along `current_delta` on a floor `check_floor` is real. Two
## horizontal probes just under the feet, ahead along the delta and across
## it, both projected onto the floor's plane, look for an edge face the centre
## has already passed by more than 10 uu. None: valid. One: the body is pushed
## back on to the floor's side of it far enough for the box to clear, and a
## downward sweep MaxStepHeight + 2 uu from there decides. With `slide_off`, a
## body found unsupported is moved by that push for real and its evade timer
## set; the push is undone if blocked.
##
## The original also offsets the drawn mesh back by the push (vt 0x424);
## that is the presentation's and not ported.
func check_valid_floor(current_delta: Vector3, check_floor: Vector3, slide_off: bool) -> bool:
	var p: PawnConfig = pawn.config.pawn
	var loc: Vector3 = pawn.collision_center()
	var h: float = pawn.collision_half_height()
	var r: float = pawn.collision_radius()
	var feet := Vector3(loc.x, loc.y - h, loc.z)
	var flat_sq: float = current_delta.x * current_delta.x + current_delta.z * current_delta.z
	var d: Vector3 = pawn.pawn_facing() if flat_sq <= 0.0 else safe_normal_2d(current_delta)
	var m: float = maxf(absf(d.z), absf(d.x))
	if m <= 0.0:
		return true
	var f: Vector3 = check_floor
	var ahead: Vector3 = safe_normal(d - f * f.dot(d)) / m
	var left: Vector3 = Vector3.UP.cross(Vector3(d.x, 0.0, d.z)) + Vector3(0.0, d.y, 0.0)
	var across: Vector3 = safe_normal(left - f * f.dot(left)) / m
	var floor_flat_sq: float = f.x * f.x + f.z * f.z
	var box: float = 1.0
	if floor_flat_sq >= 1e-8:
		var fn: Vector3 = safe_normal_2d(f)
		box = maxf(absf(fn.z), absf(fn.x))
	if f.y != 0.0:
		feet.y -= ((1.0 / box) / f.y) * r * sqrt(floor_flat_sq)
	var push: Variant = _valid_floor_probe(feet, ahead * r, loc, r)
	if push == null:
		push = _valid_floor_probe(feet, across * r, loc, r)
		if push == null:
			return true
	var out: Vector3 = push
	var start: Vector3 = loc + out
	var end: Vector3 = start - Vector3.UP * (p.max_step_down_height + STEP_FUDGE)
	var below: Dictionary = box_trace(end, start, Vector3(r, h, r))
	var below_normal: Vector3 = below["normal"]
	if float(below["time"]) < 1.0 and (float(below["time"]) <= 0.0 or below_normal.y >= pawn.walkable_floor_z):
		return true
	if slide_off:
		var moved: Dictionary = move_actor(out)
		if float(moved["time"]) != 1.0:
			move_actor(-out * float(moved["time"]))
			return true
		pawn.evade_timer = 0.2
	return false

## CheckValidFloor's probe (0x012b5eb0): the push that clears the box of an
## edge face found under the feet along `offset`, or null when there is none.
func _valid_floor_probe(feet: Vector3, offset: Vector3, loc: Vector3, r: float) -> Variant:
	var on: Vector3 = safe_normal(offset)
	var ext: Vector3 = offset + on * VALID_FLOOR_REACH
	var base := Vector3(feet.x, feet.y - 4.0 * UU, feet.z)
	var a: Vector3 = base + ext
	var b: Vector3 = base - ext
	var hit_1: Dictionary = _face_hit(line_trace(a, b))
	var hit_2: Dictionary = _face_hit(line_trace(b, a))
	var pick: Dictionary
	if not hit_1.is_empty():
		if not hit_2.is_empty() and (hit_1["normal"] as Vector3).dot(hit_2["normal"]) < 0.0:
			# A crease: two faces looking at each other.
			var crease: Vector3 = safe_normal_2d(hit_1["normal"] - hit_2["normal"])
			if (hit_1["position"] - hit_2["position"]).dot(crease) >= VALID_FLOOR_CREASE:
				return null
			var d1: float = Vector2(loc.x - hit_1["position"].x, loc.z - hit_1["position"].z).length()
			var d2: float = Vector2(loc.x - hit_2["position"].x, loc.z - hit_2["position"].z).length()
			pick = hit_2 if d2 <= d1 else hit_1
			var nn: Vector3 = safe_normal_2d(pick["normal"])
			var o2: Vector3 = safe_normal_2d(offset)
			var sign: float = -1.0 if (pick["position"] - loc).dot(nn) > 0.0 else 1.0
			var push: float = _box_reach(nn, r) + 2.0 * UU - sign * absf(minf(d1, d2) * o2.dot(nn))
			return nn * maxf(push, 0.0)
		pick = hit_1
	else:
		if hit_2.is_empty():
			return null
		pick = hit_2
	var n: Vector3 = safe_normal_2d(pick["normal"])
	var overhang: float = -((pick["position"] - loc).dot(n))
	if overhang <= VALID_FLOOR_MIN_OVERHANG:
		return null
	return n * maxf(_box_reach(n, r) + 2.0 * UU - overhang, 0.0)

## A line trace's hit as CheckValidFloor counts it: started outside, stopped
## short, on a face too steep to stand on.
func _face_hit(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {}
	var t: float = hit["time"]
	var normal: Vector3 = hit["normal"]
	if t >= 1.0 or t <= 0.0 or normal.y >= pawn.walkable_floor_z:
		return {}
	return hit

## How far a square box of half-width `r` reaches along the flat direction
## `n`: (1 + 0.828427 m sqrt(1 - m^2)) r with m its larger component.
static func _box_reach(n: Vector3, r: float) -> float:
	var m: float = maxf(absf(n.z), absf(n.x))
	var c: float = minf(m * m, 1.0)
	return (sqrt(1.0 - c) * m * BOX_CORNER + 1.0) * r

## ATdPawn::stepUp. [ME:CONFIRMED decompile N1 §4.1] Returns the final hit.
func _step_up(desired_dir: Vector3, delta: Vector3, hit_in: Dictionary) -> Dictionary:
	var p: PawnConfig = pawn.config.pawn
	var down := Vector3(0.0, -(p.max_step_down_height + STEP_FUDGE), 0.0)
	var step_down: bool = true
	var step_ok: bool = true
	var orig_hit: Dictionary = hit_in.duplicate()
	var hit: Dictionary = hit_in
	var in_normal: Vector3 = hit_in["normal"]
	# No Abs here, unlike stock UE3: a ceiling counts as a wall.
	if in_normal.y < MAX_STEP_SIDE_Z or in_normal.y >= pawn.walkable_floor_z:
		move_actor(-down + in_normal * (0.1 * UU))
		var step_location: Vector3 = pawn.global_position
		hit = move_actor(delta)
		var landed_normal: Vector3 = hit["normal"]
		if float(hit["time"]) >= 1.0 or landed_normal.y < pawn.walkable_floor_z:
			var below: Dictionary = sweep(down)
			var below_normal: Vector3 = below["normal"]
			if float(below["time"]) < 1.0 and below_normal.y < pawn.walkable_floor_z:
				hit = orig_hit.duplicate()
				move_actor(step_location - pawn.global_position)
				step_ok = false
	elif pawn.physics != Move.PHYS_WALKING:
		hit = move_actor(delta + Vector3(0.0, delta.length() * in_normal.y, 0.0))
		step_down = false

	if float(hit["time"]) < 1.0:
		var normal: Vector3 = hit["normal"]
		if normal.y < MAX_STEP_SIDE_Z and float(hit["time"]) * delta.length_squared() > MIN_STEP_SIZE_SQUARED:
			if step_down:
				move_actor(down)
			return _step_up(desired_dir, delta * (1.0 - float(hit["time"])), hit)
		var handled: bool = false
		if step_ok and normal.y < pawn.walkable_floor_z and not (hit["collider"] is CharacterBody3D):
			var along: Vector3 = safe_normal_2d(delta - normal * delta.dot(normal))
			handled = _corner_slip(along, false, delta, hit)
		if not handled:
			_process_hit_wall(hit)
			if pawn.physics == Move.PHYS_FALLING:
				return hit
			var n: Vector3 = safe_normal(Vector3(normal.x, 0.0, normal.z))
			var new_delta: Vector3 = (delta - n * delta.dot(n)) * (1.0 - float(hit["time"]))
			if safe_normal(new_delta).dot(safe_normal(delta)) > 0.707:
				# Deflected by less than 45 degrees: the whole remaining length
				# carries on along the wall, so a shallow wall hit costs no speed.
				new_delta = safe_normal(new_delta) * delta.length() * (1.0 - float(hit["time"]))
			if new_delta.dot(delta) >= 0.0:
				hit = move_actor(new_delta)
				if step_ok and float(hit["time"]) < 1.0:
					var n2: Vector3 = safe_normal_2d(hit["normal"])
					var try_slip: bool = n2.dot(safe_normal_2d(new_delta)) < -0.707 \
						and not (hit["collider"] is CharacterBody3D)
					var slipped: bool = false
					if try_slip:
						slipped = _corner_slip(-safe_normal_2d(new_delta - n2 * n2.dot(new_delta)),
							true, new_delta, hit)
					if not slipped:
						_process_hit_wall(hit)
						if pawn.physics == Move.PHYS_FALLING:
							return hit
						new_delta = two_wall_adjust(desired_dir, new_delta, hit["normal"], n,
							float(hit["time"]))
						hit = move_actor(new_delta)
	if step_down:
		hit = move_actor(down)
	return hit

## The corner slip (0x012b0ec0). [ME:CONFIRMED decompile N1 §4.3] Lets the
## body slip past a wall corner within 32 uu of its line of travel instead of
## stopping on it. Returns whether it carried the move.
func _corner_slip(along: Vector3, probe_ahead: bool, delta: Vector3, orig_hit: Dictionary) -> bool:
	if along == Vector3.ZERO:
		return false
	var orig_normal: Vector3 = orig_hit["normal"]
	if -orig_normal.dot(safe_normal(delta)) < 0.707:
		return false
	var start: Vector3 = pawn.global_position
	var handled: bool = false
	var side: Dictionary = move_actor(along * CORNER_SLIP_REACH)
	var side_time: float = side["time"]
	if side_time >= 0.0 and side_time < 1.0:
		move_actor(-along * CORNER_SLIP_REACH * side_time)
	else:
		var blocked_ahead: bool = probe_ahead \
			and float(sweep(safe_normal_2d(delta) * CORNER_SLIP_PROBE)["time"]) < 1.0
		if not blocked_ahead:
			var rest: Dictionary = move_actor(delta * (1.0 - float(orig_hit["time"])))
			handled = float(rest["time"]) >= 1.0
		move_actor(-along * CORNER_SLIP_REACH)
	var moved: Vector3 = pawn.global_position - start
	if Vector2(moved.x, moved.z).length_squared() > Vector2(delta.x, delta.z).length_squared():
		_just_teleported = true
		pawn.evade_timer = 0.2
	return handled

## APawn::processHitWall for a pawn with bDirectHitWall: the current move's
## HitWall, and only when something was hit. [ME:CONFIRMED decompile N2 §5]
func _process_hit_wall(hit: Dictionary) -> void:
	if hit["collider"] == null:
		return
	var move = pawn.move_manager.current_move()
	if move != null:
		move.hit_wall(hit["normal"], hit["collider"])

## CheckUncontrolledSlideSurface: a surface marked for the uncontrolled slide
## (the original's TdPhysicalMaterialProperty.bEnableUncontrolledSlide, this
## project's Probes.UNCONTROLLED_SLIDE_GROUP) raises bUncontrolledSlide for
## this physics tick, unless the body is already falling uncontrolled.
func _check_uncontrolled_slide(hit: Dictionary) -> void:
	if hit["collider"] == null or pawn.move_manager.current_name == Move.FALL_UNCONTROLLED:
		return
	if Probes.is_uncontrolled_slide(hit["collider"]):
		pawn.uncontrolled_slide = true
		pawn.uncontrolled_slide_normal = hit["normal"]

## The UE3 base: a body standing on something that moves is moved with it.
## The carry is the base's own transform change since the last tick.
func _set_base(collider: Object) -> void:
	pawn.base = collider
	if collider is Node3D:
		pawn.base_transform = (collider as Node3D).global_transform

func _carry_on_base(dt: float) -> void:
	pawn.base_velocity = Vector3.ZERO
	var base = pawn.base
	if base == null or not is_instance_valid(base) or not (base is Node3D):
		pawn.base = null
		return
	var now: Transform3D = (base as Node3D).global_transform
	if now == pawn.base_transform:
		return
	var carried: Vector3 = now * (pawn.base_transform.affine_inverse() * pawn.global_position)
	pawn.base_transform = now
	var shift: Vector3 = carried - pawn.global_position
	move_actor(shift)
	if dt > 0.0:
		pawn.base_velocity = shift / dt

## ATdPlayerPawn::physFalling. [ME:CONFIRMED emulated N2 §2]
##
## Not ported: water, the ceiling-corner nudge (2a). Root motion is taken as
## the move hands it over (Player.root_motion_velocity), not read off a mesh.
func phys_falling(dt: float, iterations: int) -> void:
	var p: PawnConfig = pawn.config.pawn
	var root_motion: bool = pawn.root_motion_active
	if root_motion:
		# RMM_Accel: the horizontal velocity is the animation's, the
		# acceleration is dropped, and no bound applies to it.
		pawn.velocity.x = pawn.root_motion_velocity.x
		pawn.velocity.z = pawn.root_motion_velocity.z
		pawn.acceleration = Vector3.ZERO
	var old_accel: Vector3 = pawn.acceleration
	var a: Vector3 = Vector3.ZERO if root_motion else falling_accel_bound(pawn.velocity,
		pawn.acceleration, dt, p.accel_rate, p.air_control, p.ground_speed)
	var remaining: float = dt
	if dt > 0.0:
		while iterations < MAX_ITERATIONS:
			iterations += 1
			var tick: float = minf(MAX_SUB_STEP, remaining * 0.5) if remaining > MAX_SUB_STEP else remaining
			remaining -= tick
			var old_location: Vector3 = pawn.global_position
			var old_velocity: Vector3 = pawn.velocity
			_landing_teleported = false
			_recovered = false
			pawn.velocity = old_velocity + (a + Vector3(0.0, pawn.gravity_z(), 0.0)) * tick
			var adjusted: Vector3 = pawn.velocity * tick
			# The landing edge test can send the move round again. [ME:CONFIRMED
			# emulated N2 §2c] Its flag is never cleared inside the loop, so a
			# second pass that meets a floor does not land at all.
			var retry: bool = false
			var retry_count: int = 0
			while true:
				var hit: Dictionary = move_actor(adjusted)
				if float(hit["time"]) < 1.0:
					var normal: Vector3 = hit["normal"]
					if normal.y < pawn.walkable_floor_z:
						# A wall or a ceiling.
						_process_hit_wall(hit)
						if pawn.physics != Move.PHYS_FALLING:
							return
						# TdPawn's ComputeSlideVector tests the surface for the uncontrolled
						# slide first. [ME:CONFIRMED decompile N2 §2b]
						_check_uncontrolled_slide(hit)
						var slide: Vector3 = compute_slide_vector(adjusted, normal, float(hit["time"]))
						if slide.dot(adjusted) >= 0.0:
							var target: Vector3 = pawn.global_position + slide
							var hit2: Dictionary = move_actor(slide)
							var stepped: bool = false
							var resolved: bool = false
							if safe_normal(slide).y < pawn.walkable_floor_z - 1.0:
								if float(hit2["time"]) >= 1.0:
									resolved = true
								else:
									hit2 = move_actor(target + Vector3(0.0, 1.9 * UU, 0.0) - pawn.global_position)
									stepped = true
							if not resolved:
								if float(hit2["time"]) < 1.0:
									var normal2: Vector3 = hit2["normal"]
									if normal2.y < pawn.walkable_floor_z:
										_process_hit_wall(hit2)
										if pawn.physics != Move.PHYS_FALLING:
											return
										var twin: Vector3 = two_wall_adjust(safe_normal(adjusted), slide,
											normal2, normal, float(hit2["time"]))
										var ditch: bool = normal.y > 0.0 and normal2.y > 0.0 \
											and twin.y == 0.0 and normal.dot(normal2) < 0.0
										var hit3: Dictionary = move_actor(twin)
										var normal3: Vector3 = hit3["normal"]
										if ditch or (float(hit3["time"]) < 1.0 and normal3.y >= pawn.walkable_floor_z):
											process_landed(normal3 if float(hit3["time"]) < 1.0 else normal2,
												0.0, iterations)
											return
									else:
										# A floor found by the slide: the same edge test,
										# on the slide's own delta. [ME:INFERRED] the
										# listing for this path was not read past the
										# call; a re-move it asks for is not made here,
										# the sub-step simply does not land.
										if _landing_edge_retry(slide, hit2):
											retry = true
										if not retry:
											_check_uncontrolled_slide(hit2)
											process_landed(normal2, 0.0, iterations)
											return
								elif stepped:
									move_actor(Vector3(0.0, -1.9 * UU, 0.0))
						# The blocked fraction of the step is lost; what remains is
						# the displacement the slide actually made.
						old_velocity.x = (pawn.global_position.x - old_location.x) / tick
						old_velocity.z = (pawn.global_position.z - old_location.z) / tick
					else:
						# A floor.
						if _landing_edge_retry(adjusted, hit):
							retry = true
							adjusted *= 1.0 - float(hit["time"])
						if not retry:
							remaining += (1.0 - float(hit["time"])) * tick
							if not _landing_teleported and float(hit["time"]) > LANDING_REBUILD_TIME \
									and float(hit["time"]) * tick > LANDING_REBUILD_SECONDS:
								pawn.velocity = (pawn.global_position - old_location) / (tick * float(hit["time"]))
							_check_uncontrolled_slide(hit)
							process_landed(normal, remaining, iterations)
							return
				retry_count += 1
				if not (retry and retry_count < 2):
					break
			# The velocity rebuilt from the displacement: V = 2 dLoc/dt - V0, which
			# doubles every acceleration integrated above, gravity included.
			if not root_motion and not _landing_teleported and not _recovered \
					and pawn.physics != Move.PHYS_NONE:
				pawn.velocity = (pawn.global_position - old_location) / tick
				if pawn.velocity.y < old_velocity.y or old_velocity.y >= 0.0:
					pawn.velocity = pawn.velocity * 2.0 - old_velocity
				if pawn.velocity.length_squared() > p.terminal_velocity * p.terminal_velocity:
					pawn.velocity = safe_normal(pawn.velocity) * p.terminal_velocity
			if remaining <= 0.0:
				break
	pawn.acceleration = old_accel
	pawn.set_grounded(false)

## physFalling's bJustTeleported for the sub-step: set by a landing edge test
## that moved the body, and then the velocity is not rebuilt.
var _landing_teleported: bool = false

## The landing edge test (TdPlayerPawn, N2 §2c). [ME:CONFIRMED emulated N2 §2c]
## Returns true when the move must be made again instead of landing.
##
## Not in an uncontrolled fall. A landing that is hard -- fallen further than
## the hard landing height, onto a surface excluded from hand and foot moves,
## or out of a turn in the air -- asks CheckValidFloor to push the body off an
## edge it is not really standing on, and if it did, arms SlideOffLedge and
## makes the rest of the move again from where the push left it. Any other
## landing only arms SlideOffLedge when the footing is bad, and lands anyway.
##
## "Excluded for hand and foot moves" is this project's Probes.is_inert().
## [ME:INFERRED] the original reads two actor bits and two component bits.
func _landing_edge_retry(adjusted: Vector3, hit: Dictionary) -> bool:
	var manager = pawn.move_manager
	if manager.current_name == Move.FALL_UNCONTROLLED:
		return false
	if adjusted.y == 0.0:
		return false
	var fall: float = pawn.enter_falling_height - pawn.global_position.y
	var hard: bool = pawn.config.pawn.hard_landing_height < fall \
		or Probes.is_inert(hit["collider"]) \
		or manager.current_name == Move.TURN_180_IN_AIR
	if hard:
		if not check_valid_floor(adjusted, hit["normal"], true):
			pawn.arm_slide_off_ledge(true)
			_landing_teleported = true
			return true
		return false
	if not check_valid_floor(adjusted, hit["normal"], false):
		pawn.arm_slide_off_ledge(true)
	return false

## APawn::processLanded. [ME:CONFIRMED decompile N2 §3] The floor normal, the
## landing event, the post-landing physics, and the rest of the frame walked
## with an acceleration of ONE uu/s^2 -- the falling bound normalised, not the
## input's.
##
## Not ported: the stuck-landing FindSpot jiggle for a body standing on
## nothing.
func process_landed(normal: Vector3, remaining: float, iterations: int) -> void:
	pawn.floor_normal = normal
	# What the presentation reads about this landing (the camera's dip).
	pawn.last_landing_fall_height = pawn.enter_falling_height - pawn.global_position.y
	pawn.last_landing_coiled = pawn.coiled_since_ground
	pawn.last_landing_rolled = false
	pawn.notify_landed(maxf(-pawn.velocity.y, 0.0))
	pawn.set_grounded(true)
	pawn.pawn_landed(normal)
	if pawn.physics == Move.PHYS_FALLING:
		set_physics(Move.PHYS_WALKING if not pawn.is_dying() else Move.PHYS_NONE)
	if pawn.physics == Move.PHYS_WALKING:
		pawn.acceleration = safe_normal(pawn.acceleration) * UU
	start_new_physics(remaining, iterations)

## APawn::physFlying, for the precise-location flights (Jump's ledge assist):
## the velocity the move set, moved through the world without colliding when
## collision is off.
func phys_flying(dt: float, _iterations: int) -> void:
	var old_location: Vector3 = pawn.global_position
	var hit: Dictionary = move_actor(pawn.velocity * dt)
	if float(hit["time"]) < 1.0:
		_process_hit_wall(hit)
		move_actor(compute_slide_vector(pawn.velocity * dt, hit["normal"], float(hit["time"])))
	if dt > 0.0 and not _just_teleported and not _recovered and pawn.collide_world:
		pawn.velocity = (pawn.global_position - old_location) / dt
	pawn.set_grounded(false)

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

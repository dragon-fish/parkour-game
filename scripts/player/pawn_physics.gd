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
## A corner slip's forward move that got no further than this fraction counts
## as blocked, for its step-down.
const CORNER_SLIP_BLOCKED := 0.05
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

## bJustTeleported: the body was put somewhere its velocity did not take it
## (the corner slip, the ceiling nudge), so the physics must not rebuild the
## velocity from the displacement. [ME:CONFIRMED decompile N1 §2.1, N2 §2]
## Cleared where the original clears it: once at the top of every physWalking
## call, and at the top of every physFalling sub-step -- so the walk that
## finishes a landing frame rebuilds its velocity whatever the fall set.
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
	pawn.align_collider()
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

## SingleLineCheck with the pawn's own box as the extent: where the body
## would stop if moved by `motion`, without moving it.
func sweep(motion: Vector3, from: Transform3D = Transform3D()) -> Dictionary:
	pawn.align_collider()
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
	# The walking and falling physics clear both again on their own entry, as
	# the original does; this covers phys_flying, which does not.
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
	_just_teleported = false
	_recovered = false
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

		if floor_normal.y < p.walkable_floor_z and not is_nearly_zero(delta) \
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
		if float(hit["time"]) < 1.0 and good_floor.y >= p.walkable_floor_z:
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

## ATdPlayerPawn::CheckForLedges. [ME:CONFIRMED decompile N1 §4.2] Only Crouch
## is actually held back at an edge; for every other move the edge clamp is a
## detector (Vertigo, the SlideOffLedge timer), and neither of those exists
## here yet. Crouch is not ported, so nothing is clamped.
func _check_for_ledges(delta: Vector3) -> Vector3:
	return delta

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
	if in_normal.y < MAX_STEP_SIDE_Z or in_normal.y >= p.walkable_floor_z:
		move_actor(-down + in_normal * (0.1 * UU))
		var step_location: Vector3 = pawn.global_position
		hit = move_actor(delta)
		var landed_normal: Vector3 = hit["normal"]
		if float(hit["time"]) >= 1.0 or landed_normal.y < p.walkable_floor_z:
			var below: Dictionary = sweep(down)
			var below_normal: Vector3 = below["normal"]
			if float(below["time"]) < 1.0 and below_normal.y < p.walkable_floor_z:
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
		if step_ok and normal.y < p.walkable_floor_z and not (hit["collider"] is CharacterBody3D):
			var along: Vector3 = safe_normal_2d(delta - normal * delta.dot(normal))
			# The slip scales a copy of Delta here: New below is taken from
			# stepUp's own, unscaled. Hit is whatever the slip left in it.
			handled = _corner_slip(along, _uses_custom_collision(), false, delta, hit)[0]
		if not handled:
			_process_hit_wall(hit)
			if pawn.physics == Move.PHYS_FALLING:
				return hit
			var wall_normal: Vector3 = hit["normal"]
			var n: Vector3 = safe_normal(Vector3(wall_normal.x, 0.0, wall_normal.z))
			var new_delta: Vector3 = (delta - n * delta.dot(n)) * (1.0 - float(hit["time"]))
			if safe_normal(new_delta).dot(safe_normal(delta)) > 0.707:
				# Deflected by less than 45 degrees: the whole remaining length
				# carries on along the wall, so a shallow wall hit costs no speed.
				new_delta = safe_normal(new_delta) * delta.length() * (1.0 - float(hit["time"]))
			if new_delta.dot(delta) >= 0.0:
				hit = move_actor(new_delta)
				if step_ok and float(hit["time"]) < 1.0:
					var hit_normal: Vector3 = hit["normal"]
					var n2: Vector3 = safe_normal_2d(hit_normal)
					var try_slip: bool = n2.dot(safe_normal_2d(new_delta)) < -0.707 \
						and not (hit["collider"] is CharacterBody3D)
					var slipped: bool = false
					if try_slip:
						# Along the wall as the 3D normal has it; New comes back
						# scaled, and the wall adjust below works on that.
						var slip: Array = _corner_slip(
							-safe_normal_2d(new_delta - hit_normal * hit_normal.dot(new_delta)),
							false, true, new_delta, hit)
						slipped = slip[0]
						new_delta = slip[1]
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
## stopping on it: 32 uu sideways (undone by what it got if that was blocked),
## then -- unless `probe_ahead` finds the way 34 uu ahead blocked -- Delta,
## scaled in place by (1 - Hit.Time), forward from there; blocked at once with
## `step_down_too`, a MaxStepHeight step down and Delta again (the step taken
## back if that is blocked too); then the 32 uu back.
##
## Returns [handled, delta]: handled when the last forward move went all the
## way, and the caller's Delta as the slip left it. `hit` is the caller's Hit,
## rewritten as the original rewrites its one FCheckResult: back to what it
## came in with, unless the slip moved forward -- then the last forward or
## step-down move's. bJustTeleported is ASSIGNED, so a slip can clear it:
## set when the body ended further from where it started, flat, than Delta
## reaches. The mesh offset it hides that with (OffsetMeshXY) is not ported.
func _corner_slip(along: Vector3, step_down_too: bool, probe_ahead: bool, delta: Vector3,
		hit: Dictionary) -> Array:
	if along == Vector3.ZERO:
		return [false, delta]
	var kept_normal: Vector3 = hit["normal"]
	var kept_time: float = hit["time"]
	var kept_collider = hit["collider"]
	if -kept_normal.dot(safe_normal(delta)) < 0.707:
		return [false, delta]
	var start: Vector3 = pawn.global_position
	var handled: bool = false
	var back: Vector3 = -along * CORNER_SLIP_REACH
	var side: Dictionary = move_actor(along * CORNER_SLIP_REACH)
	var side_time: float = side["time"]
	if side_time < 1.0 and side_time >= 0.0:
		back *= side_time
	elif not (probe_ahead and float(sweep(safe_normal_2d(delta) * CORNER_SLIP_PROBE)["time"]) < 1.0):
		var drop := Vector3(0.0, -pawn.config.pawn.max_step_down_height, 0.0)
		delta *= 1.0 - kept_time
		var last: Dictionary = move_actor(delta)
		var forward_time: float = last["time"]
		var down_time: float = 0.0
		var blocked_again: bool = false
		if forward_time <= CORNER_SLIP_BLOCKED and step_down_too:
			last = move_actor(drop)
			down_time = last["time"]
			if down_time > CORNER_SLIP_BLOCKED:
				last = move_actor(delta)
				forward_time = last["time"]
				blocked_again = forward_time <= CORNER_SLIP_BLOCKED
		handled = forward_time >= 1.0
		kept_normal = last["normal"]
		kept_time = last["time"]
		kept_collider = last["collider"]
		if blocked_again:
			move_actor(-drop * down_time)
	var final: Dictionary = move_actor(back)
	var moved: Vector3 = pawn.global_position - start
	_just_teleported = Vector2(delta.x, delta.z).length_squared() < Vector2(moved.x, moved.z).length_squared()
	if _just_teleported:
		pawn.evade_timer = 0.2
	hit["normal"] = kept_normal
	hit["time"] = kept_time
	hit["collider"] = kept_collider
	hit["position"] = final["position"]
	return [handled, delta]

## The current move's bUseCustomCollision, the corner slip's step-down switch.
## False for every move ported so far; read off the move when it declares one.
func _uses_custom_collision() -> bool:
	var move = pawn.move_manager.current_move()
	return move != null and move.get(&"use_custom_collision") == true

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
## Not ported: root motion, water and the landing edge check (2c, whose
## EdgeCheck is only partly read) -- every floor hit lands.
func phys_falling(dt: float, iterations: int) -> void:
	var p: PawnConfig = pawn.config.pawn
	var old_accel: Vector3 = pawn.acceleration
	var a: Vector3 = falling_accel_bound(pawn.velocity, pawn.acceleration, dt, p.accel_rate,
		p.air_control, p.ground_speed)
	var remaining: float = dt
	if dt > 0.0:
		while iterations < MAX_ITERATIONS:
			iterations += 1
			var tick: float = minf(MAX_SUB_STEP, remaining * 0.5) if remaining > MAX_SUB_STEP else remaining
			remaining -= tick
			var old_location: Vector3 = pawn.global_position
			var old_velocity: Vector3 = pawn.velocity
			_just_teleported = false
			_recovered = false
			pawn.velocity = old_velocity + (a + Vector3(0.0, pawn.gravity_z(), 0.0)) * tick
			var adjusted: Vector3 = pawn.velocity * tick
			var hit: Dictionary = move_actor(adjusted)
			if float(hit["time"]) < 1.0:
				var normal: Vector3 = hit["normal"]
				if normal.y < p.walkable_floor_z:
					# A wall or a ceiling.
					_process_hit_wall(hit)
					if pawn.physics != Move.PHYS_FALLING:
						return
					if normal.y <= -p.walkable_floor_z and pawn.velocity.y > 0.0:
						# Everything below reads the nudge's own last hit, as the
						# original's one FCheckResult does.
						var nudged: Dictionary = _ceiling_corner_nudge()
						if not nudged.is_empty():
							hit = nudged
							normal = hit["normal"]
					# TdPawn's ComputeSlideVector tests the surface for the uncontrolled
					# slide first. [ME:CONFIRMED decompile N2 §2b]
					_check_uncontrolled_slide(hit)
					var slide: Vector3 = compute_slide_vector(adjusted, normal, float(hit["time"]))
					if slide.dot(adjusted) >= 0.0:
						var target: Vector3 = pawn.global_position + slide
						var hit2: Dictionary = move_actor(slide)
						var stepped: bool = false
						var resolved: bool = false
						if safe_normal(slide).y < p.walkable_floor_z - 1.0:
							if float(hit2["time"]) >= 1.0:
								resolved = true
							else:
								hit2 = move_actor(target + Vector3(0.0, 1.9 * UU, 0.0) - pawn.global_position)
								stepped = true
						if not resolved:
							if float(hit2["time"]) < 1.0:
								var normal2: Vector3 = hit2["normal"]
								if normal2.y < p.walkable_floor_z:
									_process_hit_wall(hit2)
									if pawn.physics != Move.PHYS_FALLING:
										return
									var twin: Vector3 = two_wall_adjust(safe_normal(adjusted), slide,
										normal2, normal, float(hit2["time"]))
									var ditch: bool = normal.y > 0.0 and normal2.y > 0.0 \
										and twin.y == 0.0 and normal.dot(normal2) < 0.0
									var hit3: Dictionary = move_actor(twin)
									var normal3: Vector3 = hit3["normal"]
									if ditch or (float(hit3["time"]) < 1.0 and normal3.y >= p.walkable_floor_z):
										process_landed(normal3 if float(hit3["time"]) < 1.0 else normal2,
											0.0, iterations)
										return
								else:
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
					remaining += (1.0 - float(hit["time"])) * tick
					if not _just_teleported and float(hit["time"]) > LANDING_REBUILD_TIME \
							and float(hit["time"]) * tick > LANDING_REBUILD_SECONDS:
						pawn.velocity = (pawn.global_position - old_location) / (tick * float(hit["time"]))
					_check_uncontrolled_slide(hit)
					process_landed(normal, remaining, iterations)
					return
			# The velocity rebuilt from the displacement: V = 2 dLoc/dt - V0, which
			# doubles every acceleration integrated above, gravity included.
			if not _just_teleported and not _recovered and pawn.physics != Move.PHYS_NONE:
				pawn.velocity = (pawn.global_position - old_location) / tick
				if pawn.velocity.y < old_velocity.y or old_velocity.y >= 0.0:
					pawn.velocity = pawn.velocity * 2.0 - old_velocity
				if pawn.velocity.length_squared() > p.terminal_velocity * p.terminal_velocity:
					pawn.velocity = safe_normal(pawn.velocity) * p.terminal_velocity
			if remaining <= 0.0:
				break
	pawn.acceleration = old_accel
	pawn.set_grounded(false)

## The ceiling-corner nudge in ATdPlayerPawn::physFalling (0x012c0980), with
## its probe 0x012b74e0. [ME:CONFIRMED decompile N2 §2a] Rising into a ceiling,
## four level lines run from the top of the head out to the corners at
## +-(R + 1) uu; none hitting, the four again 4 uu higher. Each line that ends
## inside a face that is not walkable (|n.y| < WalkableFloorZ) asks for the
## horizontal push that takes its corner back out along the face's normal;
## per axis the largest push wins, and a push of the other sign is ignored.
## A push within R + 1 is lengthened by min(5, R + 1 - |push|) and made: if
## nothing stopped it the body counts as teleported, otherwise it is undone by
## the fraction it got. Returns the hit of the last move, or {} when nothing
## was moved. The probes and the box are square to the world axes, UE's X and
## Y as Godot's x and z.
func _ceiling_corner_nudge() -> Dictionary:
	var reach: float = pawn.collision_radius() + 1.0 * UU
	var start: Vector3 = pawn.collision_center() + Vector3.UP * (pawn.collision_half_height() + 1.0 * UU)
	var corners: Array[float] = [-reach, reach]
	var push := Vector3.ZERO
	var hits := 0
	for level in 2:
		if hits != 0:
			break
		for k in 4:
			var corner := Vector3(corners[k & 1], 0.0, corners[k >> 1])
			var probed: Array = _ceiling_corner_probe(start, corner, push)
			hits += int(probed[0])
			push = probed[1]
		start.y += 4.0 * UU
	if hits == 0 or push.length_squared() > reach * reach:
		return {}
	var length: float = push.length()
	if length > 0.0:
		push += push * (minf(5.0 * UU, reach - length) / length)
	var nudge: Dictionary = move_actor(push)
	var time: float = nudge["time"]
	if time >= 1.0 or time < 0.0:
		_just_teleported = true
		return nudge
	return move_actor(-push * time)

## 0x012b74e0: one corner line of the nudge. Returns [counted, push]: counted
## is 1 when the line ended inside a non-walkable face, and push is the running
## push with this corner's merged in.
func _ceiling_corner_probe(start: Vector3, corner: Vector3, push: Vector3) -> Array:
	var end: Vector3 = start + corner
	var hit: Dictionary = line_trace(start, end)
	if hit.is_empty():
		return [0, push]
	var time: float = hit["time"]
	var normal: Vector3 = hit["normal"]
	if time >= 1.0 or time <= 0.0 or absf(normal.y) >= pawn.config.pawn.walkable_floor_z:
		return [0, push]
	var n: Vector3 = safe_normal_2d(normal)
	var hit_position: Vector3 = hit["position"]
	var wanted: Vector3 = n * n.dot(hit_position - end)
	return [1, Vector3(_merge_push(push.x, wanted.x), 0.0, _merge_push(push.z, wanted.z))]

## One axis of the nudge's push: a push already made in the other direction
## keeps it; otherwise the larger of the two.
static func _merge_push(current: float, wanted: float) -> float:
	if current != 0.0 and signf(current) != signf(wanted):
		return current
	return wanted if absf(current) < absf(wanted) else current

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

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

## Pawn.bForceFloorCheck: the next walking floor test traces, whatever it
## could reuse. Raised when the base stops colliding, cleared by the trace.
var _force_floor_check: bool = false
## Actor.RelativeLocation while based: where the body stands from its base,
## as the last MoveActor or SetBase left it. A body put somewhere by anything
## else (a respawn, a teleport) no longer matches it, and the standing-still
## floor reuse traces instead.
var _relative_location := Vector3.ZERO

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
##
## `fluid` is bFluid: the flying physics passes it, and it scales the whole
## velocity by (1 - dt * Friction) after the drag, precise location or not.
static func calc_velocity(velocity: Vector3, acceleration: Vector3, accel_dir: Vector3,
		dt: float, max_speed: float, friction: float, brake: bool, mobility: float,
		accel_rate: float, braking_friction_strength: float, wall_physics: bool,
		precise_location: bool, force_max_accel: bool, facing: Vector3,
		fluid: bool = false) -> Array:
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
	if fluid:
		v = v * (1.0 - dt * friction)
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
		_note_relative_location()
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
	_note_recovery(before, delta * time)
	_note_relative_location()
	if collision == null:
		return _miss()
	var collider: Object = collision.get_collider()
	# UWorld::MoveActor's bump: a blocking hit on anything but the level's own
	# geometry, or the base the pawn stands on, is NotifyBump -- TdPawn.Bump,
	# handed to the current move. HitWall, from the physics, comes as well.
	if collider != null and not _is_world_geometry(collider) and collider != pawn.base:
		var move = pawn.move_manager.current_move()
		if move != null:
			move.bump(collision.get_normal(), collider)
	return {"time": time, "normal": collision.get_normal(),
		"collider": collider, "position": collision.get_position()}

## Godot's move_and_collide() first pushes a body out of anything it overlaps
## or sits within its safe margin of; UE3's MoveActor never moves a body it did
## not ask to. A push like that is not the body's own motion, and the velocity
## rebuilt from displacement (both physics modes do it) must not read it as
## such. A small one -- a body resting inside the margin, as a straight-down
## landing leaves it while the still walk reuses its floor -- is undone, so the
## body ends exactly where MoveActor would put it; left in, the next take-off
## gains its depenetration twice over in the falling rebuild. A large one (a
## body spawned inside a floor, which would otherwise leave at tens of metres a
## second) is kept and treated like the original's bJustTeleported: the step
## that saw it keeps its velocity.
const RECOVERY_TOLERANCE := 0.5 * UU
var _recovered: bool = false
## Set with a large push and kept until the start of the next walk: the world
## has just changed around the body (a floor moved through it, say), so that
## walk traces for its floor rather than reusing the one it had. By then the
## physics server has geometry moved this frame where its node is.
var _pushed_out: bool = false

func _note_recovery(before: Vector3, asked: Vector3) -> void:
	var pushed: Vector3 = pawn.global_position - before - asked
	if pushed.length() > RECOVERY_TOLERANCE:
		_recovered = true
		_pushed_out = true
	elif pushed != Vector3.ZERO:
		pawn.global_position = before + asked

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

## How much smaller than asked the box an extent trace sweeps is, per side.
## See box_trace().
const TRACE_SKIN := 0.05 * UU

## An extent trace from `start` to `end` with a box of half-size `extent`, the
## shape TdMove's traces sweep. {time, position, normal, collider}; time 1 and
## no collider when nothing is hit; time 0 when the box starts inside
## something. `position` is the box centre where it stops.
##
## UE3's semantics, not Jolt's. DO NOT hand Jolt the box as asked: its
## cast_motion IGNORES EVERY BODY the box starts touching or overlapping, even
## 20 cm deep, and a level mesh is one body. A hang puts the box flush on the
## wall, so every trace from it -- the heave checks, the transfer's fit, the
## shimmy -- saw nothing of the whole level and the pull-up went up through a
## ceiling. So the box swept is TRACE_SKIN smaller on every side, which a
## touching start no longer touches; a start that overlaps even that is
## inside, a hit at time 0 as UE3 reports it; and a hit's time is taken back
## by the distance the skin delayed it. Sharp (margin 0) for the same reason
## the pawn's box is.
func box_trace(end: Vector3, start: Vector3, extent: Vector3) -> Dictionary:
	if extent == Vector3.ZERO:
		var line: Dictionary = line_trace(start, end)
		if line.is_empty():
			return {"time": 1.0, "position": end, "normal": Vector3.ZERO, "collider": null}
		return line
	var space: PhysicsDirectSpaceState3D = pawn.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.margin = 0.0
	var skin: Vector3 = (extent * 0.5).min(Vector3.ONE * TRACE_SKIN)
	box.size = (extent - skin) * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, start)
	query.exclude = [pawn.get_rid()]
	var inside: Dictionary = space.get_rest_info(query)
	if not inside.is_empty():
		return {"time": 0.0, "position": start, "normal": inside["normal"],
			"collider": instance_from_id(inside["collider_id"])}
	var motion: Vector3 = end - start
	var length: float = motion.length()
	if length == 0.0:
		return {"time": 1.0, "position": end, "normal": Vector3.ZERO, "collider": null}
	query.motion = motion
	var fractions: PackedFloat32Array = space.cast_motion(query)
	if fractions.size() < 2:
		return {"time": 1.0, "position": end, "normal": Vector3.ZERO, "collider": null}
	var safe: float = fractions[0]
	var unsafe: float = fractions[1]
	if safe >= 1.0 and unsafe >= 1.0:
		return {"time": 1.0, "position": end, "normal": Vector3.ZERO, "collider": null}
	query.transform = Transform3D(Basis.IDENTITY, start + motion * unsafe)
	query.motion = Vector3.ZERO
	var rest: Dictionary = space.get_rest_info(query)
	var normal: Vector3 = rest.get("normal", Vector3.ZERO)
	var collider: Object = instance_from_id(rest["collider_id"]) if rest.has("collider_id") else null
	# The full box met the face the skin's width earlier along the way.
	var closing: float = absf(normal.dot(motion / length))
	var early: float = normal.abs().dot(skin) / closing if closing > 1e-3 else 0.0
	var time: float = maxf(safe * length - early, 0.0) / length
	return {"time": time, "position": start + motion * time, "normal": normal, "collider": collider}

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
		Move.PHYS_WALL_RUNNING:
			phys_wall_running(dt, iterations)
		Move.PHYS_WALL_CLIMBING:
			phys_wall_climbing(dt, iterations)

## ATdPawn::setPhysics. [ME:CONFIRMED decompile N2 §4] Entering Falling stamps
## EnterFallingHeight with the body's centre height. Any physics but walking
## clears the SlideOffLedge timer; leaving the wall modes ends the wall contact
## (bIsWallWalking).
func set_physics(mode: int) -> void:
	if mode == pawn.physics:
		return
	if mode == Move.PHYS_FALLING:
		pawn.enter_falling_height = pawn.collision_center().y
	if mode != Move.PHYS_WALKING:
		pawn.base = null
		pawn.clear_slide_off_ledge()
	if pawn.physics == Move.PHYS_WALL_RUNNING or pawn.physics == Move.PHYS_WALL_CLIMBING:
		pawn.is_wall_walking = false
	pawn.physics = mode

## ATdPawn::physWalking. [ME:CONFIRMED decompile N1 §2]
func phys_walking(dt: float, iterations: int) -> void:
	var p: PawnConfig = pawn.config.pawn
	# Read before the base carry below re-measures it: anything but the
	# physics that moved the body, or a base that moved, fails it.
	var undisturbed: bool = _relative_location_holds()
	if _pushed_out:
		_force_floor_check = true
		_pushed_out = false
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

		if pawn.base != null and not _base_collides(pawn.base):
			_force_floor_check = true
		var floor_dist: float
		if floor_from_step != null:
			hit = {"time": 0.1, "normal": floor_normal_from_step, "collider": floor_from_step,
				"position": pawn.global_position}
			floor_dist = MAX_FLOOR_DIST
		elif zero_move and _is_world_geometry(pawn.base) and undisturbed \
				and _relative_location_holds() and not _force_floor_check:
			# [ME:CONFIRMED decompile N1 §2.1] Standing still on world
			# geometry: the floor is the one already under the feet, no trace
			# is made, and the body is not lifted to its hover.
			hit = {"time": 0.1, "normal": pawn.floor_normal, "collider": pawn.base,
				"position": pawn.global_position}
			floor_dist = MAX_FLOOR_DIST
		else:
			_force_floor_check = false
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

## How far the feet are above the floor right now, for this project's own
## probes. Usually FLOOR_DIST, but a body standing still reuses its floor
## (phys_walking) and keeps whatever gap its landing left. Measured with a
## short sweep and kept until the body moves.
func floor_gap() -> float:
	if pawn.global_position != _gap_measured_at:
		_gap_measured_at = pawn.global_position
		var reach: float = MAX_FLOOR_DIST * 2.0
		var below: Dictionary = sweep(Vector3.DOWN * reach)
		_gap = minf(reach * float(below["time"]) + pawn.safe_margin, FLOOR_DIST) \
			if float(below["time"]) < 1.0 else FLOOR_DIST
	return _gap

var _gap := FLOOR_DIST
var _gap_measured_at := Vector3.INF

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
	if absf(d.dot(pawn.facing())) <= VERTIGO_EFFECT_THRESHOLD:
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
	var d: Vector3 = pawn.facing() if flat_sq <= 0.0 else safe_normal_2d(current_delta)
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
func _uses_custom_collision() -> bool:
	var move: Move = pawn.move_manager.current_move()
	return move != null and move.use_custom_collision

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
## Actor.SetBase for a move (the wall moves' SetBase(MovementActor, ...)).
## The floor normal is the move's to set.
func set_base(collider: Object) -> void:
	_set_base(collider)

func _set_base(collider: Object) -> void:
	pawn.base = collider
	if collider is Node3D:
		pawn.base_transform = (collider as Node3D).global_transform
	_note_relative_location()

## What MoveActor and SetBase do to RelativeLocation: re-measured from the base.
func _note_relative_location() -> void:
	var base = pawn.base
	if base != null and is_instance_valid(base) and base is Node3D:
		_relative_location = pawn.global_position - (base as Node3D).global_position

## RelativeLocation == Location - Base.Location: nothing but the physics has
## moved the body since it was last measured.
func _relative_location_holds() -> bool:
	var base = pawn.base
	return base != null and is_instance_valid(base) and base is Node3D \
		and pawn.global_position - (base as Node3D).global_position == _relative_location

## Base.bWorldGeometry: the level's own static collision, not a mover or a
## body.
static func _is_world_geometry(base) -> bool:
	if base == null or not is_instance_valid(base):
		return false
	return (base is StaticBody3D and not (base is AnimatableBody3D)) or base is CSGShape3D

## Base.bCollideActors: false once the base has stopped colliding -- freed,
## out of the tree, on no layer, or with every shape disabled (a pane that
## broke under the feet).
static func _base_collides(base) -> bool:
	if not is_instance_valid(base):
		return false
	if base is Node and not (base as Node).is_inside_tree():
		return false
	if base is CSGShape3D:
		return (base as CSGShape3D).use_collision
	if base is CollisionObject3D:
		var body := base as CollisionObject3D
		if body.collision_layer == 0:
			return false
		for owner_id in body.get_shape_owners():
			if not body.is_shape_owner_disabled(owner_id):
				return true
		return false
	return true

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
## Not ported: water. Root motion is taken as the move hands it over
## (Player.root_motion_velocity), not read off a mesh.
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
			_just_teleported = false
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
						if normal.y <= -pawn.walkable_floor_z and pawn.velocity.y > 0.0:
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
							if not _just_teleported and float(hit["time"]) > LANDING_REBUILD_TIME \
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
			if not root_motion and not _just_teleported and not _recovered \
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
	if time >= 1.0 or time <= 0.0 or absf(normal.y) >= pawn.walkable_floor_z:
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
## "Excluded for hand and foot moves" is MoveTraces' reading of the hit's
## bits. [ME:INFERRED] the original reads two actor bits and two component bits.
func _landing_edge_retry(adjusted: Vector3, hit: Dictionary) -> bool:
	var manager = pawn.move_manager
	if manager.current_name == Move.FALL_UNCONTROLLED:
		return false
	if adjusted.y == 0.0:
		return false
	var fall: float = pawn.enter_falling_height - pawn.collision_center().y
	var hard: bool = pawn.config.pawn.hard_landing_height < fall \
		or (MoveTraces.excludes_hand_moves(hit["collider"]) and MoveTraces.excludes_foot_moves(hit["collider"])) \
		or manager.current_name == Move.TURN_180_IN_AIR
	if hard:
		if not check_valid_floor(adjusted, hit["normal"], true):
			pawn.arm_slide_off_ledge(true)
			_just_teleported = true
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
## nothing, and SetPostLandedPhysics' SetBase(HitActor) -- the first walking
## sub-step sets the base from its own floor trace instead.
func process_landed(normal: Vector3, remaining: float, iterations: int) -> void:
	pawn.floor_normal = normal
	# What the presentation reads about this landing (the camera's dip).
	pawn.last_landing_fall_height = pawn.enter_falling_height - pawn.collision_center().y
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

## PhysicsVolume.FluidFriction of the default volume. [ME:CONFIRMED decompile
## N5 §0.1] physFlying passes half of it to CalcVelocity: 0.15.
const DEFAULT_FLUID_FRICTION := 0.3
## physFlying steps up a blocking face whose normal is within this of
## horizontal, while the travel is within -0.2 .. 0.5 of straight down.
## [ME:CONFIRMED decompile 0x00f00c30]
const FLYING_STEP_NORMAL_Z := 0.2
const FLYING_STEP_UP_DOWN_MAX := 0.5
const FLYING_STEP_UP_DOWN_MIN := -0.2

## APawn::physFlying. [ME:CONFIRMED decompile N5 §0.1, 0x00f00c30] One move,
## no sub-steps: CalcVelocity with bFluid (MaxSpeed AirSpeed, Friction half
## the volume's FluidFriction, no braking), a sweep along Velocity * dt, a
## step-up or a slide along what blocked it, and the velocity rebuilt from the
## displacement. The moves that fly either set Velocity every frame (ZipLine,
## a precise location) or keep it at zero and place the body themselves
## (Swing), so the decay and the AirSpeed clamp act on what they chose.
func phys_flying(dt: float, _iterations: int) -> void:
	var p: PawnConfig = pawn.config.pawn
	var move = pawn.move_manager.current_move()
	var move_cfg: MoveConfig = move.current_config() if move != null else null
	var speed_modifier: float = move_cfg.speed_modifier if move_cfg != null else 1.0
	var accel_dir: Vector3 = Vector3.ZERO if pawn.acceleration == Vector3.ZERO \
		else safe_normal(pawn.acceleration)
	var force: bool = pawn.force_max_accel_one_frame
	pawn.force_max_accel_one_frame = false
	if pawn.root_motion_active:
		# The root-motion branch of CalcVelocity, as the walking physics takes
		# it; flying keeps the vertical too -- the climbs rise on it. [ME:UNKNOWN]
		# APawn::CalcVelocity's root-motion path was not read.
		pawn.velocity = pawn.root_motion_velocity
		pawn.acceleration = Vector3.ZERO
	else:
		var r: Array = calc_velocity(pawn.velocity, pawn.acceleration, accel_dir, dt, p.air_speed,
			DEFAULT_FLUID_FRICTION * 0.5, false, pawn.mobility_multiplier() * speed_modifier,
			p.accel_rate, p.braking_friction_strength, false,
			move != null and move.use_precise_location, force, pawn.facing(), true)
		pawn.velocity = r[0]
		pawn.acceleration = r[1]
	_just_teleported = false
	var old_location: Vector3 = pawn.global_position
	var adjusted: Vector3 = pawn.velocity * dt
	var hit: Dictionary = move_actor(adjusted)
	if float(hit["time"]) < 1.0:
		var normal: Vector3 = hit["normal"]
		var up_down: float = -safe_normal(pawn.velocity).y
		if absf(normal.y) < FLYING_STEP_NORMAL_Z and up_down < FLYING_STEP_UP_DOWN_MAX \
				and up_down > FLYING_STEP_UP_DOWN_MIN:
			# What the step lifts the body by is not travel: the old location
			# is lifted with it before the velocity is rebuilt.
			var before_y: float = pawn.global_position.y
			_step_up(safe_normal(adjusted), adjusted * (1.0 - float(hit["time"])), hit)
			old_location.y += pawn.global_position.y - before_y
		else:
			_process_hit_wall(hit)
			var slide: Vector3 = (adjusted - normal * adjusted.dot(normal)) * (1.0 - float(hit["time"]))
			if slide.dot(adjusted) >= 0.0:
				var hit2: Dictionary = move_actor(slide)
				if float(hit2["time"]) < 1.0:
					_process_hit_wall(hit2)
					slide = two_wall_adjust(safe_normal(adjusted), slide, hit2["normal"], normal,
						float(hit2["time"]))
					move_actor(slide)
	if dt > 0.0 and not _just_teleported and not _recovered:
		pawn.velocity = (pawn.global_position - old_location) / dt
	pawn.set_grounded(false)

# --- the wall modes -------------------------------------------------------------
#
# [ME:CONFIRMED emulated N3 §1, §2.6, §2.7, §3.4] physWallRunning (12) and
# physWallClimbing (13), with their blocked-move responses. Floor holds the
# wall's normal in both. The order of every event against every physics change
# is the original's, and so are the quirks: the loop runs on after a response
# changed the physics, the Floor read back after the stick move is that move's
# own hit (a stick that touches nothing leaves Floor zero and the next frame
# falls), a fall re-simulates the WHOLE frame in the falling physics, and the
# climb ends on V = 2 Vnew - V0, which doubles every velocity change.

## TdPawn.MaxWallStepHeight: how far the wall physics steps over things and
## pushes into the wall. 35 uu.
const MAX_WALL_STEP_HEIGHT := 35.0 * UU
## How far ahead along the velocity the wall run looks for its wall.
const WALL_RUN_PROBE_AHEAD := 35.0 * UU

## The CalcVelocity both wall modes start with: no friction on the vertical,
## a speed bound of GroundSpeed x 4 that never binds, and the move's LIVE
## FrictionModifier as the friction itself.
func _wall_calc_velocity(dt: float) -> void:
	var p: PawnConfig = pawn.config.pawn
	var move = pawn.move_manager.current_move()
	var friction: float = move.live_friction_modifier() if move != null else 1.0
	var speed_modifier: float = move.current_config().speed_modifier \
		if move != null and move.current_config() != null else 1.0
	var accel_dir: Vector3 = safe_normal(pawn.acceleration)
	var r: Array = calc_velocity(pawn.velocity, pawn.acceleration, accel_dir, dt, p.ground_speed * 4.0,
		friction, false, pawn.mobility_multiplier() * speed_modifier, p.accel_rate,
		p.braking_friction_strength, true, false, false, pawn.facing())
	pawn.velocity = r[0]
	pawn.acceleration = r[1]

static func _wall_sub_tick(remaining: float) -> float:
	return minf(remaining * 0.5, MAX_SUB_STEP) if remaining > MAX_SUB_STEP else remaining

static func _normalised(v: Vector3) -> Vector3:
	var sq: float = v.length_squared()
	return v / sqrt(sq) if sq > 1e-8 else v

## ATdPawn::physWallRunning (0x012bba30).
func phys_wall_running(dt: float, iterations: int) -> void:
	var p: PawnConfig = pawn.config.pawn
	var walkable: float = pawn.walkable_floor_z
	var start_yaw: int = UE.dir_yaw(pawn.floor_normal)
	if is_nearly_zero(pawn.floor_normal, 1e-4):
		pawn.falling_off_wall()
		if pawn.physics == Move.PHYS_WALL_RUNNING:
			set_physics(Move.PHYS_FALLING)
		start_new_physics(dt, iterations)
		return
	# A based pawn moves with its base, a wall that moves among them.
	_carry_on_base(dt)
	_wall_calc_velocity(dt)
	iterations += 1
	_just_teleported = false
	_recovered = false
	var vm: Vector3 = pawn.velocity
	var old_location: Vector3 = pawn.global_position
	var remaining: float = dt
	var step := Vector3.UP * MAX_WALL_STEP_HEIGHT
	var stick: float = MAX_WALL_STEP_HEIGHT + STEP_FUDGE
	var move = pawn.move_manager.current_move()
	var r: float = pawn.collision_radius()
	var h: float = pawn.collision_half_height()
	while remaining > 0.0 and iterations < MAX_ITERATIONS:
		iterations += 1
		var tick: float = _wall_sub_tick(remaining)
		remaining -= tick
		var delta: Vector3 = vm * tick
		var hit: Dictionary = move_actor(delta)
		if float(hit["time"]) < 1.0:
			if not pawn.is_wall_walking:
				var n: Vector3 = hit["normal"]
				if n.y > walkable:
					# A slope or a step in the way: up, the rest, down.
					move_actor(step)
					var over: Dictionary = move_actor(delta * (1.0 - float(hit["time"])))
					if (over["normal"] as Vector3).y < walkable and float(over["time"]) < 1.0:
						n = over["normal"]
					hit = move_actor(-step)
				if n.y < walkable:
					move_actor(step)
					var along: Dictionary = move_actor(delta * (1.0 - float(hit["time"])))
					if (along["normal"] as Vector3).y < walkable and float(along["time"]) < 1.0:
						# First contact: the velocity loses its component into
						# the wall, horizontally only.
						var wall: Vector3 = along["normal"]
						var into: float = pawn.velocity.dot(wall)
						pawn.velocity.x -= into * wall.x
						pawn.velocity.z -= into * wall.z
						pawn.is_wall_walking = true
						vm = pawn.velocity
						pawn.reached_wall()
						_just_teleported = true
					move_actor(-step)
			else:
				_wall_run_blocked(delta * (1.0 - float(hit["time"])), hit)
		if pawn.is_wall_walking or (move != null and move.move_active_time > 0.2):
			var floor: Vector3 = pawn.floor_normal
			var probe_start: Vector3 = pawn.global_position + safe_normal_2d(pawn.velocity) * WALL_RUN_PROBE_AHEAD
			var probe_end: Vector3 = probe_start - floor * stick
			var extent := Vector3(r * 0.25, h * 0.25, r * 0.25)
			probe_start.y -= extent.y * 0.75
			probe_end.y -= extent.y * 0.75
			var line: Dictionary = box_trace(probe_end, probe_start, extent)
			var found: bool = float(line["time"]) < 1.0
			if not pawn.is_wall_walking:
				if not found and pawn.physics == Move.PHYS_WALL_RUNNING:
					_wall_run_fall(dt, iterations)
					return
			elif found:
				var bend: Vector3 = line["normal"]
				if floor.dot(bend) < 0.96 and bend.dot(delta) > 0.0:
					_wall_run_fall(dt, iterations)
					return
				var held: Dictionary = move_actor(-floor * stick)
				pawn.floor_normal = held["normal"]
				if held["collider"] != null and held["collider"] != pawn.base:
					_set_base(held["collider"])
			elif pawn.physics == Move.PHYS_WALL_RUNNING:
				_wall_run_fall(dt, iterations)
				return
	if pawn.physics != Move.PHYS_WALL_RUNNING:
		return
	# The pawn turns with a wall that curves.
	var turn: int = UE.normalize_axis(UE.dir_yaw(pawn.floor_normal) - start_yaw)
	pawn.pawn_yaw = UE.godot_yaw(UE.yaw_units(pawn.pawn_yaw) + turn)
	var rebuilt: Vector3 = (pawn.global_position - old_location) / dt
	if rebuilt.length_squared() < pawn.velocity.length_squared() and not _just_teleported \
			and not _recovered and pawn.physics == Move.PHYS_WALL_RUNNING:
		pawn.velocity = rebuilt

## The wall run's way off its wall inside the physics: Falling, the event, and
## the whole frame again in the falling physics.
func _wall_run_fall(dt: float, iterations: int) -> void:
	set_physics(Move.PHYS_FALLING)
	pawn.falling_off_wall()
	start_new_physics(dt, iterations)

## The wall run's blocked move (0x012b3e50): a floor lands, a ceiling ends the
## run, a face square to the wall is stepped round, a corner sharper than
## about 66 degrees ends the run, a gentler inside corner turns the run onto
## the new wall.
func _wall_run_blocked(rest: Vector3, hit: Dictionary) -> void:
	var floor: Vector3 = pawn.floor_normal
	var into: Vector3 = -floor * MAX_WALL_STEP_HEIGHT
	var n: Vector3 = hit["normal"]
	if n.y > 0.707 and pawn.physics == Move.PHYS_WALL_RUNNING:
		process_landed(n, 0.0, MAX_ITERATIONS)
		set_physics(Move.PHYS_WALKING)
		return
	if n.y < -0.707 and pawn.physics == Move.PHYS_WALL_RUNNING:
		_process_hit_wall(hit)
		pawn.falling_off_wall()
		set_physics(Move.PHYS_FALLING)
		return
	if floor.dot(n) < 0.1:
		move_actor(-into)
		hit = move_actor(rest)
	if float(hit["time"]) < 1.0:
		n = hit["normal"]
		if n.dot(floor) < 0.4:
			move_actor(into)
			pawn.falling_off_wall()
			set_physics(Move.PHYS_FALLING)
			return
		# An inside corner: the rest of the move turned into the new wall's
		# frame.
		var old: Vector3 = floor
		pawn.floor_normal = n
		var a: Vector3 = _normalised(UE.cross(n, old))
		var b: Vector3 = _normalised(UE.cross(a, old))
		var out: Vector3 = UE.cross(a, n) * rest.dot(b) + a * rest.dot(a) + n * rest.dot(old)
		if rest.dot(out) >= 0.0:
			_just_teleported = true
			move_actor(out)
	move_actor(into)

## ATdPawn::physWallClimbing (0x012bcc00).
func phys_wall_climbing(dt: float, iterations: int) -> void:
	if is_nearly_zero(pawn.floor_normal, 1e-4) or pawn.velocity.y < 0.0:
		_wall_climb_fall(dt, iterations)
		return
	var v0: Vector3 = pawn.velocity
	# A based pawn moves with its base, a wall that moves among them.
	_carry_on_base(dt)
	_wall_calc_velocity(dt)
	var vm: Vector3 = pawn.velocity
	_just_teleported = false
	_recovered = false
	var old_location: Vector3 = pawn.global_position
	var remaining: float = dt
	var stick: float = MAX_WALL_STEP_HEIGHT + STEP_FUDGE
	while remaining > 0.0 and iterations < MAX_ITERATIONS:
		iterations += 1
		var tick: float = _wall_sub_tick(remaining)
		remaining -= tick
		var delta: Vector3 = vm * tick
		var hit: Dictionary = move_actor(delta)
		if float(hit["time"]) < 1.0:
			var n: Vector3 = hit["normal"]
			if pawn.is_wall_walking:
				_wall_climb_blocked(delta * (1.0 - float(hit["time"])), hit)
			elif absf(n.y) < 0.2:
				# First contact: the velocity projected onto the wall, keeping
				# its vertical.
				var projected: Vector3 = pawn.velocity - n * pawn.velocity.dot(n)
				pawn.velocity.x = projected.x
				pawn.velocity.z = projected.z
				vm = pawn.velocity
				_just_teleported = true
				pawn.is_wall_walking = true
				pawn.reached_wall()
			else:
				_wall_climb_fall(dt, iterations)
				return
		if pawn.is_wall_walking:
			var floor: Vector3 = pawn.floor_normal
			var line: Dictionary = box_trace(pawn.global_position - floor * stick, pawn.global_position,
				pawn.collision_extent())
			if float(line["time"]) >= 1.0:
				_wall_climb_fall(dt, iterations)
				return
			if absf((line["normal"] as Vector3).y) > 0.2:
				move_actor(-floor * stick)
				if pawn.physics == Move.PHYS_WALL_CLIMBING:
					set_physics(Move.PHYS_FALLING)
				pawn.falling_off_wall()
				start_new_physics(dt, iterations)
				return
			var held: Dictionary = move_actor(-floor * stick)
			pawn.floor_normal = held["normal"]
	if _just_teleported or _recovered or pawn.physics != Move.PHYS_WALL_CLIMBING:
		return
	var rebuilt: Vector3 = (pawn.global_position - old_location) / dt
	pawn.velocity = rebuilt
	if v0.y > rebuilt.y or v0.y >= 0.0:
		pawn.velocity = rebuilt * 2.0 - v0

func _wall_climb_fall(dt: float, iterations: int) -> void:
	pawn.falling_off_wall()
	if pawn.physics == Move.PHYS_WALL_CLIMBING:
		set_physics(Move.PHYS_FALLING)
	start_new_physics(dt, iterations)

## The wall climb's blocked move (0x012b4550): something off the wall plane is
## stepped round, away from the wall; if that is blocked too the climb is
## over and the rise is gone. Otherwise the wall turns under the body.
func _wall_climb_blocked(rest: Vector3, hit: Dictionary) -> void:
	var floor: Vector3 = pawn.floor_normal
	var away: Vector3 = floor * MAX_WALL_STEP_HEIGHT
	if floor.dot(hit["normal"]) < 0.95:
		move_actor(away)
		var again: Dictionary = move_actor(rest)
		if float(again["time"]) < 1.0 and floor.dot(again["normal"]) < 0.95:
			move_actor(-rest * (1.0 - float(again["time"])))
			move_actor(-away)
			if pawn.physics == Move.PHYS_WALL_CLIMBING:
				pawn.falling_off_wall()
				set_physics(Move.PHYS_FALLING)
			pawn.velocity.y = 0.0
			return
		hit = again
	if float(hit["time"]) < 1.0 and floor.dot(hit["normal"]) < 0.95:
		pawn.floor_normal = hit["normal"]
		var turned: Vector3 = pawn.floor_normal
		move_actor(rest - turned * turned.dot(rest))

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

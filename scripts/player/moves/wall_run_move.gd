class_name WallRunMove
extends PhysicsMove

# The original's TdMove_WallRun, ported. [ME:CONFIRMED decompile N3 §2;
# FindWallForward, FindWallSide and the per-tick half ME:CONFIRMED emulated]
#
# WallRunningRight, WallRunningLeft and the generic WallRun are ONE object in
# the original (Moves[4] = Moves[5] = Moves[40]): CanDoMove fills NextMove and
# WallNormal for the StartMove that follows, and WallRunJump reads this
# object's ConsequtiveWallruns. Here it is one move, WALL_RUN, and which of
# the two states it is in is `side` (SIDE_RIGHT 4 / SIDE_LEFT 5, the
# original's numbers).
#
# What the run is, in the original's own terms:
#   * entry (CheckAutoMoves of a move with bCheckForWallClimb): FindWallSide
#     right after a jump with a strafe hint, else FindWallForward -- the pawn
#     FACING within 57 degrees of the wall plane, a wall 190 uu tall;
#   * on the wall: the controller gives no acceleration (PlayerWallWalking);
#     every tick the horizontal velocity is snapped onto the wall's tangent,
#     keeping its size, and the vertical takes 820 (rising) or 500 (falling) x
#     (1 + ConsequtiveWallruns) of gravity; the run ends when it falls faster
#     than 500 uu/s, or when the physics loses the wall;
#   * the start: a rising entry is given the vertical speed that tops out
#     170 uu above the take-off, unless it chains from a wall-run jump.
# No horizontal speed floor and no timer: a run lasts as long as its vertical
# arc. A chain gets heavier with every wall (1 + n), and the jump off it
# weaker (WallRunJump divides by 1 + n).

const SIDE_NONE := 0
const SIDE_RIGHT := 4
const SIDE_LEFT := 5

## TdPhysicsMove.ContextMoveDistanceMultiplier. [ME:CONFIRMED ini] 1.8: how far
## FindWallForward's reach stretches between SpeedMaxBaseVelocity and
## GroundSpeed.
const CONTEXT_MOVE_DISTANCE_MULTIPLIER := 1.8

## TdMove_WallRun.NextMove: which side CanDoMove found, for the StartMove that
## follows.
var next_move: int = SIDE_NONE
## The MovementState this run is in: WallRunningRight (4) or Left (5).
var side: int = SIDE_NONE
var wall_normal: Vector3 = Vector3.ZERO
var predicted_wall_hit_location: Vector3 = Vector3.ZERO
var wall_running_begin_speed: float = 0.0
## Counted up by a run that starts out of a wall-run jump, reset by any
## other. Live across moves: WallRunJump reads it.
var consequtive_wallruns: int = 0
var has_reached_wall: bool = false
var start_moving_into_wall: bool = false
var turned_90_from_wall: bool = false
var changed_constraints: bool = false
## The absolute yaw window, rotator units. Widened by 20000 on the side away
## from the wall after 0.3 s, and NOT normalised again when it is.
var min_contraint_world: int = 0
var max_contraint_world: int = 0
## WallRunningHorisontalAcceleration / Deceleration as this run has them:
## the config's times (1 + ConsequtiveWallruns).
var horisontal_acceleration: float = 0.0
var horisontal_deceleration: float = 0.0
## FrictionModifier, rewritten every tick: 0 until the wall is reached, then
## WallRunningHorisontalFriction.
var friction_modifier: float = 1.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_WALL_RUNNING
	controller_state = CS_PLAYER_WALL_WALKING
	disable_controller_facing_pawn_yaw_rotation = true

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func live_friction_modifier() -> float:
	return friction_modifier

func get_min_look_constrain_yaw() -> int:
	return min_contraint_world

func get_max_look_constrain_yaw() -> int:
	return max_contraint_world

func _wall_cfg() -> WallRunConfig:
	return cfg as WallRunConfig

## The state this object is in right now: its side while it is the current
## move, none once something else is. The original reads MovementState, which
## a FallingOffWall in the middle of its own tick has already changed.
func _state_side() -> int:
	return side if player.move_manager.current_move() == self else SIDE_NONE

# --- entry -----------------------------------------------------------------------

## TdMove_WallRun.CanDoMove. Asked by CheckAutoMoves, never by the action
## table.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var c: WallRunConfig = _wall_cfg()
	var v: Vector3 = player.velocity
	if Vector2(v.x, v.z).length_squared() < c.wall_running_min_speed * c.wall_running_min_speed:
		return false
	if v.dot(player.facing()) < 0.0:
		return false
	var wanted: int = SIDE_NONE
	if (player.global_position - player.last_jump_location).length() < 30.0 * UU:
		if player.move_action_hint == MAH_RIGHT:
			wanted = SIDE_RIGHT
		elif player.move_action_hint == MAH_LEFT:
			wanted = SIDE_LEFT
	var hit: Dictionary = {}
	if wanted != SIDE_NONE:
		hit = find_wall_side(wanted)
	if not hit.is_empty():
		next_move = wanted
	else:
		var forward: Array = find_wall_forward()
		next_move = forward[0]
		hit = forward[1]
	if next_move == SIDE_NONE:
		return false
	if hit["feet_excluded"]:
		return false
	var volume: Object = player.traces.get_movement_exclusion_volume(hit["ledge_location"])
	if volume != null and MoveTraces.excludes_foot_moves(volume):
		return false
	var normal: Vector3 = hit["move_normal"]
	if v.dot(normal) >= 0.0:
		return false
	if v.y < 0.0:
		# Falling onto the wall: refused when something is just below the
		# path the run would take.
		var start: Vector3 = (hit["ledge_location"] as Vector3) + normal * player.collision_radius()
		start.y -= player.collision_half_height() * 2.0
		var half: float = Vector2(v.x, v.z).length() * 0.5
		var end: Vector3 = UE.cross(normal, Vector3.DOWN if next_move == SIDE_RIGHT else Vector3.UP) * half
		end.y -= 45.0 * UU
		end += start
		if player.traces.movement_trace_for_blocking(end, start, Vector3(1.0, 1e-4, 1.0) * UU):
			return false
	player.movement_actor = hit["move_actor"]
	player.found_ledge_excludes_foot_moves = hit["feet_excluded"]
	player.found_ledge_excludes_hand_moves = hit["hands_excluded"]
	player.move_normal = normal
	wall_normal = normal
	predicted_wall_hit_location = hit["ledge_location"]
	return true

## The (pitch-free) direction of the projected offset to a wall hit, signed
## toward the facing: the along-wall half of both finders' probe direction.
static func _along_wall(offset: Vector3, normal: Vector3, facing: Vector3) -> Vector3:
	var q: float = -absf(offset.x * normal.x + offset.z * normal.z)
	var p := Vector3(offset.x - q * normal.x, -normal.y * q, offset.z - q * normal.z)
	if p.dot(facing) <= 0.0:
		p = -p
	if p.length_squared() > 1e-8 * UU * UU:
		p = p.normalized()
	return p

func _wall_hit(location: Vector3, wall: Dictionary) -> Dictionary:
	var actor: Object = wall["actor"]
	return {"ledge_location": location, "ledge_normal": wall["normal"], "move_normal": wall["normal"],
		"move_actor": actor, "feet_excluded": MoveTraces.excludes_foot_moves(actor),
		"hands_excluded": MoveTraces.excludes_hand_moves(actor)}

## UTdMove_WallRun::FindWallForward (0x011f67b0). [ME:CONFIRMED emulated N3
## §2.2] Returns [side, hit]: SIDE_NONE and {} when there is no wall to run.
##
## Two thin boxes straight ahead along the pawn's FACING -- one at the waist,
## one up where the wall must still be (190 uu above the feet, less at a
## glancing angle) -- then a body-sized box along a direction between "into
## the wall" and "along it"; the high and the body hits must lie on one flat
## wall. The side is the cross product's sign. While the wall-run jump's ledge
## timer runs, a wall within 11.5 degrees of the one jumped off is refused.
func find_wall_forward() -> Array:
	var c: WallRunConfig = _wall_cfg()
	var p: PawnConfig = config.pawn
	var x: Vector3 = player.facing()
	var l: Vector3 = player.global_position
	var r: float = player.collision_radius()
	var h: float = player.collision_half_height()
	var v: Vector3 = player.velocity
	var speed: float = Vector2(v.x, v.z).length()
	var excess: float = maxf(speed - p.speed_max_base_velocity, 0.0)
	var dist: float = ((CONTEXT_MOVE_DISTANCE_MULTIPLIER - 1.0) * excess \
		/ (p.ground_speed - p.speed_max_base_velocity) + 1.0) * c.wall_running_forward_check_distance
	var ext := Vector3(r, 2.0 * UU, r)
	var t1: Dictionary = player.traces.trace(l + x * dist, l, ext)
	if not t1["hit"]:
		return [SIDE_NONE, {}]
	var n: Vector3 = t1["normal"]
	var d: float = (-n).dot(x)
	if d < cos(PI * 0.5 - c.wall_running_forward_min_start_angle):
		return [SIDE_NONE, {}]
	if d > cos(PI * 0.5 - c.wall_running_forward_max_start_angle):
		return [SIDE_NONE, {}]
	if player.illegal_ledge_timer > 0.0 and player.illegal_ledge_normal.dot(n) > 0.98:
		return [SIDE_NONE, {}]
	var high := Vector3(l.x, l.y - h + (c.wall_running_min_wall_height - 2.0 * UU) - (1.0 - d) * 50.0 * UU, l.z)
	var t2: Dictionary = player.traces.trace(high + x * dist, high, ext)
	if not t2["hit"]:
		return [SIDE_NONE, {}]
	var high_hit: Vector3 = t2["location"]
	n = t2["normal"]
	var w: Vector3 = UE.cross(n, Vector3.UP)
	var s: float = -1.0 if w.dot(x) < 0.0 else 1.0
	if v.dot(w * s) < 0.0:
		return [SIDE_NONE, {}]
	var along: Vector3 = _along_wall(high_hit - l, n, x)
	var vn: Vector3 = PawnPhysics.safe_normal(v)
	var k: float = clampf(c.wall_running_move_to_into_position_degree_threshold / (PI * 0.5), 0.0, 1.0)
	var a: float = maxf(k, (-n).dot(vn))
	var b: float = maxf(k, vn.dot(along))
	var dir: Vector3 = PawnPhysics.safe_normal_2d(-n * speed * a + along * speed * b)
	var inv: float = 1.0 / (-n).dot(dir)
	var step: float = p.max_step_down_height
	var s3 := Vector3(l.x, l.y + step * 0.5, l.z)
	var ext3 := Vector3(r, h - step * 0.5, r)
	var t3: Dictionary = player.traces.trace(s3 + dir * c.wall_running_forward_check_distance * inv, s3, ext3)
	if not t3["hit"]:
		return [SIDE_NONE, {}]
	var body_hit: Vector3 = t3["location"]
	var n3: Vector3 = t3["normal"]
	var q: Vector3 = PawnPhysics.safe_normal_2d(high_hit - body_hit)
	if absf(q.dot(n3)) > 0.05:
		return [SIDE_NONE, {}]
	var ledge: Vector3 = body_hit + _contact_offset(dir, n3, ext3.x)
	var side_value: float = n3.x * x.z - n3.z * x.x
	return [SIDE_RIGHT if side_value > 0.0 else SIDE_LEFT, _wall_hit(ledge, t3)]

## The box-corner reach from a body hit to the wall, along the probe
## direction.
static func _contact_offset(dir: Vector3, normal: Vector3, extent: float) -> Vector3:
	var n2: Vector3 = PawnPhysics.safe_normal_2d(normal)
	var dn: Vector3 = PawnPhysics.safe_normal_2d(dir)
	var reach: float = MoveTraces.box_reach(n2, extent)
	var c: float = absf(dn.dot(n2))
	if c > 0.0:
		reach /= c
	return dn * reach

## UTdMove_WallRun::FindWallSide (0x011f5a10). [ME:CONFIRMED emulated N3 §2.3]
## The hit, or {} when there is no wall on `wanted_side`.
##
## Sideways off the facing: a thin box at wall height, its normal within 60
## degrees of sideways; one near the feet, the two hits stacked within about
## 16 degrees of vertical; a body box along a direction weighted 700 into the
## wall and 300 along it (WallRunningHorisontalAlignSpeed and
## WallRunningVelocityStartLimit, which are nothing else). The flatness test
## compares the body hit with the HIGH hit, not the low one.
##
## While the wall-run jump's ledge timer runs this refuses a wall whose
## normal is OPPOSITE the one jumped off -- the wall across the corridor --
## where FindWallForward refuses the same wall. The sign is the original's;
## DO NOT make the two agree.
func find_wall_side(wanted_side: int) -> Dictionary:
	var c: WallRunConfig = _wall_cfg()
	var p: PawnConfig = config.pawn
	var x: Vector3 = player.facing()
	var l: Vector3 = player.global_position
	var r: float = player.collision_radius()
	var h: float = player.collision_half_height()
	var v: Vector3 = player.velocity
	var sg: float = -1.0 if wanted_side == SIDE_RIGHT else 1.0
	var sideways: Vector3 = UE.cross(x, Vector3.UP) * sg
	var dist: float = c.wall_running_strafe_check_distance
	var ext := Vector3(r, 2.0 * UU, r)
	var high := Vector3(l.x, l.y + (c.wall_running_min_wall_height - 2.0 * UU) - h, l.z)
	var t1: Dictionary = player.traces.trace(high + sideways * dist, high, ext)
	if not t1["hit"]:
		return {}
	var high_hit: Vector3 = t1["location"]
	var n: Vector3 = t1["normal"]
	if absf((-n).dot(sideways)) < cos(c.wall_running_strafe_start_angle):
		return {}
	if player.illegal_ledge_timer > 0.0 and player.illegal_ledge_normal.dot(n) < -0.98:
		return {}
	var w: Vector3 = UE.cross(n, Vector3.UP) * sg
	if v.dot(w) < 0.0:
		return {}
	var low := Vector3(l.x, l.y + p.max_step_down_height + 2.0 * UU - h, l.z)
	var t2: Dictionary = player.traces.trace(low + sideways * dist, low, ext)
	if not t2["hit"]:
		return {}
	var low_hit: Vector3 = t2["location"]
	n = t2["normal"]
	var up: Vector3 = high_hit - low_hit
	var sq: float = up.length_squared()
	if sq != 1.0:
		if sq < 1e-8 * UU * UU:
			return {}
		up /= sqrt(sq)
	if up.y < 0.96:
		return {}
	var along: Vector3 = _along_wall(low_hit - l, n, x)
	var dir: Vector3 = PawnPhysics.safe_normal_2d(-n * c.wall_running_horisontal_align_speed \
		+ along * c.wall_running_velocity_start_limit)
	var inv: float = 1.0 / (-n).dot(dir)
	var step: float = p.max_step_down_height
	var s3 := Vector3(l.x, l.y + step * 0.5, l.z)
	var ext3 := Vector3(r, h - step * 0.5, r)
	var t3: Dictionary = player.traces.trace(s3 + dir * dist * inv, s3, ext3)
	if not t3["hit"]:
		return {}
	var body_hit: Vector3 = t3["location"]
	var n3: Vector3 = t3["normal"]
	var q: Vector3 = PawnPhysics.safe_normal_2d(body_hit - high_hit)
	if absf(q.dot(n3)) >= 0.1:
		return {}
	return _wall_hit(body_hit + _contact_offset(dir, n3, ext3.x), t3)

# --- on the wall -------------------------------------------------------------------

## TdMove_WallRun.StartMove.
func enter(_previous: StringName) -> void:
	var c: WallRunConfig = _wall_cfg()
	has_reached_wall = false
	start_moving_into_wall = true
	changed_constraints = false
	turned_90_from_wall = false
	side = next_move
	player.wall_side = 1 if side == SIDE_RIGHT else -1
	var v: Vector3 = player.velocity
	wall_running_begin_speed = Vector2(v.x, v.z).length()
	if v.y > 0.0:
		wall_running_begin_speed = maxf(wall_running_begin_speed, c.wall_running_velocity_start_limit)
	if player.old_movement_state == WALLRUN_JUMP:
		consequtive_wallruns += 1
	else:
		consequtive_wallruns = 0
	horisontal_deceleration = c.wall_running_horisontal_deceleration * (1 + consequtive_wallruns)
	horisontal_acceleration = c.wall_running_horisontal_acceleration * (1 + consequtive_wallruns)
	player.set_physics(PHYS_WALL_RUNNING)
	has_reached_wall = false
	start_moving_into_wall = false
	# The apex: up to 170 uu of headroom over the take-off point, truncated to
	# whole uu, reached at the wall's rising gravity. Not for a chained run.
	var l: Vector3 = player.global_position
	var up: Dictionary = player.traces.movement_trace(l + Vector3.UP * c.wall_running_horisontal_initial_z_height,
		l, player.collision_extent())
	var height: float = (up["location"] as Vector3).y - l.y if up["hit"] \
		else c.wall_running_horisontal_initial_z_height
	height -= l.y - player.last_jump_location.y
	height = maxi(int(height / UU), 0) * UU
	var speed: float = sqrt(2.0 * height * horisontal_acceleration)
	if player.velocity.y > 0.0 and player.old_movement_state != WALLRUN_JUMP:
		player.velocity.y = speed
	# SetBase(MovementActor, WallNormal): Floor is the wall's normal.
	player.floor_normal = wall_normal
	set_timer(c.wall_running_delay_pawn_rotation_time)
	var yaw: int = UE.dir_yaw(wall_normal)
	if side == SIDE_RIGHT:
		min_contraint_world = UE.normalize_axis(yaw)
		max_contraint_world = UE.normalize_axis(yaw + 16384)
	elif side == SIDE_LEFT:
		min_contraint_world = UE.normalize_axis(yaw - 16384)
		max_contraint_world = UE.normalize_axis(yaw)

## OnTimer -> FacePawnAlongWall: the pawn turns to face along the wall,
## a quarter turn off its normal, over WallRunningRotatePawnAlongWallTime.
func on_timer() -> void:
	var yaw: int = UE.dir_yaw(wall_normal) + (16384 if _state_side() == SIDE_RIGHT else -16384)
	player.move_normal = wall_normal
	set_precise_rotation(UE.normalize_axis(yaw), _wall_cfg().wall_running_rotate_pawn_along_wall_time)

## TdMove_WallRun.ReachedWall, fired by the physics on first contact: the
## horizontal speed set back to the speed the run began with, along whatever
## direction the contact left it.
func reached_wall() -> void:
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	flat = flat.normalized() * wall_running_begin_speed if flat.length_squared() > 0.0 else Vector3.ZERO
	player.velocity.x = flat.x
	player.velocity.z = flat.z
	has_reached_wall = true
	# Never cleared again on this object, as in the original.
	disable_face_rotation = true

## The wall run's per-tick native (vt 0x118, 0x012073c0). [ME:CONFIRMED
## emulated N3 §2.5] Runs before the physics, after the base's precise
## rotation.
func pre_physics(delta: float) -> void:
	var c: WallRunConfig = _wall_cfg()
	friction_modifier = 0.0
	super.pre_physics(delta)
	if player.physics == PHYS_FALLING:
		player.move_manager.set_move(FALLING)
		return
	if player.velocity.length() < 0.1 * UU:
		player.falling_off_wall()
		if player.physics == PHYS_WALL_RUNNING:
			player.set_physics(PHYS_FALLING)
	if not changed_constraints and move_active_time > 0.3:
		var yaw: int = UE.dir_yaw(wall_normal)
		var state: int = _state_side()
		if state == SIDE_RIGHT:
			max_contraint_world = yaw + 20000
		elif state == SIDE_LEFT:
			min_contraint_world = yaw - 20000
		changed_constraints = true
	if has_reached_wall:
		var along: Vector3 = PawnPhysics.safe_normal_2d(UE.cross(player.floor_normal, Vector3.UP))
		var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		var sign: float = 1.0 if _state_side() == SIDE_LEFT else -1.0
		player.velocity.x = sign * along.x * speed
		player.velocity.z = sign * along.z * speed
		friction_modifier = c.wall_running_horisontal_friction
	if not start_moving_into_wall:
		if player.velocity.y >= c.wall_running_velocity_stop_limit:
			var gravity: float = horisontal_deceleration if player.velocity.y <= 0.0 else horisontal_acceleration
			player.acceleration = Vector3(0.0, -gravity, 0.0)
		else:
			player.falling_off_wall()
			if player.physics == PHYS_WALL_RUNNING:
				player.set_physics(PHYS_FALLING)

## TdMove_WallRun.HandleMoveAction(MA_Turn): the view swung to face straight
## off the wall in 0.15 s (held for 1.5 s), the pitch kept. The body stays on
## the wall.
func handle_move_action(action: int) -> void:
	if action != MA_TURN:
		return
	set_look_at_target_angle(player.controller_pitch_units(), UE.dir_yaw(player.floor_normal), 0.15, 1.5)
	turned_90_from_wall = true

## TdMove_WallRun.StopMove: unless the view was turned off the wall, the pawn
## eases back to the view over 0.3 s.
func exit() -> void:
	next_move = SIDE_NONE
	if not turned_90_from_wall:
		player.face_rotation_time_left = 0.3
	player.wall_side = 0

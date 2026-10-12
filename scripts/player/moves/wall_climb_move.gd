class_name WallClimbMove
extends PhysicsMove

# The original's TdMove_WallClimb, ported. [ME:CONFIRMED decompile N3 §3; the
# native gate, the per-tick half and CheckDoubleJump ME:CONFIRMED emulated]
#
# Entered only from CheckAutoMoves, after the hand-plant search found a wall
# (or a ledge) ahead: the native gate wants the Up hint (forward held past
# 0.8), the body rising and within 120 uu of the plant, and the CAMERA within
# 33 degrees of straight into the wall. Not RedoMoveTime -- the script's
# CanDoMove is never asked.
#
# The climb: the world's gravity until the wall is touched; then a launch of
# sqrt(4 h g) for AddOnHeight h (approach speed and vertical speed buy it)
# against WallClimbingGravity, the velocity kept on the wall plane and the
# horizontal braked by 6 /s. The physics doubles every velocity change
# (V = 2 Vnew - V0), so the climb rises exactly h and ends when the rise
# stops. With a ledge found up the wall, a second kick (CheckDoubleJump)
# carries the hands to it once the rise has slowed below 100 uu/s.

var has_reached_wall: bool = false
var found_possible_hand_plant_flag: bool = false
var performed_double_jump: bool = false
var possible_edge_destination: Vector3 = Vector3.ZERO
## The approach speed the climb was bought with: |V.xy| - JumpAddXY.
var into_wall_climb_speed: float = 0.0
## The take-off's feet height: the double jump reaches no more than 480 uu
## above it.
var ground_z_loc: float = 0.0
## WallClimbingGravity as this climb has it: the world's until ReachedWall.
var wall_climbing_gravity: float = 0.0
## FrictionModifier, rewritten every tick: 0 until the wall is reached, then
## WallClimbingVerticalFriction.
var friction_modifier: float = 1.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_WALL_CLIMBING
	controller_state = CS_PLAYER_WALL_WALKING
	check_for_edge_in_vel_dir = true

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func live_friction_modifier() -> float:
	return friction_modifier

func _climb_cfg() -> WallClimbConfig:
	return cfg as WallClimbConfig

## The climb's rise for an approach at `into_speed` (|V.xy| - JumpAddXY) and a
## vertical speed `vz` at contact: AddOnHeight, ReachedWall's formula. The
## approach term is truncated to whole uu first, as the original's int is.
static func add_on_height(into_speed: float, vz: float, c: WallClimbConfig, p: PawnConfig) -> float:
	var over: float = maxi(int((into_speed - p.speed_max_base_velocity) / UU), 0) * UU
	var by_speed: float = clampf(over / (c.add_on_speed_2d_max_limit - p.speed_max_base_velocity), 0.0, 1.0)
	var by_rise: float = clampf(vz / c.add_on_speed_z_max_limit, 0.0, 1.0)
	return c.add_on_speed_2d_height * by_speed + c.add_on_speed_z_height * by_rise

## UTdMove_WallClimb's native gate (vt 0x128, 0x011f5000). [ME:CONFIRMED
## emulated N3 §3.1] A level's block on the move is this project's addition.
func can_do_move_native() -> bool:
	var c: WallClimbConfig = _climb_cfg()
	if player.statuses != null and player.statuses.is_move_blocked(WALL_CLIMB):
		return false
	if player.move_action_hint != MAH_UP:
		return false
	var l: Vector3 = player.global_position
	var ledge: Vector3 = player.move_ledge_location
	if Vector2(l.x - ledge.x, l.z - ledge.z).length_squared() \
			> c.wall_climbing_max_distance_2d * c.wall_climbing_max_distance_2d:
		return false
	var h: float = player.collision_half_height()
	if player.move_ledge_result == MoveTraces.LEDGE_TOP:
		if (ledge.y - l.y) + h < c.min_wall_height:
			return false
		# A wall in front of the head: the top is not a ledge at hand height.
		var start := Vector3(l.x, l.y + h - 64.0 * UU, l.z)
		var forward: Vector3 = PawnPhysics.safe_normal_2d(player.facing())
		var reach: float = MoveTraces.box_reach(player.move_normal, player.collision_radius()) + 8.0 * UU
		var head: Dictionary = player.traces.trace(start + forward * reach, start)
		if not head["hit"] or MoveTraces.excludes_foot_moves(head["actor"]):
			return false
	var v: Vector3 = player.velocity
	if Vector2(v.x, v.z).length_squared() < c.wall_climbing_velocity_start_limit * c.wall_climbing_velocity_start_limit:
		return false
	if v.y <= 0.0:
		return false
	var view: Vector3 = Vector3(-sin(player.rotation.y), 0.0, -cos(player.rotation.y))
	if PawnPhysics.safe_normal_2d(v).dot(view) < 0.0:
		return false
	if absf(PawnPhysics.safe_normal_2d(player.move_normal).dot(-view)) < cos(c.wall_climbing_vertical_start_angle):
		return false
	return true

## TdMove.CanDoMove, which the way in never asks.
func can_do_move() -> bool:
	return td_can_do_move()

## TdMove_WallClimb.StartMove.
func enter(_previous: StringName) -> void:
	has_reached_wall = false
	found_possible_hand_plant_flag = false
	performed_double_jump = false
	into_wall_climb_speed = player.horizontal_speed() - config.pawn.jump_add_xy
	wall_climbing_gravity = absf(player.gravity_z())
	# SetBase(MovementActor, MoveNormal): Floor is the wall's normal.
	player.floor_normal = player.move_normal
	if detect_possible_hand_plant():
		found_possible_hand_plant()
	ground_z_loc = player.last_jump_location.y - player.collision_half_height()
	if into_wall_climb_speed < 100.0 * UU:
		# Too slow to have reached the wall: drawn into it.
		var suck: Vector3 = -player.move_normal * 400.0 * UU
		player.velocity.x = suck.x
		player.velocity.z = suck.z

## TdMove_WallClimb.ReachedWall: the launch.
func reached_wall() -> void:
	var c: WallClimbConfig = _climb_cfg()
	var height: float = add_on_height(into_wall_climb_speed, player.velocity.y, c, config.pawn)
	wall_climbing_gravity = c.wall_climbing_gravity
	player.velocity.y = sqrt(maxf(4.0 * height * wall_climbing_gravity, 0.01 * UU * UU))
	has_reached_wall = true

## UTdMove_WallClimb::DetectPossibleHandPlant (vt 0x12c). [ME:CONFIRMED
## decompile N3 §3.3] The hand-plant search again from 215 uu up the wall;
## MoveLedgeResult takes its answer every call.
func detect_possible_hand_plant() -> bool:
	var start: Vector3 = player.move_ledge_location + player.move_normal * player.collision_radius() \
		+ Vector3.UP * 215.0 * UU
	var hit: Dictionary = player.traces.find_auto_move_ledge(start, player.facing(),
		MoveTraces.HAND_PLANT_CHECK_DISTANCE, true, edge_in_vel_dir())
	player.move_ledge_result = hit["result"]
	if hit["result"] == MoveTraces.LEDGE_TOP:
		possible_edge_destination = hit["ledge_location"]
		return true
	return false

## TdMove_WallClimb.FoundPossibleHandPlant.
func found_possible_hand_plant() -> void:
	look_at_ledge(possible_edge_destination)
	found_possible_hand_plant_flag = true

## UTdMove_WallClimb::CheckDoubleJump (vt 0x130). [ME:CONFIRMED emulated N3
## §3.3] Once, with a ledge found within 480 uu of the take-off's feet and the
## rise slowed below MinUpwardsVelocityToDoubleJump: the speed that carries
## the head 4 uu past the ledge.
func check_double_jump() -> void:
	if performed_double_jump or not found_possible_hand_plant_flag:
		return
	if player.velocity.y >= _climb_cfg().min_upwards_velocity_to_double_jump:
		return
	if possible_edge_destination.y - ground_z_loc >= 480.0 * UU:
		return
	var head: float = player.global_position.y + player.collision_half_height()
	var x: float = (possible_edge_destination.y - head + 4.0 * UU) * wall_climbing_gravity * 4.0
	player.velocity.y = sqrt(maxf(x, 0.01 * UU * UU))
	player.acceleration = PawnPhysics.safe_normal(player.velocity)
	performed_double_jump = true

## The wall climb's per-tick native (vt 0x118, 0x012071f0). [ME:CONFIRMED
## emulated N3 §3.3]
func pre_physics(delta: float) -> void:
	friction_modifier = 0.0
	super.pre_physics(delta)
	if player.physics == PHYS_FALLING:
		player.move_manager.set_move(FALLING)
		return
	if not found_possible_hand_plant_flag and detect_possible_hand_plant():
		found_possible_hand_plant()
	check_double_jump()
	if has_reached_wall:
		var floor: Vector3 = player.floor_normal
		player.velocity -= floor * player.velocity.dot(floor)
		friction_modifier = _climb_cfg().wall_climbing_vertical_friction
	player.acceleration = Vector3(0.0, -wall_climbing_gravity, 0.0)

## TdMove_WallClimb.UpdateViewRotation: the base, then the view drawn up to
## the ledge found up the wall, or to a point 100 uu over the eyes at the wall.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	var result: Array = super.update_view_rotation(view, dt, delta_rot, now)
	if found_possible_hand_plant_flag:
		look_at_ledge(possible_edge_destination)
	else:
		var target: Vector3 = player.global_position - player.move_normal * player.collision_radius()
		target.y += Player.BASE_EYE_HEIGHT + 100.0 * UU
		look_at_ledge(target)
	return result

## TdMove_WallClimb.LookAtLedge: a ledge above the eyes is looked up at, in 0.2
## s; the yaw goes square to the wall only when the pawn is already within
## 4096 units of it. Anything lower ends the look.
func look_at_ledge(ledge_location: Vector3) -> void:
	var eye: Vector3 = player.global_position + Vector3.UP * Player.BASE_EYE_HEIGHT
	if ledge_location.y <= eye.y:
		abort_look_at_target()
		return
	var wall_yaw: int = UE.dir_yaw(-player.move_normal)
	var pawn_yaw: int = UE.yaw_units(player.pawn_yaw)
	var pitch: int = UE.dir_pitch(PawnPhysics.safe_normal(ledge_location - eye))
	var yaw: int = pawn_yaw if absi(wall_yaw - pawn_yaw) > 4096 else wall_yaw
	set_look_at_target_angle(UE.normalize_axis(pitch), UE.normalize_axis(yaw), 0.2)

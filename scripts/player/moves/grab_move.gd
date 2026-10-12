class_name GrabMove
extends PhysicsMove

# The original's TdMove_Grab (MOVE_Grabbing 3): hanging from a ledge.
# [ME:CONFIRMED decompile script TdMove_Grab.uc; PrePhysics 0x01207a70,
# UpdateShimmy 0x011f7d60, CheckWallLegPlacement 0x011f7f40 read, N5 §12]
#
# No physics while hanging (PHYS_None) and no collision; PlayerGrabbing turns
# the stick into one action a tick (shimmy, climb, drop). The pull-up, the jump
# off and the transfer are their own moves, asked by the action table.
#
# The native per-tick half (PrePhysics) runs only while the body has physics,
# which while hanging means while a shimmy flies it (PHYS_Flying) -- the actor
# tick skips performPhysics under PHYS_None, so an idle hang probes nothing:
#   * the legs: a 10 uu box swept from 52 uu above the feet, from either foot,
#     up to 32 uu past the box's reach in front -- wall or free hang;
#   * the ledge: the hand-plant search from 5 uu to the side the shimmy goes,
#     30 uu deep, single pair. A top on the same wall refreshes the ledge; a
#     turned wall stops the shimmy; no top asks CanShimmyAroundCorner, and a
#     free corner with a ledge round it starts the corner shimmy.
# Kept as the original has it: the shimmy's time-out compares the SIGNED
# velocity, so only a left shimmy (-60) times out -- a right one runs to its
# animation's end; a timed out left shimmy keeps drifting while its animation
# blends out.

enum GrabType { LEGS_ON_WALL, LEGS_FREE }
enum ShimmyType { SHIMMY, SHIMMY_LONG, AROUND_CORNER, NO_SHIMMY }
enum FoldedType { NONE, START, END }

## TdPawn.CurrentGrabTurnType: 0 none, 1 turning, 2 turning back, 3 turned.
var current_grab_turn_type: int = 0

var relative_extent: float = 0.0
var distance_to_wall_from_feet: float = 0.0
var is_within_forward_view: bool = true
var is_turned_right: bool = false
var sloped_ledge: bool = false
var climb_up_folded_action_received: bool = false
var request_drop_down_flag: bool = false
var hang_free_vertigo_effect: bool = false
var grab_from_vertical_wallrun: bool = false
var grab_from_high_z_speed: bool = false
var pending_shimmy_corner_animation: StringName = &""
var grab_type: int = GrabType.LEGS_ON_WALL
var previous_grab_type: int = GrabType.LEGS_ON_WALL
var current_shimmy_move: int = ShimmyType.NO_SHIMMY
var current_folded_type: int = FoldedType.NONE
## The corner shimmy's target yaw, rotator units; -1 when none.
var target_yaw: int = -1
var target_location: Vector3 = Vector3.ZERO
var shimmy_velocity: float = 0.0
var shimmy_time: float = 0.0
var last_shimmy_time_seconds: float = 0.0
## The animation the shimmy speed is scaled by (CustomAnimNode): its blend
## weight is NodeTotalWeight.
var custom_anim_node: StringName = &""
var start_looking_at_ledge_time: float = 0.0
var stop_looking_at_ledge_time: float = 0.0
## bConstrainLook, which the hang turns off and on at runtime.
var constrain_look_flag: bool = true
## MinLookConstraint / MaxLookConstraint as UpdateViewConstraints sets them,
## (pitch, yaw) rotator units.
var min_look: Vector2i = MIN_LOOK
var max_look: Vector2i = MAX_LOOK

## The CDO's constraints and the variants UpdateViewConstraints swaps in.
const MIN_LOOK := Vector2i(-3200, -32768)
const MAX_LOOK := Vector2i(16000, 32768)
const HANG_FREE_MIN_LOOK := Vector2i(8300, -16384)
const HANG_FREE_MAX_LOOK := Vector2i(16000, 16384)
const SLOPE_MIN_LOOK := Vector2i(-3200, -8192)
const SLOPE_MAX_LOOK := Vector2i(8300, 8192)
const CORNER_MIN_LOOK := Vector2i(3200, -32768)
const CORNER_MAX_LOOK := Vector2i(16000, 32768)
const CORNER_FREE_MIN_LOOK := Vector2i(11000, -32768)
const CORNER_FREE_MAX_LOOK := Vector2i(16000, 32768)
## The corner shimmy's start offset from its end: the corner animations' root
## displacement, forward and sideways uu.
const CORNER_FORWARD := 63.858 * UU
const CORNER_SIDE := 60.753 * UU
## PrePhysics' ledge probe: 5 uu to the side, 30 uu deep.
const SHIMMY_PROBE_SIDE := 5.0 * UU
const SHIMMY_PROBE_DISTANCE := 30.0 * UU
## CanShimmy's sideways sweep.
const SHIMMY_CHECK_DISTANCE := 35.0 * UU
## StartShimmy: 60 uu/s for ShimmyTime 1 s.
const SHIMMY_SPEED := 60.0 * UU
const SHIMMY_TIME := 1.0
const HANG_FREE_TURN_CONSTRAINT_DELTA := 750

func _init() -> void:
	super._init()
	pawn_physics = PHYS_NONE
	controller_state = CS_PLAYER_GRABBING
	disable_collision = true
	disable_face_rotation = true
	disable_look_time = 0.8

func is_ported() -> bool:
	return true

## TdMove_Grab.HandleDeath: a body going round a corner survives with one
## point; any other hang lets go into Falling and dies.
func handle_death(damage: float) -> float:
	if current_shimmy_move == ShimmyType.AROUND_CORNER:
		return player.health.hp - 1.0
	player.move_manager.set_move(FALLING)
	return damage

func uses_view_rotation() -> bool:
	return true

func _grab_cfg() -> GrabConfig:
	return cfg as GrabConfig

func constrains_look() -> bool:
	return constrain_look_flag

## TdMove_Grab.CanDoMove: only from IntoGrab, facing the ledge.
func can_do_move() -> bool:
	if player.movement_state != INTO_GRAB:
		return false
	if not is_facing_ledge():
		return false
	return td_can_do_move()

## TdMove_Grab.IsFacingLedge: -MoveNormal within GrabMaxAngle of the pawn's
## facing.
func is_facing_ledge() -> bool:
	return (-player.move_normal).dot(player.facing()) >= cos(_grab_cfg().grab_max_angle)

## UTdMove_Grab::IsHangingFree.
func is_hanging_free() -> bool:
	return grab_type == GrabType.LEGS_FREE and not sloped_ledge

## UTdMove_Grab::CheckWallLegPlacement. [ME:CONFIRMED decompile 0x011f7f40]
func check_wall_leg_placement() -> int:
	var f: Vector3 = PawnPhysics.safe_normal_2d(player.facing())
	var left: Vector3 = UE.cross(f, Vector3.UP)
	var w: float = MoveTraces.HAND_PLANT_EXTENT_CHECK_WIDTH * 0.5
	var r: float = player.collision_radius()
	var o: float = r - w
	var here: Vector3 = player.global_position
	var z: float = here.y + player.collision_half_height() - _grab_cfg().hang_free_z_distance_check
	var reach: float = MoveTraces.box_reach(player.move_normal, r)
	var d: float = reach + 32.0 * UU
	var extent := Vector3(w, w, w)
	for s in [here + left * o, here - left * o]:
		var start := Vector3(s.x, z, s.z)
		var hit: Dictionary = player.traces.trace(start + f * d, start, extent)
		if hit["hit"]:
			var at: Vector3 = hit["location"]
			distance_to_wall_from_feet = maxf(0.0, Vector2(start.x - at.x, start.z - at.z).length() - reach)
			return GrabType.LEGS_ON_WALL
	return GrabType.LEGS_FREE

func set_grab_type(value: int) -> void:
	previous_grab_type = grab_type
	grab_type = value

## TdMove_Grab.StartMove.
func enter(_previous: StringName) -> void:
	sloped_ledge = player.move_ledge_normal.y < 0.999
	relative_extent = player.traces.calculate_relative_extent(player.collision_radius())
	player.velocity = Vector3.ZERO
	target_yaw = -1
	current_shimmy_move = ShimmyType.NO_SHIMMY
	current_grab_turn_type = 0
	update_view_constraints()
	hang_free_vertigo_effect = false
	climb_up_folded_action_received = false
	request_drop_down_flag = false
	last_shimmy_time_seconds = player.world_time
	# bTakeFallDamage is the pawn's default: a catch after a long fall hurts
	# as a landing would, and the fall counts again from the hands.
	player.take_falling_damage()
	player.enter_falling_height = player.collision_center().y

## TdMove_Grab.StopMove.
func exit() -> void:
	player.use_root_motion(false)
	player.use_root_rotation(false)
	player.face_rotation_time_left = 0.5
	if current_folded_type != FoldedType.START:
		player.anim_slot.stop(0.2)
	hang_free_vertigo_effect = false
	grab_from_vertical_wallrun = false
	request_drop_down_flag = false
	constrain_look_flag = true
	grab_from_high_z_speed = false

## TdMove_Grab.EnableFoldedHang, asked by IntoGrab.
func enable_folded_hang() -> void:
	current_folded_type = FoldedType.START
	play_slot_anim(&"HangFoldedStart", 1.0, 0.2, 0.0)
	constrain_look_flag = false

func _can_drop_down() -> bool:
	if hang_free_vertigo_effect or request_drop_down_flag:
		return false
	return current_folded_type == FoldedType.NONE

## TdMove_Grab.CanPullUp.
func can_pull_up() -> bool:
	if hang_free_vertigo_effect:
		return false
	if grab_from_vertical_wallrun and move_active_time < 1.0:
		return false
	if current_folded_type == FoldedType.END:
		return false
	if request_drop_down_flag:
		return false
	if grab_from_high_z_speed and move_active_time < 1.0:
		return false
	return true

## TdMove_Grab.RequestDropDown: crouch while hanging. With nothing turning,
## the let-go animation plays first and its end drops the body; otherwise it
## drops at once.
func request_drop_down() -> void:
	if not _can_drop_down():
		return
	if current_shimmy_move != ShimmyType.AROUND_CORNER and current_grab_turn_type == 0 \
			and (not grab_from_vertical_wallrun or move_active_time > 1.0):
		play_slot_anim(&"HangFreeEnd" if is_hanging_free() else &"HangEnd", 1.0, 0.1, 0.2)
	else:
		_drop_down()
	request_drop_down_flag = true

func _drop_down() -> void:
	player.move_manager.set_move(FALLING)

## TdMove_Grab.UpdateViewRotation.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	if hang_free_vertigo_effect or current_folded_type != FoldedType.NONE:
		delta_rot = Vector2i.ZERO
	if delta_rot != Vector2i.ZERO:
		abort_look_at_target()
	var result: Array = super.update_view_rotation(view, dt, delta_rot, now)
	var out: Vector2i = result[0]
	var pawn_units: int = UE.yaw_units(player.pawn_yaw)
	var controller_yaw: int = UE.normalize_axis(UE.normalize_axis(out.y) - pawn_units)
	var start_turning: int = _grab_cfg().start_turning_angle
	is_within_forward_view = controller_yaw < start_turning and controller_yaw > -start_turning
	is_turned_right = controller_yaw >= 0
	var trigger_hang_free_turn: bool = is_hanging_free() \
		and (controller_yaw >= HANG_FREE_MAX_LOOK.y - HANG_FREE_TURN_CONSTRAINT_DELTA
			or controller_yaw <= HANG_FREE_MIN_LOOK.y + HANG_FREE_TURN_CONSTRAINT_DELTA) \
		and not hang_free_vertigo_effect
	if not is_hanging_free():
		if current_grab_turn_type == 0:
			if controller_yaw > start_turning:
				play_slot_anim(&"HangTurnRightStart", 1.0, 0.2, 0.2)
				current_grab_turn_type = 1
				set_timer(0.2)
			elif controller_yaw < -start_turning:
				play_slot_anim(&"HangTurnLeftStart", 1.0, 0.2, 0.2)
				current_grab_turn_type = 1
				set_timer(0.2)
			elif move_active_time > 1.0:
				timer = 0.0
		elif is_within_forward_view:
			if current_grab_turn_type == 3:
				play_slot_anim(&"HangTurnRightEnd" if is_turned_right else &"HangTurnLeftEnd", 1.0, 0.2, 0.2)
				current_grab_turn_type = 2
				set_timer(0.6)
			elif current_grab_turn_type == 1:
				player.anim_slot.stop(0.2)
				current_grab_turn_type = 0
	else:
		current_grab_turn_type = 0
	if move_active_time > start_looking_at_ledge_time and move_active_time < stop_looking_at_ledge_time \
			and current_folded_type == FoldedType.NONE and not grab_from_vertical_wallrun:
		set_look_at_target_location(player.move_ledge_location, 0.3, 0.25)
	if trigger_hang_free_turn:
		hang_free_vertigo_effect = true
		play_slot_anim(&"HangFreeTurnRight" if is_turned_right else &"HangFreeTurnLeft", 1.0, 0.2, 0.2)
		set_look_at_target_angle(0, pawn_units, 0.2, 0.2)
		constrain_look_flag = false
		set_timer(1.75)
	return result

## TdMove_Grab.OnTimer.
func on_timer() -> void:
	if current_grab_turn_type == 2:
		current_grab_turn_type = 0
	elif current_grab_turn_type == 1:
		current_grab_turn_type = 3
	else:
		abort_look_at_target()
		set_look_at_target_angle(9000, UE.yaw_units(player.pawn_yaw), 0.2, 0.5)

## TdMove_Grab.UpdateViewConstraints.
func update_view_constraints() -> void:
	if sloped_ledge:
		min_look = SLOPE_MIN_LOOK
		max_look = SLOPE_MAX_LOOK
		if is_hanging_free():
			min_look.x = HANG_FREE_MIN_LOOK.x
			max_look.x = HANG_FREE_MAX_LOOK.x
	elif current_shimmy_move == ShimmyType.AROUND_CORNER:
		min_look = CORNER_FREE_MIN_LOOK if is_hanging_free() else CORNER_MIN_LOOK
		max_look = CORNER_FREE_MAX_LOOK if is_hanging_free() else CORNER_MAX_LOOK
	else:
		min_look = HANG_FREE_MIN_LOOK if is_hanging_free() else MIN_LOOK
		max_look = HANG_FREE_MAX_LOOK if is_hanging_free() else MAX_LOOK

## While any shimmy runs the yaw is held to +-5000 and the pitch to level and
## up.
func get_min_look_constrain_yaw() -> int:
	return -5000 if current_shimmy_move != ShimmyType.NO_SHIMMY else min_look.y

func get_max_look_constrain_yaw() -> int:
	return 5000 if current_shimmy_move != ShimmyType.NO_SHIMMY else max_look.y

func get_min_look_constrain_pitch() -> int:
	return 0 if current_shimmy_move != ShimmyType.NO_SHIMMY else min_look.x

func get_max_look_constrain_pitch() -> int:
	return max_look.x

static func _is_left(action: int) -> bool:
	return action == MA_SHIMMY_LEFT or action == MA_SHIMMY_LEFT_LONG

static func _is_right(action: int) -> bool:
	return action == MA_SHIMMY_RIGHT or action == MA_SHIMMY_RIGHT_LONG

## TdMove_Grab.HandleMoveAction.
func handle_move_action(action: int) -> void:
	climb_up_folded_action_received = action == MA_CLIMB_UP
	if current_shimmy_move == ShimmyType.SHIMMY and action == MA_NONE:
		abort_shimmy()
		return
	if current_shimmy_move == ShimmyType.AROUND_CORNER or hang_free_vertigo_effect \
			or current_folded_type == FoldedType.START:
		return
	var shimmy_allowed: bool = move_active_time > _grab_cfg().disable_shimmy_time
	var move_left: bool = _is_left(action) and shimmy_allowed
	var move_right: bool = _is_right(action) and shimmy_allowed
	if sloped_ledge or request_drop_down_flag:
		return
	if (move_left or move_right) and not is_within_forward_view and not is_hanging_free():
		return
	if action == MA_TURN and current_folded_type == FoldedType.NONE:
		stop_looking_at_ledge_time = 0.0
		var yaw: int = UE.yaw_units(player.pawn_yaw) + (max_look.y if is_turned_right else min_look.y)
		abort_look_at_target()
		set_look_at_target_angle(0, UE.normalize_axis(yaw), 0.2)
	if (move_left or move_right) and player.world_time - last_shimmy_time_seconds > 0.5:
		if can_shimmy(action):
			start_shimmy(action)
		else:
			abort_shimmy()

## The pawn's right axis, flat.
func _right() -> Vector3:
	return PawnPhysics.safe_normal_2d(UE.cross(Vector3.UP, player.facing()))

## The hang point the shimmy sweeps start from.
func _hang_point() -> Vector3:
	var c: GrabConfig = _grab_cfg()
	var start: Vector3 = player.move_ledge_location \
		+ player.move_normal * (c.grab_desired_ledge_offset_x + relative_extent)
	start.y -= c.grab_desired_ledge_offset_z
	return start

## TdMove_Grab.CanShimmy: the body box swept 35 uu sideways from the hang point.
func can_shimmy(action: int) -> bool:
	if current_grab_turn_type != 0:
		return false
	var direction: Vector3 = -_right() if _is_left(action) else _right()
	var start: Vector3 = _hang_point()
	return not player.traces.movement_trace_for_blocking(start + direction * SHIMMY_CHECK_DISTANCE,
		start, player.collision_extent())

## TdMove_Grab.CanShimmyAroundCorner: free sideways past the corner, then free
## back toward the wall's side; the end of that is the corner shimmy's target.
func can_shimmy_around_corner(action: int) -> bool:
	var left: bool = _is_left(action)
	var direction: Vector3 = -_right() if left else _right()
	var c: GrabConfig = _grab_cfg()
	var distance: float = c.grab_desired_ledge_offset_x * 2.0 + relative_extent + 4.0 * UU
	var start: Vector3 = _hang_point()
	var end: Vector3 = start + direction * distance
	var extent: Vector3 = player.collision_extent()
	if player.traces.movement_trace_for_blocking(end, start, extent):
		return false
	start = end
	end = start - player.move_normal * distance
	if player.traces.movement_trace_for_blocking(end, start, extent):
		return false
	target_location = end
	target_yaw = UE.normalize_axis(UE.yaw_units(player.pawn_yaw) + (16384 if left else -16384))
	return true

## TdMove_Grab.StartShimmy.
func start_shimmy(action: int) -> void:
	if current_shimmy_move == ShimmyType.SHIMMY:
		return
	var left: bool = _is_left(action)
	abort_look_at_target()
	current_shimmy_move = ShimmyType.SHIMMY
	shimmy_velocity = SHIMMY_SPEED * (-1.0 if left else 1.0)
	shimmy_time = SHIMMY_TIME
	last_shimmy_time_seconds = player.world_time
	player.set_physics(PHYS_FLYING)
	play_slot_anim(_strafe_anim(left), 1.0, 0.2, 0.0)
	custom_anim_node = player.anim_slot.current_name()

func _strafe_anim(left: bool) -> StringName:
	if is_hanging_free():
		return &"HangFreeStrafeLeft" if left else &"HangFreeStrafe"
	return &"HangStrafeLeft" if left else &"HangStrafeRight"

## TdMove_Grab.StartShimmyAroundCorner: the body put at the corner
## animation's start, its root motion and then its root rotation carrying it
## round to the target.
func start_shimmy_around_corner(action: int) -> void:
	var left: bool = _is_left(action)
	var x: Vector3 = player.facing()
	var y: Vector3 = _right()
	player.use_root_motion(true)
	set_move_timer(0.1, false, _start_root_rotation)
	if left:
		player.global_position = target_location - x * CORNER_FORWARD + y * CORNER_SIDE
	else:
		player.global_position = target_location - x * CORNER_FORWARD - y * CORNER_SIDE
	abort_look_at_target()
	reset_camera_look(0.1)
	player.anim_slot.stop(0.2)
	if left:
		pending_shimmy_corner_animation = &"HangFreeCornerOutSideLeft" if is_hanging_free() \
			else &"HangCornerOutSideLeft"
	else:
		pending_shimmy_corner_animation = &"HangFreeCornerOutSideRight" if is_hanging_free() \
			else &"HangCornerOutSideRight"
	player.set_physics(PHYS_FLYING)
	current_shimmy_move = ShimmyType.AROUND_CORNER
	update_view_constraints()

func _start_root_rotation() -> void:
	player.use_root_rotation(true)
	play_slot_anim(pending_shimmy_corner_animation, 1.0, 0.15, 0.15, true, true)

## TdMove_Grab.AbortShimmy. Without the force, the strafe stops only inside
## the animation's (0.1, 0.25) or past 0.8 of it.
func abort_shimmy(force_vel_stop: bool = false) -> void:
	if current_shimmy_move == ShimmyType.AROUND_CORNER:
		return
	if force_vel_stop:
		player.velocity = Vector3.ZERO
		player.acceleration = Vector3.ZERO
		player.anim_slot.stop(0.2)
		current_shimmy_move = ShimmyType.NO_SHIMMY
		shimmy_time = 0.0
		return
	var position: float = player.anim_slot.normalized_position(custom_anim_node)
	if (position > 0.1 and position < 0.25) or position > 0.8:
		player.anim_slot.stop(0.4)
		current_shimmy_move = ShimmyType.NO_SHIMMY
		shimmy_time = 0.0

## TdMove_Grab.OnCustomAnimEnd.
func on_custom_anim_end(anim: StringName) -> void:
	if current_shimmy_move == ShimmyType.AROUND_CORNER:
		if anim == pending_shimmy_corner_animation and target_yaw != -1:
			player.pawn_yaw = UE.godot_yaw(target_yaw)
			player.global_position = target_location
			target_yaw = -1
			shimmy_time = 0.0
			relative_extent = player.traces.calculate_relative_extent(player.collision_radius())
		else:
			return
	player.use_root_motion(false)
	player.use_root_rotation(false)
	current_shimmy_move = ShimmyType.NO_SHIMMY
	player.velocity = Vector3.ZERO
	player.set_physics(PHYS_NONE)
	update_view_constraints()
	if current_folded_type == FoldedType.START:
		if climb_up_folded_action_received and player.move_manager.can_do(GRAB_PULL_UP):
			climb_up_folded_action_received = false
			player.move_manager.set_move(GRAB_PULL_UP)
		else:
			if is_hanging_free():
				play_slot_anim(&"HangFreeFoldedEndHangFree", 1.0, 0.0, 0.2)
				set_timer(1.5)
			else:
				play_slot_anim(&"HangFoldedEndHang", 1.0, 0.0, 0.2)
			current_folded_type = FoldedType.END
			constrain_look_flag = false
	elif current_folded_type == FoldedType.END:
		current_folded_type = FoldedType.NONE
		constrain_look_flag = true
	if hang_free_vertigo_effect:
		hang_free_vertigo_effect = false
		constrain_look_flag = true
	if current_grab_turn_type == 1:
		current_grab_turn_type = 3
	elif current_grab_turn_type == 2:
		current_grab_turn_type = 0
	if request_drop_down_flag:
		_drop_down()

## TdMove_Grab.UpdateGrabType, raised by the per-tick native when the legs
## change between the wall and free: the strafe animation of the new kind,
## picked up where the last one was -- its normalized position times the
## LAST animation's playback length, as the original computes it.
func update_grab_type(moving_left: bool) -> void:
	update_view_constraints()
	var slot: CustomAnimSlot = player.anim_slot
	var prev_position: float = slot.current_normalized_position()
	var prev_length: float = slot.current_playback_length()
	play_slot_anim(_strafe_anim(moving_left), 1.0, 0.2, 0.0)
	slot.set_position(prev_position * prev_length)

## UTdMove_Grab's native PrePhysics. [ME:CONFIRMED decompile 0x01207a70]
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.move_manager.current_move() != self:
		return
	if current_shimmy_move == ShimmyType.AROUND_CORNER:
		return
	var act: int = MA_SHIMMY_LEFT if shimmy_velocity < 0.0 else MA_SHIMMY_RIGHT
	var g: int = check_wall_leg_placement()
	if g != grab_type:
		previous_grab_type = grab_type
		grab_type = g
		update_grab_type(act == MA_SHIMMY_LEFT)
	var side: Vector3 = -_right() if act == MA_SHIMMY_LEFT else _right()
	var hit: Dictionary = player.traces.find_auto_move_ledge(player.global_position + side * SHIMMY_PROBE_SIDE,
		player.facing(), SHIMMY_PROBE_DISTANCE, false, false)
	if hit["result"] == MoveTraces.LEDGE_TOP:
		if player.move_normal.dot(hit["move_normal"]) >= 0.98:
			player.move_ledge_location = hit["ledge_location"]
			player.move_ledge_normal = hit["ledge_normal"]
			player.move_normal = hit["move_normal"]
		else:
			shimmy_velocity = 0.0
			abort_shimmy(true)
	else:
		if can_shimmy_around_corner(act):
			var round: Dictionary = player.traces.find_auto_move_ledge(target_location,
				UE.yaw_dir(target_yaw), MoveTraces.HAND_PLANT_CHECK_DISTANCE, false, false)
			if round["result"] == MoveTraces.LEDGE_TOP:
				player.move_ledge_location = round["ledge_location"]
				player.move_ledge_normal = round["ledge_normal"]
				player.move_normal = round["move_normal"]
				var c: GrabConfig = _grab_cfg()
				target_location = player.move_ledge_location \
					+ player.move_normal * (relative_extent + c.grab_desired_ledge_offset_x)
				target_location.y -= c.grab_desired_ledge_offset_z
				abort_shimmy(false)
				start_shimmy_around_corner(act)
				return
		shimmy_velocity = 0.0
		abort_shimmy(true)
	if absf(shimmy_velocity) > 0.0:
		update_shimmy(delta)

## UTdMove_Grab::UpdateShimmy. [ME:CONFIRMED decompile 0x011f7d60] Along the
## pawn's right axis at the strafe animation's blend weight times the signed
## shimmy speed. The time-out compares that SIGNED speed with 1e-4: only a
## left shimmy ever times out.
func update_shimmy(delta: float) -> void:
	var d: Vector3 = _right()
	player.velocity = d * (player.anim_slot.weight_of(custom_anim_node) * shimmy_velocity)
	shimmy_time -= delta
	if shimmy_time < 0.0 and shimmy_velocity < 1e-4 * UU:
		abort_shimmy(false)

## For the debug HUD.
func shimmy_report() -> String:
	return "%s v %+.2f t %.2f %s turn %d" % [ShimmyType.keys()[current_shimmy_move], shimmy_velocity,
		shimmy_time, GrabType.keys()[grab_type], current_grab_turn_type]

## For the animation: -1 travelling left, +1 right, 0 still.
func shimmy_direction() -> float:
	if current_shimmy_move == ShimmyType.SHIMMY:
		return signf(shimmy_velocity)
	if current_shimmy_move == ShimmyType.AROUND_CORNER:
		return -1.0 if String(pending_shimmy_corner_animation).ends_with("Left") else 1.0
	return 0.0

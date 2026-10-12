class_name LedgeWalkMove
extends PhysicsMove

# The original's TdMove_LedgeWalk (MOVE_LedgeWalk 30): back to the wall along
# a narrow ledge. [ME:CONFIRMED decompile script TdMove_LedgeWalk.uc;
# PrePhysics 0x0120a530 emulated, N5 §19]
#
# Taken on entering (or standing in) a ledge-walk volume from Walking, Landing
# or Balance. PlayerLedgeWalking turns the stick's strafe past 0.6 into a
# shimmy action and gives no acceleration; the move sets the velocity itself
# every frame -- 80 uu/s along the line (left is along it, right against it),
# capped by the walking physics at SpeedModifier 0.1, i.e. 72 uu/s -- turns
# the pawn to face away from the wall, and pulls the body onto the line at 10
# per second. Jump on a plain ledge is a Jump with 200 uu/s off the wall;
# leaving the volume ends it 0.2 s later, unless it was entered again.
#
# The volume is a LEDGE_WALK InterestLine: front() points AT the wall, so the
# original's WallNormal is -front(); its FloorNormal is taken as straight up.
# Its spline is the original's (MovementSpline), searched every frame from the
# segment the body was on -- a parameter StartMove never resets, so the next
# ledge walk starts its search where the last one left off.

var volume: InterestLine = null
var current_param_on_curve: float = 0.0
var strafe_factor: float = 0.0
var strafe_speed: float = 0.0
var pending_leaving_volume: bool = false
## MinLookConstraint.Pitch, which CheckLedgeWalkType rewrites.
var min_look_pitch: int = MIN_LOOK_PITCH

const MIN_LOOK_PITCH := -14000
const NARROW_MIN_LOOK_PITCH := -6000
const STRAFE_SPEED := 80.0 * UU
const NARROW_RADIUS := 10.0 * UU

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_LEDGE_WALKING
	disable_face_rotation = true
	disable_controller_facing_pawn_yaw_rotation = true
	avoid_ledges = false

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

## WallNormal: out from the wall.
func wall_normal() -> Vector3:
	return -volume.front()

func is_narrow() -> bool:
	return volume != null and volume.narrow_space

## TdMove_LedgeWalk.CanDoMove: from Walking, Landing or Balance.
func can_do_move() -> bool:
	var state: StringName = player.movement_state
	if state == WALKING or state == LANDING or state == BALANCE:
		return td_can_do_move()
	return false

## TdMove_LedgeWalk.StartMove.
func enter(_previous: StringName) -> void:
	if is_narrow():
		player.set_collision_radius(NARROW_RADIUS)
	var wall_yaw: int = UE.dir_yaw(wall_normal())
	set_look_at_target_angle(0, wall_yaw, 0.5, 0.5)
	set_precise_rotation(wall_yaw, 0.5)
	strafe_factor = 0.0
	var look_pitch: int = 0
	var look_yaw: int = wall_yaw
	var vel_2d: Vector3 = PawnPhysics.safe_normal(player.velocity)
	vel_2d.y = 0.0
	if not is_narrow():
		look_pitch = min_look_pitch + 7000
		set_look_at_target_angle(look_pitch, look_yaw, 0.2)
	else:
		if UE.cross(wall_normal(), vel_2d).y < 0.0:
			look_yaw += get_min_look_constrain_yaw()
		else:
			look_yaw += get_max_look_constrain_yaw()
		if player.horizontal_speed() > 50.0 * UU:
			set_look_at_target_angle(look_pitch, UE.normalize_axis(look_yaw), 0.2)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	pending_leaving_volume = false
	play_slot_anim(&"LedgeInto", 1.0, 0.2, 0.3)
	check_ledge_walk_type()

func check_ledge_walk_type() -> void:
	if volume == null:
		return
	min_look_pitch = NARROW_MIN_LOOK_PITCH if volume.narrow_space else MIN_LOOK_PITCH

func get_min_look_constrain_pitch() -> int:
	return min_look_pitch

## TdMove_LedgeWalk.HandleMoveAction.
func handle_move_action(action: int) -> void:
	if action == MA_JUMP and not is_narrow():
		if player.move_manager.can_do(JUMP):
			player.velocity = player.facing() * 200.0 * UU
			player.move_manager.set_move(JUMP)
		return
	if action != MA_SHIMMY_LEFT and action != MA_SHIMMY_RIGHT:
		strafe_speed = 0.0
	elif action == MA_SHIMMY_LEFT:
		strafe_speed = STRAFE_SPEED
	else:
		strafe_speed = -STRAFE_SPEED

## TdMove_LedgeWalk.UpdateViewRotation: any look input ends the look-at.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	if delta_rot != Vector2i.ZERO:
		abort_look_at_target()
	return super.update_view_rotation(view, dt, delta_rot, now)

func notify_leaving_volume() -> void:
	pending_leaving_volume = true
	set_timer(0.2)

func notify_entering_volume() -> void:
	pending_leaving_volume = false
	set_precise_rotation(UE.dir_yaw(wall_normal()), 0.5)
	check_ledge_walk_type()

func on_timer() -> void:
	if pending_leaving_volume:
		player.move_manager.set_move(WALKING)

## TdMove_LedgeWalk.StopMove.
func exit() -> void:
	player.set_collision_radius(player.default_collision_radius())

## UTdMove_LedgeWalk's native PrePhysics. [ME:CONFIRMED emulated 0x0120a530]
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.move_manager.current_move() != self or volume == null or not is_instance_valid(volume):
		return
	var here: Vector3 = player.global_position
	var spline := MovementSpline.of(volume)
	var found: Array = spline.find_closest(here, int(current_param_on_curve))
	current_param_on_curve = found[1]
	var c: Vector3 = found[0]
	c.y = here.y
	var t: Vector3 = spline.slope_at(current_param_on_curve / float(spline.num_segments))
	var a: Vector3 = UE.cross(t, Vector3.UP)
	var face: Vector3 = PawnPhysics.safe_normal_2d(a * (wall_normal().dot(a) / a.length_squared()))
	var v: Vector3 = PawnPhysics.safe_normal_2d(t) * strafe_speed
	player.velocity = v
	player.acceleration = v
	if not use_precise_rotation:
		player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(face))
	var side: Vector3 = PawnPhysics.safe_normal(UE.cross(face, Vector3.DOWN))
	strafe_factor = v.dot(side)
	player.phys.move_actor((c - here) * delta * 10.0)

## The volume's PawnEnteredVolume, PawnLeavingVolume and PawnUpdate.
func volume_entered(line: InterestLine) -> void:
	volume = line
	notify_entering_volume()
	if player.movement_state != LEDGE_WALK:
		if can_do_move():
			player.move_manager.set_move(LEDGE_WALK)
		else:
			volume = null

func volume_leaving(_line: InterestLine) -> void:
	if player.movement_state == LEDGE_WALK:
		notify_leaving_volume()

func volume_pawn_update(line: InterestLine) -> bool:
	if player.movement_state == LEDGE_WALK:
		return false
	volume = line
	if can_do_move():
		player.move_manager.set_move(LEDGE_WALK)
		return true
	return false

## For the animation: -1 left, 0 still, +1 right.
func shuffle_direction() -> int:
	if strafe_factor > 0.0:
		return 1
	if strafe_factor < 0.0:
		return -1
	return 0

class_name GrabJumpMove
extends PhysicsMove

# The original's TdMove_GrabJump (MOVE_GrabJump 13): jumping back off a hang or
# a ladder. [ME:CONFIRMED decompile script TdMove_GrabJump.uc, N5 §13]
#
# Jump with the view turned at least 45 degrees from the wall (after
# GrabTransfer and GrabPullUp have refused). The launch is along the view's
# flat direction at 200 .. 400 uu/s (400 looking straight out from the wall)
# and up at 2 g sqrt(h / g) for h = 160 uu or the headroom, g the script
# gravity -- the falling physics doubles it, so the apex is h.
#
# The velocity is applied 0.1 s AFTER the move starts: until then the body is
# already falling from rest and drops about 8 uu first. Kept. The hand and
# vault checks wait 0.2 s; the animation's end (1.5 s) hands to Falling.

var jump_velocity: Vector3 = Vector3.ZERO
var turned_left: bool = false
## The view's yaw from the pawn's at the start, rotator units.
var delta_jump_yaw: int = 0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_falling = true
	delay_time_check_auto_moves = 0.2
	disable_face_rotation = true

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func _jump_cfg() -> GrabJumpConfig:
	return cfg as GrabJumpConfig

## TdMove_GrabJump.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	var turned: int = UE.normalize_axis(UE.yaw_units(player.pawn_yaw) - UE.yaw_units(player.rotation.y))
	if absf(float(turned)) < 32768.0 * _jump_cfg().grab_allowed_jump_angle / 180.0:
		return false
	var state: StringName = player.movement_state
	if state == GRAB:
		var grab: GrabMove = player.move_manager.move_for(GRAB) as GrabMove
		if grab != null and grab.is_hanging_free():
			return false
	return state == GRAB or state == CLIMB

## TdMove_GrabJump.StartMove.
func enter(_previous: StringName) -> void:
	var c: GrabJumpConfig = _jump_cfg()
	player.last_jump_location = player.global_position
	var cam_dir: Vector3 = PawnPhysics.safe_normal_2d(
		UE.rot_dir(player.controller_pitch_units(), UE.yaw_units(player.rotation.y)))
	turned_left = UE.cross(cam_dir, player.facing()).y > 0.0
	var interp: float = maxf(cam_dir.dot(player.move_normal), 0.0)
	var push: float = interp * c.grab_jump_push_away_max_speed + (1.0 - interp) * c.grab_jump_push_away_min_speed
	var jump_height: float = c.grab_jump_off_z_height
	var start: Vector3 = player.global_position
	var hit: Dictionary = player.traces.movement_trace(start + Vector3.UP * jump_height, start,
		player.collision_extent())
	if hit["hit"]:
		jump_height = (hit["location"] as Vector3).y - start.y
	var gravity: float = absf(player.gravity_z())
	var speed: float = gravity * 2.0 * sqrt(jump_height / gravity)
	jump_velocity = cam_dir * push
	jump_velocity.y = speed
	play_slot_anim(&"HangTurnJump", 1.0, 0.2, 0.2)
	disable_face_rotation = true
	set_timer(0.1)
	delta_jump_yaw = UE.normalize_axis(UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw))

## The launch, 0.1 s late.
func on_timer() -> void:
	player.velocity = jump_velocity
	player.face_rotation_time_left = 0.3
	disable_face_rotation = false

## TdMove_GrabJump.UpdateViewRotation: in the first 0.05 s a further turn the
## way the view already faces (past 27000 units) is eaten.
func update_view_rotation(view: Vector2i, dt: float, delta_rot: Vector2i, now: float) -> Array:
	if move_active_time < 0.05 and ((delta_rot.y > 300 and delta_jump_yaw >= 27000)
			or (delta_rot.y < -300 and delta_jump_yaw < -27000)):
		delta_rot.y = 0
	return super.update_view_rotation(view, dt, delta_rot, now)

func exit() -> void:
	player.anim_slot.stop(0.2)

func on_custom_anim_end(_anim: StringName) -> void:
	player.move_manager.set_move(FALLING)

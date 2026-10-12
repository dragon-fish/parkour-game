class_name GrabPullUpMove
extends PhysicsMove

# The original's TdMove_GrabPullUp (MOVE_GrabPullUp 10): climbing up from a
# hang. [ME:CONFIRMED decompile script TdMove_GrabPullUp.uc]
#
# Jump or a long push forward while hanging, with the view within 45 degrees
# of the wall. CanDoMove finds the floor over the ledge and picks standing or
# crouched by the room there; a floor more than MaxStepHeight below the ledge
# is a heave OVER (a thin wall), not up. The body is moved by the animation's
# root motion (first-person sequences, rate 1) with collision off; collision
# comes back at 0.6 .. 1.4 s, the camera at 0.6 .. 0.8 s, and the animation's
# end hands to Walking or Crouch.

enum PullUpType { INTO_WALKING, INTO_CROUCH }

var grab_pull_up_type: int = PullUpType.INTO_WALKING
var floor_over_ledge_location: Vector3 = Vector3.ZERO

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE
	pawn_physics = PHYS_FLYING
	controller_state = CS_PLAYER_WALKING
	disable_collision = true
	disable_face_rotation = true
	disable_movement_time = -1.0
	disable_look_time = 0.2

func is_ported() -> bool:
	return true

## TdMove_GrabPullUp.HandleDeath: the pull-up survives with one point.
func handle_death(_damage: float) -> float:
	return player.health.hp - 1.0

func uses_view_rotation() -> bool:
	return true

## The pull-up's pitch floor (level) is the first-person eye's: there is
## nothing to look at below the lip. Seen from outside it only pins the orbit
## below the body, so the camera cannot rise to watch the climb from above --
## the pull-up's pitch goes free in third person. PROJECT-DEFINED presentation.
func third_person_pitch_limits() -> Vector2:
	return Vector2(-PI, PI)

func _grab() -> GrabMove:
	return player.move_manager.move_for(GRAB) as GrabMove

## TdMove_GrabPullUp.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	if player.movement_state != GRAB:
		return false
	if not _grab().can_pull_up():
		return false
	var turned: int = UE.normalize_axis(UE.yaw_units(player.pawn_yaw) - UE.yaw_units(player.rotation.y))
	if absf(float(turned)) > 32768.0 * (cfg as GrabPullUpConfig).grab_allowed_pull_up_angle / 180.0:
		return false
	floor_over_ledge_location = player.global_position - Vector3.UP * player.collision_half_height()
	var max_ledge_thickness: float = 5.0 * UU
	var depth: float = 64.0 * UU + max_ledge_thickness
	# Pawn.MaxStepHeight, 35 uu. DO NOT read max_step_height here: that is
	# this project's measured 0.4 m walking reach, and a floor 35 .. 40 uu
	# below the ledge would be pulled up onto instead of heaved over.
	var step: float = config.pawn.max_step_down_height
	floor_over_ledge_location = find_floor_over_ledge(depth, floor_over_ledge_location, step + 4.0 * UU)
	var delta_height: float = floor_over_ledge_location.y - player.move_ledge_location.y
	if delta_height > -step:
		return can_pull_up(63.0 * UU)
	if not can_pull_up(90.0 * UU + max_ledge_thickness):
		floor_over_ledge_location.y = player.move_ledge_location.y
		return can_pull_up(63.0 * UU)
	return true

## TdMove_GrabPullUp.CanPullUp: standing room, else crouched room (not from a
## folded hang) on a floor no lower than a step below the ledge.
func can_pull_up(check_depth: float) -> bool:
	var grab: GrabMove = _grab()
	var highest: float = player.move_ledge_location.y \
		+ tan(acos(clampf(player.move_ledge_normal.y, -1.0, 1.0))) * player.default_collision_radius()
	if can_heave_over_ledge_fully_extended(check_depth, floor_over_ledge_location, highest):
		grab_pull_up_type = PullUpType.INTO_WALKING
		return true
	if grab.current_folded_type != GrabMove.FoldedType.START \
			and can_heave_over_ledge_crouched(check_depth, floor_over_ledge_location, highest):
		grab_pull_up_type = PullUpType.INTO_CROUCH
		if floor_over_ledge_location.y < player.move_ledge_location.y - config.pawn.max_step_down_height:
			return false
		return true
	return false

## TdMove_GrabPullUp.StartMove.
func enter(_previous: StringName) -> void:
	var grab: GrabMove = _grab()
	var heave_over: bool = floor_over_ledge_location.y \
		< player.move_ledge_location.y - config.pawn.max_step_down_height
	var hanging_free: bool = grab.is_hanging_free()
	var release_camera: float
	var enable_collision: float
	if grab.current_folded_type == GrabMove.FoldedType.START:
		play_slot_anim(&"HangFoldedHeaveUp", 1.0, 0.1, 0.2, true)
		grab.current_folded_type = GrabMove.FoldedType.NONE
		release_camera = 0.8
		enable_collision = 0.8
	elif not heave_over:
		var crouch: bool = grab_pull_up_type == PullUpType.INTO_CROUCH
		if hanging_free:
			play_slot_anim(&"hangfreeheaveuptocrouch" if crouch else &"HangFreeHeaveUp", 1.0, 0.1, 0.2, true)
		else:
			play_slot_anim(&"HangHeaveUpToCrouch" if crouch else &"HangHeaveUp", 1.0, 0.1, 0.2, true)
		release_camera = 0.8
		enable_collision = 1.4
	else:
		play_slot_anim(&"HangFreeHeaveOver" if hanging_free else &"HangHeaveOver", 1.0, 0.2, 0.2, true)
		release_camera = 0.7 if hanging_free else 0.6
		enable_collision = 0.6
	disable_face_rotation = true
	player.use_root_motion(true)
	# This project's presentation: the root motion carries the body up, so the
	# pack's climb clip must not add its own hip lift on top
	# (Player.set_clip_lift_cancelled()).
	player.set_clip_lift_cancelled(true)
	reset_camera_look(disable_look_time)
	set_move_timer(release_camera, false, _release_camera)
	set_move_timer(enable_collision, false, _enable_collision)

func _release_camera() -> void:
	disable_face_rotation = false
	player.face_rotation_time_left = 0.25
	abort_look_at_target()

func _enable_collision() -> void:
	player.collide_world = true
	player.stop_ignore_move_input()

## TdMove_GrabPullUp.StopMove.
func exit() -> void:
	_enable_collision()
	player.set_clip_lift_cancelled(false)

func on_cease_relevant_root_motion() -> void:
	player.use_root_motion(false)

## The animation's end: walking (or crouching) from where it left the body.
func on_custom_anim_end(_anim: StringName) -> void:
	player.use_root_motion(false)
	# Normal(V) is 1 uu/s^2 long in the original: UU here, not 1 m/s^2.
	player.acceleration = PawnPhysics.safe_normal(player.velocity) * UU
	player.set_physics(PHYS_WALKING)
	player.move_manager.set_move(CROUCH if grab_pull_up_type == PullUpType.INTO_CROUCH else WALKING)

## For the animation.
func is_into_crouch() -> bool:
	return grab_pull_up_type == PullUpType.INTO_CROUCH

## For the animation: the original's sequence length, which the pack's clip is
## fitted to, and how far through it the climb is.
func scripted_duration() -> float:
	return player.anim_slot.current_length()

func path_debug() -> Dictionary:
	return {"progress": player.anim_slot.normalized_position(player.anim_slot.current_name())}

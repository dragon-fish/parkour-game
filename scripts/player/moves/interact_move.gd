class_name InteractMove
extends PhysicsMove

# The original's TdMove_Interact, ported for buttons. [ME:CONFIRMED decompile
# script TdMove_Interact, TdPawn's SeqEvent_TdUsed handling]
#
# Pressing use at a TdTrigger walks the body to the button -- 48 uu out along
# the trigger's Y axis, at clamp(distance / 0.2 s, 100, 1000) uu/s on a
# PLM_Walk precise location while it turns to face it over the same 0.2 s --
# then places it exactly, plays the press, and fires the trigger's Used output
# 0.6 s later; 0.85 s after arriving it is Walking. Move and look input are
# off throughout. Refused (not walking, more than half the trigger's
# AngleLimit off facing it, or the spot blocked), the press does nothing.
#
# This project has no use key: a UseZone whose interact_type is set stands in
# for the TdTrigger, its dwell for the press, and its +X axis for the
# trigger's Y. A valve (TIT_Valve) has no UseZone counterpart and is not
# ported.

## [ME:CONFIRMED decompile] UpdateEventDelay: 0.6 s for a button.
const BUTTON_EVENT_DELAY := 0.6
## [ME:CONFIRMED decompile] StartInteract: the walk takes 0.2 s for a button,
## at 100 .. 1000 uu/s.
const BUTTON_WALK_TIME := 0.2
const WALK_SPEED_MIN := 100
const WALK_SPEED_MAX := 1000

## TdMove_Interact.CurrentTrigger.
var current_trigger: UseZone = null
var move_location: Vector3 = Vector3.ZERO
var normal_from_trigger_2d: Vector3 = Vector3.ZERO
var reached_trigger: bool = false
var event_delay: float = 0.0
var _distance_to_object: float = 0.0

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE
	controller_state = CS_PLAYER_WALKING
	# [ME:CONFIRMED decompile] bDisableFaceRotation.
	disable_face_rotation = true
	disable_movement_time = -1.0
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

## TdPawn's use handling: the trigger and its event handed over, then the move
## if it can be done, the trigger released if not. Returns whether it started.
func use_trigger(zone: UseZone) -> bool:
	current_trigger = zone
	if can_do_move():
		player.move_manager.set_move(INTERACT)
		return true
	current_trigger = null
	return false

## TdMove_Interact.CanDoMove.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	if current_trigger == null or not is_instance_valid(current_trigger) \
			or current_trigger.interact_type == UseZone.InteractType.NONE:
		return false
	if player.move_manager.current_name != WALKING:
		return false
	var y: Vector3 = current_trigger.global_basis.x.normalized()
	var deg_diff: float = rad_to_deg(acos(clampf(player.facing().dot(-y), -1.0, 1.0)))
	if absf(deg_diff) > current_trigger.angle_limit / 2.0:
		return false
	normal_from_trigger_2d = y
	_distance_to_object = cfg.distance_to_a_button
	# Normal(Y) with its Z zeroed afterwards and not renormalised.
	normal_from_trigger_2d.y = 0.0
	move_location = current_trigger.global_position + normal_from_trigger_2d * _distance_to_object
	move_location.y = player.global_position.y
	if player.phys.trace_blocked(move_location, player.global_position, player.collision_extent()):
		return false
	return true

func enter(_previous: StringName) -> void:
	player.set_grounded(true)
	event_delay = BUTTON_EVENT_DELAY
	_start_interact()

## StartInteract.
func _start_interact() -> void:
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	reached_trigger = false
	var to: Vector3 = move_location - player.global_position
	var walk_speed: float = float(clampi(int(Vector2(to.x, to.z).length() / UU / BUTTON_WALK_TIME),
		WALK_SPEED_MIN, WALK_SPEED_MAX)) * UU
	reset_camera_look(BUTTON_WALK_TIME)
	var face: Vector3 = -normal_from_trigger_2d
	set_precise_rotation(UE.dir_yaw(face), BUTTON_WALK_TIME)
	set_precise_location(move_location, walk_speed, PLM_WALK)

## ReachedPreciseLocationAndRotation: placed exactly, facing the button; the
## press; the event after event_delay; Walking 0.85 s on. Raised a second time
## (both halves arriving on one frame), it only holds the body still there.
func reached_precise_location_and_rotation() -> void:
	if reached_trigger:
		player.velocity = Vector3.ZERO
		player.global_position = move_location
		return
	reached_trigger = true
	abort_look_at_target()
	reset_camera_look(0.0)
	player.velocity = Vector3.ZERO
	player.acceleration = Vector3.ZERO
	# SetPhysics(PHYS_Flying) for the placement, then PHYS_Walking again: the
	# round trip drops the base and the SlideOffLedge timer.
	player.set_physics(PHYS_FLYING)
	player.global_position = move_location
	# The pawn faces the button, and the controller's yaw is set to the pawn's.
	var face: Vector3 = -normal_from_trigger_2d
	player.pawn_yaw = atan2(-face.x, -face.z)
	player.rotation.y = player.pawn_yaw
	player.set_physics(PHYS_WALKING)
	# PlayInteractAnimation: on the canned slot. [ME:CONFIRMED anims]
	play_slot_anim(&"interactbuttonhigh" if current_trigger.interact_type == UseZone.InteractType.BUTTON_HIGH \
		else &"interactbutton", 1.0, 0.2, 0.45, false, false, CustomAnimSlot.CNT_CANNED)
	player.set_ignore_look_input(-1.0)
	set_timer(0.85)
	set_move_timer(event_delay, false, _activate_first_output_link)

func _activate_first_output_link() -> void:
	if current_trigger != null and is_instance_valid(current_trigger):
		current_trigger.used.emit()

func on_timer() -> void:
	player.move_manager.set_move(WALKING)

## OnCustomAnimEnd: a button's animation over is Walking.
func on_custom_anim_end(_anim_name: StringName) -> void:
	player.move_manager.set_move(WALKING)

func exit() -> void:
	current_trigger = null
	reached_trigger = false

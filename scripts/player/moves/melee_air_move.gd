class_name MeleeAirMove
extends MeleeBaseMove

# The original's TdMove_MeleeAir, ported without combat. [ME:CONFIRMED
# decompile script TdMove_MeleeAir]
#
# The flying kick, from IntoGrab, Jump (not in its first 0.1 s), Falling,
# WallRunJump or GrabJump. Falling physics with the move input off. Faster than
# 200 uu/s across the ground it is MAT_FromJump: the view pulled down to
# -6000 over 0.2 s and MeleeInAir (0.567 s); slower it is MAT_FromJumpStill:
# the vertical speed zeroed on the spot and MeleeInAirStill (0.733 s). The
# animation's end is Falling.
#
# Landing a MAT_FromJump kick goes THROUGH Landing, below the hard-landing
# height as above it -- the script calls TdMove.Landed first, then sets
# Walking, which Landing has usually set already. So Landing's
# SubtractLandingSpeed runs on it like on any jump's landing (its condition
# names MeleeAir). Only a kick that already hit something would skip Landing,
# and nothing is ever hit here. A MAT_FromJumpStill kick's landing does
# nothing at all: the move stays MeleeAir on the ground until its animation
# ends and hands to Falling, which lands again.

const MAT_FROM_JUMP := 0
const MAT_FROM_JUMP_STILL := 1
const MAT_FROM_JUMP_HIGH := 2

var melee_type: int = MAT_FROM_JUMP
var has_received_landed_event: bool = false

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	# [ME:CONFIRMED decompile] DisableMovementTime = -1.
	disable_movement_time = -1.0

## TdMove_MeleeAir.CanDoMove. It also picks the kick's type -- a side effect
## of asking, as in the original.
func can_do_move() -> bool:
	var manager = player.move_manager
	var state: StringName = manager.current_name
	if state == JUMP:
		var jump: Move = manager.move_for(JUMP)
		if jump != null and jump.move_active_time < 0.1:
			return false
	match state:
		INTO_GRAB, JUMP, FALLING, WALLRUN_JUMP, GRAB_JUMP:
			melee_type = MAT_FROM_JUMP if Vector2(player.velocity.x, player.velocity.z).length() > 200.0 * UU \
				else MAT_FROM_JUMP_STILL
		_:
			return false
	return super.can_do_move()

func enter(previous: StringName) -> void:
	super.enter(previous)
	has_received_landed_event = false
	_trigger_move()

func _trigger_move() -> void:
	if melee_type == MAT_FROM_JUMP:
		set_look_at_target_angle(UE.pitch_units(cfg.look_at_pitch), UE.yaw_units(player.pawn_yaw), 0.2)
		play_move_anim(&"MeleeInAir", 1.0, 0.1, 0.2)
		hit_detection = true
	elif melee_type == MAT_FROM_JUMP_STILL:
		play_move_anim(&"MeleeInAirStill", 1.0, 0.1, 0.2)
		set_timer(0.25)
		player.velocity.y = 0.0

func on_timer() -> void:
	hit_detection = true

## TdMove_MeleeAir.Bump: an interactable bumped into takes the barge.
func bump(normal: Vector3, collider: Object) -> void:
	if not BargeMove.is_interactable(collider):
		return
	BargeMove.hit_object(player, collider, (collider as Node3D).global_position, -normal)
	hit_detection = false

func on_custom_anim_end(_anim_name: StringName) -> void:
	player.move_manager.set_move(FALLING)
	var falling: Move = player.move_manager.move_for(FALLING)
	if falling != null:
		falling.reset_camera_look(0.6)

func landed(normal: Vector3) -> void:
	has_received_landed_event = true
	if melee_type != MAT_FROM_JUMP:
		return
	var manager = player.move_manager
	var fall_height: float = player.enter_falling_height - player.collision_center().y
	var walking: Move = manager.move_for(WALKING)
	if hit_detection and fall_height < config.pawn.hard_landing_height:
		super.landed(normal)
		manager.set_move(WALKING)
		if walking != null:
			walking.reset_camera_look(0.4)
		play_move_anim(&"MeleeInAirLand2", 1.0, 0.3, 0.3)
		hit_detection = false
	elif hit_detection and fall_height >= config.pawn.hard_landing_height:
		hit_detection = false
		super.landed(normal)
	else:
		manager.set_move(WALKING)
		play_move_anim(&"MeleeInAirLand", 1.0, 0.1, 0.1)
		if walking != null:
			walking.reset_camera_look(0.2)

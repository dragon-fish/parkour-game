class_name MeleeCrouchMove
extends MeleeBaseMove

# The original's TdMove_MeleeCrouch, ported without combat. [ME:CONFIRMED
# decompile script TdMove_MeleeCrouch]
#
# The punch from a crouch: walking physics at a fifth of the speed, the small
# cylinder, the controller left as it was. MeleeCrouchStart (0.1 s), then with
# no target the miss, MeleeCrouchHit (0.467 s); then Walking where a standing
# body fits 30 uu up, Crouch where it does not. Against a wall it is only
# allowed with an interactable within 120 uu ahead.
#
# SetCameraPitchConstraints(-2000, 2000) is called on StartMove, but this move
# has no bConstrainLook, so it constrains nothing. Not ported.

func _init() -> void:
	super._init()
	# [ME:CONFIRMED decompile] bUseCustomCollision (Move.begin_move / end_move).
	use_custom_collision = true

func can_do_move() -> bool:
	if not super.can_do_move():
		return false
	if player.against_wall_state() != Player.AW_NONE:
		if BargeMove.find_barge_targets(player, cfg.barge_trace_distance).is_empty():
			return false
	return true

func enter(previous: StringName) -> void:
	super.enter(previous)
	hit_detection = false
	_trigger_move()

func _trigger_move() -> void:
	if melee_state == MS_ATTACK_FINISHING:
		play_move_anim(&"MeleeCrouchStartUpperCut", 1.0, 0.1, 1.0)
	else:
		play_move_anim(&"MeleeCrouchStart", 1.0, 0.1, -1.0, CustomAnimSlot.CNT_UPPER_BODY)

func on_custom_anim_end(_anim_name: StringName) -> void:
	match melee_state:
		MS_ATTACK_FINISHING, MS_ATTACK_NORMAL:
			# TestHit: no target, so whatever interactable is 120 uu ahead
			# takes the barge, and it is a miss.
			BargeMove.hit_all(player, BargeMove.find_barge_targets(player, cfg.barge_trace_distance))
			_trigger_miss()
		MS_HIT_FINISHING, MS_MISS_FINISHING, MS_MISS_NORMAL, MS_HIT_NORMAL:
			if player.can_stand(player.collision_center() + Vector3.UP * 30.0 * UU):
				player.move_manager.set_move(WALKING)
			else:
				player.move_manager.set_move(CROUCH)

func _trigger_miss() -> void:
	if melee_state == MS_ATTACK_FINISHING:
		play_move_anim(&"MeleeCrouchHitUppercut", 1.0, 0.1, 0.1)
	elif melee_state == MS_ATTACK_NORMAL:
		play_move_anim(&"MeleeCrouchHit", 1.0, 0.1, 0.2, CustomAnimSlot.CNT_UPPER_BODY)
	melee_state = MS_MISS_FINISHING if melee_state == MS_ATTACK_FINISHING else MS_MISS_NORMAL

## TdMove_MeleeCrouch.StopMove: the upper body fades out over 0.2 s.
func exit() -> void:
	player.anim_slot.stop(0.2, CustomAnimSlot.CNT_UPPER_BODY)

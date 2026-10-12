class_name MeleeSlideMove
extends MeleeBaseMove

# The original's TdMove_MeleeSlide, ported without combat. [ME:CONFIRMED
# decompile script TdMove_MeleeSlide]
#
# The kick out of a slide: walking physics on a tenth of the friction (with
# the slide's friction scales), the small cylinder, move and look input off,
# for the length of MeleeSlide (0.667 s); then Walking where a standing body
# fits, Crouch where it does not.
#
# Its StartMove tests MeleeState == MS_AttackFinishing for the slide-to-crouch
# lead-in, but MeleeBase.StartMove has just set MS_AttackNormal, so that branch
# never runs. The original's, kept.

## The original's 1P sequence lengths, seconds. [ME:CONFIRMED anims]
const CROUCH_SLIDE_TO_CROUCH_LENGTH := 0.5
const MELEE_SLIDE_LENGTH := 0.667
const MELEE_SLIDE_HARD_LENGTH := 0.733

var in_move: bool = false

func _init() -> void:
	super._init()
	# [ME:CONFIRMED decompile] bUseCustomCollision (Move.begin_move / end_move).
	use_custom_collision = true
	disable_movement_time = -1.0
	disable_look_time = -1.0

func enter(previous: StringName) -> void:
	super.enter(previous)
	hit_detection = false
	in_move = false
	timer = 0.0
	if melee_state == MS_ATTACK_FINISHING:
		play_move_anim(&"CrouchSlideToCrouch", CROUCH_SLIDE_TO_CROUCH_LENGTH)
		melee_state = MS_PENDING
	else:
		_trigger_move()

func _trigger_move() -> void:
	if melee_state == MS_ATTACK_FINISHING:
		play_move_anim(&"MeleeSlideHard", MELEE_SLIDE_HARD_LENGTH)
	else:
		play_move_anim(&"MeleeSlide", MELEE_SLIDE_LENGTH)
	in_move = true
	set_timer(0.2542)

func on_timer() -> void:
	hit_detection = true

func on_custom_anim_end(_anim_name: StringName) -> void:
	match melee_state:
		MS_PENDING:
			melee_state = MS_ATTACK_FINISHING
			_trigger_move()
		MS_ATTACK_FINISHING, MS_ATTACK_NORMAL, MS_HIT_FINISHING, MS_MISS_FINISHING:
			if player.can_stand(player.collision_center()):
				player.move_manager.set_move(WALKING)
			else:
				player.move_manager.set_move(CROUCH)

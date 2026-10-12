class_name MeleeMove
extends MeleeBaseMove

# The original's TdMove_Melee, ported without combat. [ME:CONFIRMED decompile
# script TdMove_Melee]
#
# The ground punch: walking physics, the controller left as it was (the body
# keeps running under it), the look held within +-10000 of level. Its timing is
# its animations: MeleeStart at 1.5x (0.111 s), then, with no target, the miss
# at 1.5x (0.378 s), then Walking. A press inside the 0.33 s window after each
# punch queues one more; a queued punch re-runs StartMove -- which zeroes the
# combo counters -- and is then counted down below zero, so of two presses in
# one window only the first is ever thrown. The original's, kept.

## [ME:CONFIRMED anims/moves_to_anims.md, ini] The punches play at 1.5x, the shove at 1;
## a miss blends in over BlendInMissed and out over BlendOutMissed (0.6 with a
## punch queued).
const PUNCH_RATE := 1.5
const BLEND_IN_MISSED := 0.08
const BLEND_OUT_MISSED := 0.1

## TdMove_Melee.EMoveMeleeType: only the two with no target.
const MT_NORMAL := 0
const MT_AT_COMBO_FINISHER := 3

## [ME:CONFIRMED decompile] TdMove_Melee.TriggerMove opens the combo window
## for 0.33 s.
const COMBO_WINDOW := 0.33
## Legs turned this far (4000 rotator units) from the body pick the side.
const LEGS_YAW_SIDE := 4000.0 * TAU / 65536.0

var is_left: bool = false
var window_open: bool = false
var combo_counter: int = 0
var combo_queued_actions: int = 0
var melee_type: int = MT_NORMAL

## TdMove_Melee.CanDoMove. PreventTime is never set without combat; a body
## with a hand against a wall cannot punch.
func can_do_move() -> bool:
	if not super.can_do_move():
		return false
	if player.against_wall_state() != Player.AW_NONE:
		return false
	return true

func enter(previous: StringName) -> void:
	super.enter(previous)
	_reset()
	# The legs' yaw against the body's picks the side; this project's body has
	# no separate leg rotation, so the punches alternate.
	var legs_body_yaw_delta: float = 0.0
	if melee_state == MS_ATTACK_NORMAL and absf(legs_body_yaw_delta) > LEGS_YAW_SIDE:
		is_left = legs_body_yaw_delta > 0.0
	else:
		is_left = not is_left
	_trigger_move()

## TdMove_Melee.StopMove: both slots fade out over 0.3 s.
func exit() -> void:
	super.exit()
	player.anim_slot.stop(0.3, CustomAnimSlot.CNT_UPPER_BODY)
	player.anim_slot.stop(0.3)
	_reset()

## A punch pressed inside the window is queued, at most two.
func handle_move_action(action: int) -> void:
	if action != MA_MELEE or not window_open:
		return
	if combo_counter < 2:
		combo_counter += 1
		combo_queued_actions += 1

func _open_window(seconds: float) -> void:
	set_timer(seconds)
	window_open = true

func _close_window() -> void:
	timer = 0.0
	window_open = false

func on_timer() -> void:
	_close_window()

func _reset() -> void:
	combo_counter = 0
	combo_queued_actions = 0
	_close_window()

func on_custom_anim_end(_anim_name: StringName) -> void:
	match melee_state:
		MS_ATTACK_NORMAL, MS_ATTACK_FINISHING:
			# TestHit: no target, a miss.
			_trigger_miss()
		MS_HIT_NORMAL, MS_HIT_FINISHING, MS_MISS_NORMAL, MS_MISS_FINISHING:
			if combo_queued_actions > 0:
				restart_move()
				combo_queued_actions -= 1
				is_left = not is_left
				_trigger_move()
			else:
				player.move_manager.set_move(WALKING)

func _trigger_move() -> void:
	_open_window(COMBO_WINDOW)
	if combo_queued_actions == 0 and combo_counter == 2:
		melee_type = MT_AT_COMBO_FINISHER
		play_move_anim(&"MeleeStartShove", 1.0, 0.1, -1.0, CustomAnimSlot.CNT_UPPER_BODY)
		player.set_ignore_move_input(1.0)
	else:
		melee_type = MT_NORMAL
		play_move_anim(&"MeleeStartLeft" if is_left else &"MeleeStartRight", PUNCH_RATE, 0.1, -1.0,
			CustomAnimSlot.CNT_UPPER_BODY)

func _trigger_miss() -> void:
	match melee_type:
		MT_NORMAL:
			play_move_anim(&"MeleeMissedLeft" if is_left else &"MeleeMissedRight", PUNCH_RATE, BLEND_IN_MISSED,
				0.6 if combo_queued_actions > 0 else BLEND_OUT_MISSED, CustomAnimSlot.CNT_UPPER_BODY)
		MT_AT_COMBO_FINISHER:
			play_move_anim(&"MeleeHitShove", 1.0, 0.0, 0.1, CustomAnimSlot.CNT_UPPER_BODY)
			_reset()
	melee_state = MS_MISS_NORMAL if melee_state == MS_ATTACK_NORMAL else MS_MISS_FINISHING

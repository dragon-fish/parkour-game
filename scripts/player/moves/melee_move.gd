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

## The original's 1P sequence lengths, seconds. [ME:CONFIRMED anims]
const START_LENGTH := 0.167
const START_SHOVE_LENGTH := 0.133
const MISSED_LENGTH := 0.567
const HIT_SHOVE_LENGTH := 0.567
## The punches play at 1.5x; the shove at 1.
const PUNCH_RATE := 1.5

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

func exit() -> void:
	super.exit()
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
		play_move_anim(&"MeleeStartShove", START_SHOVE_LENGTH)
		player.set_ignore_move_input(1.0)
	else:
		melee_type = MT_NORMAL
		play_move_anim(&"MeleeStartLeft" if is_left else &"MeleeStartRight", START_LENGTH, PUNCH_RATE)

func _trigger_miss() -> void:
	match melee_type:
		MT_NORMAL:
			play_move_anim(&"MeleeMissedLeft" if is_left else &"MeleeMissedRight", MISSED_LENGTH, PUNCH_RATE)
		MT_AT_COMBO_FINISHER:
			play_move_anim(&"MeleeHitShove", HIT_SHOVE_LENGTH)
			_reset()
	melee_state = MS_MISS_NORMAL if melee_state == MS_ATTACK_NORMAL else MS_MISS_FINISHING

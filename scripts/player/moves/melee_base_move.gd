class_name MeleeBaseMove
extends PhysicsMove

# The original's TdMove_MeleeBase, as far as movement goes. [ME:CONFIRMED
# decompile script TdMove_MeleeBase, N5 §21]
#
# This project has no combat: no target is ever acquired (GetMeleeTarget finds
# none), the hit detection traces for pawns and finds none, and no damage is
# dealt. What is ported is what moves the body or times the move: each
# subclass's own physics, input and look changes, and the animation ends that
# hand the body on -- every subclass taking the branch the original takes with
# no target.

## TdMove_MeleeBase.EMeleeState.
const MS_PENDING := 0
const MS_ATTACK_NORMAL := 1
const MS_ATTACK_FINISHING := 2
const MS_HIT_NORMAL := 3
const MS_HIT_FINISHING := 4
const MS_MISS_NORMAL := 5
const MS_MISS_FINISHING := 6

## [ME:CONFIRMED decompile] CanDoMoveTaserLimit: refused below this mobility.
const CAN_DO_MOVE_TASER_LIMIT := 0.8

var melee_state: int = MS_PENDING
## bHitDetection: only ever read by the hit trace, which finds nothing here;
## kept because the original's landing and vault branches test it.
var hit_detection: bool = false

var _anim := MoveAnim.new()

func is_ported() -> bool:
	return true

## TdMove_MeleeBase.CanDoMove. The weapon-animation states it also refuses
## never occur without weapons.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	if player.mobility_multiplier() < CAN_DO_MOVE_TASER_LIMIT:
		return false
	return true

## TdMove_MeleeBase.StartMove.
func enter(_previous: StringName) -> void:
	melee_state = MS_ATTACK_NORMAL

## TdMove_MeleeBase.StopMove: the custom animations stop.
func exit() -> void:
	_anim.stop()

## PlayMoveAnim, for the timing: see MoveAnim.
func play_move_anim(anim: StringName, length_1p: float, rate: float = 1.0) -> void:
	_anim.play(anim, length_1p, rate)

## The base TickMove, then the animation: an end that this move is still
## waiting for is OnCustomAnimEnd.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	var ended: StringName = _anim.advance(delta)
	if ended != &"":
		on_custom_anim_end(ended)

func on_custom_anim_end(_anim_name: StringName) -> void:
	pass

## Re-runs StartMove on the move already current, as the original's
## StartMove() called from inside the move does: the common half, then this
## move's own.
func restart_move() -> void:
	begin_move()
	enter(player.old_movement_state)

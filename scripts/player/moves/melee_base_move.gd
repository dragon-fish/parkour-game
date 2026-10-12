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

func _init() -> void:
	super._init()
	movement_group = MG_NON_INTERACTIVE

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

## PlayMoveAnim, on the pawn's slot `node` with the original's rate and
## blends (Move.play_slot_anim()); its end comes back as OnCustomAnimEnd.
func play_move_anim(anim: StringName, rate: float, blend_in: float, blend_out: float,
		node: int = CustomAnimSlot.CNT_FULL_BODY) -> void:
	play_slot_anim(anim, rate, blend_in, blend_out, false, false, node)

## Re-runs StartMove on the move already current, as the original's
## StartMove() called from inside the move does: the common half, then this
## move's own.
func restart_move() -> void:
	begin_move()
	enter(player.old_movement_state)

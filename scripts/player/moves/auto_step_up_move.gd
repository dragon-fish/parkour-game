class_name AutoStepUpMove
extends PhysicsMove

# The original's TdMove_AutoStepUp (MOVE_AutoStepUp 81). [ME:CONFIRMED
# decompile script TdMove_AutoStepUp.uc, script_raw checked]
#
# DEAD in the shipped game: CanDoMove returns false straight after TdMove's
# own checks, ahead of its whole planning. CheckAutoMoves still asks it first
# whenever a top was found under bCheckForVaultOver, so it is registered and
# asked, and always refuses; VaultOver is what answers. Its StartMove and the
# rest can never run and are not ported. DO NOT "repair" the early return: the
# low step-ups it would have given are the vault table's autostepuprightleg
# row.

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FLYING
	disable_collision = true
	disable_movement_time = -1.0
	disable_look_time = -1.0

func is_ported() -> bool:
	return true

## TdMove_AutoStepUp.CanDoMove: TdMove's checks, then false.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	return false

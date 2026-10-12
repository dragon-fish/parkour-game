class_name JumpConfig
extends MoveConfig

# The original's TdMove_Jump defaults (CDO and DefaultPawnMovement.ini). The
# take-off numbers, BaseJumpZ and JumpAddXY, are PawnConfig's.

func _init() -> void:
	# [ME:CONFIRMED decompile, ini] bCheckForGrab, bCheckForVaultOver and
	# bCheckForWallClimb all set: the only airborne move without the last one
	# is Falling, which is the whole rule against a long drop turning into a
	# wall run.
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	# The level's interest points, asked with the switches above (see
	# PhysicsMove.check_auto_moves()).
	check_for_ladder = true
	check_for_ledge_walk = true
	check_for_balance = true
	# [ME:CONFIRMED decompile, ini] RedoMoveTime = 0: neither
	# [TdGame.TdMove_Jump] nor TdMove_Jump's defaultproperties set it, so Jump
	# keeps [TdGame.TdMove]'s 0 and a second jump is allowed the moment the
	# body is back on its feet. DO NOT put a cooldown here.
	redo_move_time = 0.0

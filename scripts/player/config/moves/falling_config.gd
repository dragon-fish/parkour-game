class_name FallingConfig
extends MoveConfig

# The original's TdMove_Falling defaults (CDO and DefaultPawnMovement.ini).

func _init() -> void:
	# [ME:CONFIRMED decompile, ini] bCheckForGrab and bCheckForVaultOver set,
	# bCheckForWallClimb clear. That single absence is the whole rule against
	# a long drop converting into a wall run.
	check_for_grab = true
	check_for_vault_over = true

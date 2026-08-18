class_name FallingConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Falling. No fields of its
# own yet -- air control still reads straight off PawnConfig -- so this class
# exists purely to give Falling a slot in MovementConfig that matches every
# other move's own layering.

func _init() -> void:
	# Source: 05 §5.7 ③'s table -- `TdMove_Falling` (descending) has
	# `bCheckForGrab` / `bCheckForVaultOver` set but `bCheckForWallClimb`
	# clear. ✅ for all three: this is also where autostepuprightleg's
	# falling-only band (MinSpeedZ/MaxSpeedZ -6.0..0.0) actually becomes
	# reachable -- see SpeedVaultConfig.variants' own note on that row, and
	# FallingMove's own comment on why the vault check runs before the ledge
	# grab it falls back to.
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = false

class_name JumpConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Jump. No fields of its own
# yet -- jump take-off still reads straight off PawnConfig's base_jump_z/
# jump_add_xy -- so this class exists purely to give Jump a slot in
# MovementConfig that matches every other move's own layering.

func _init() -> void:
	# Source: 05 §5.7 ③'s table -- `TdMove_Jump` (rising) has
	# `bCheckForGrab` / `bCheckForVaultOver` / `bCheckForWallClimb` all set.
	# ✅ for Grab/VaultOver (this project's FallingMove reads both while
	# rising, via current_config() picking this config over FallingConfig's).
	# check_for_wall_climb is recorded for parity with the source table only
	# -- this project has no wall-climb move (wall running is a different,
	# already-implemented mechanic), so nothing reads it.
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true

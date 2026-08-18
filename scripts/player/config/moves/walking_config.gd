class_name WalkingConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Walking. No fields of its
# own yet -- ground locomotion still reads straight off PawnConfig -- so this
# class exists purely to give Walking a slot in MovementConfig that matches
# every other move's own layering.

func _init() -> void:
	# Source: 06 §6.2 `bCheckForVaultOver` on TdMove_Walking. ✅ A grounded run
	# is where the whole vault table lives (05 §5.7): WalkingMove is the move
	# that actually earns most of the six variants (the sweet spot and the
	# slow climb both fire from here), so its own probe switch is on.
	check_for_vault_over = true

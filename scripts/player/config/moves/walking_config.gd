class_name WalkingConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Walking. No fields of its
# own yet -- ground locomotion still reads straight off PawnConfig -- so this
# class exists purely to give Walking a slot in MovementConfig that matches
# every other move's own layering.

func _init() -> void:
	# NO PROBES AT ALL, and this is confirmed rather than inferred.
	# TdMove_Walking's entire CDO is six fields:
	#
	#     ControllerState PlayerWalking / bShouldUnzoom / bUseCameraCollision
	#     bEnableFootPlacement / bEnableAgainstWall / bAllowPickup
	#
	# Not one bCheckFor*. Walking does not vault, does not grab and does not
	# climb: every upward move in the original starts from a launch or a fall,
	# which is why all twelve states holding bCheckForVaultOver are airborne
	# (11 §11.2).
	#
	# DO NOT set check_for_vault_over here: "06 §6.2 bCheckForVaultOver on
	# TdMove_Walking" is a misreading -- that section is a table explaining
	# what the FIELDS mean, not a list of which moves carry them. Enabling it
	# vaults the player automatically while simply running past a crate. In
	# the original, nothing goes upward unless the player asks for it.
	check_for_vault_over = false

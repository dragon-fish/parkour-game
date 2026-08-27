class_name JumpConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Jump. No fields of its own
# yet -- jump take-off still reads straight off PawnConfig's base_jump_z/
# jump_add_xy -- so this class exists purely to give Jump a slot in
# MovementConfig that matches every other move's own layering.

func _init() -> void:
	# [ME:CONFIRMED 05 §5.7 ③] TdMove_Jump (rising) has bCheckForGrab /
	# bCheckForVaultOver / bCheckForWallClimb all set. JumpMove is a real
	# state now (AirborneMove's own subclass), and
	# AirborneMove.probe_transition() reads check_for_wall_climb directly to
	# gate WALL_RUN entry -- this is the ONLY thing that distinguishes
	# JumpConfig from FallingConfig (see FallingConfig's own note on that
	# absence).
	check_for_grab = true
	check_for_vault_over = true
	check_for_wall_climb = true
	check_for_zipline = true
	check_for_swing = true
	check_for_ladder = true

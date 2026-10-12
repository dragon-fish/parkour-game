class_name MeleeConfig
extends MoveConfig

# The original's TdMove_Melee: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Melee]. Damage values are not ported: this project has no
# combat.

func _init() -> void:
	# [ME:CONFIRMED decompile] bConstrainLook: pitch -10000 .. 10000, yaw and
	# roll a full turn.
	constrain_look = true
	min_look_constraint = Vector3(-10000.0, -32768.0, -32768.0) * (TAU / 65536.0)
	max_look_constraint = Vector3(10000.0, 32768.0, 32768.0) * (TAU / 65536.0)

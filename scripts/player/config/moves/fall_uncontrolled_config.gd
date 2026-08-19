class_name FallUncontrolledConfig
extends MoveConfig

# The original's TdMove_FallingUncontrolled. ✅ Its CDO carries exactly one
# check -- bCheckForSoftLanding -- and ControllerState = PlayerDying. Every
# other probe is absent, which is what makes the outcome inevitable rather
# than merely likely (11 §11.2).

func _init() -> void:
	check_for_grab = false
	check_for_vault_over = false
	check_for_wall_climb = false

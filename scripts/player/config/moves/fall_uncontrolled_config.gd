class_name FallUncontrolledConfig
extends MoveConfig

# The original's TdMove_FallingUncontrolled. ✅ Its CDO carries exactly one
# check -- bCheckForSoftLanding -- and ControllerState = PlayerDying. Every
# other probe is absent, which is what makes the outcome inevitable rather
# than merely likely (11 §11.2).

## How much of the fall's own intensity reaches BLUR, where desaturation gets
## all of it. See FallUncontrolledMove._drive_screen_effects() for what drives
## both.
##
## ⚠️ PROJECT-DEFINED, whole cloth -- and so is the effect it scales. The
## original plays a cutscene on impact and its data says nothing whatsoever
## about the descent, so there is no source value to read this off. It exists
## because spec §6 asks for losing control to be VISIBLE while it is
## happening, not only once the body has landed.
##
## Blur is deliberately the quieter of the two: desaturation says "this is no
## longer your fall" without costing legibility, while blur at the same
## strength only makes the approaching ground harder to read. The outcome is
## already settled by this point, but the player should still get to watch it
## arrive.
@export var blur_scale: float = 0.6

func _init() -> void:
	check_for_grab = false
	check_for_vault_over = false
	check_for_wall_climb = false

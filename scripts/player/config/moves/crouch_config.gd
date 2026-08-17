class_name CrouchConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Crouch.

## Capsule height while standing-crouched. Shares a number with
## SlideConfig.slide_capsule_height without sharing a variable: a slide that
## decays into a crouch under a low roof must not visibly pop, but the two
## stay independently tunable.
@export var crouch_capsule_height: float = 0.9

func _init() -> void:
	# Source: 02 §2.3 / 03 §3.4 `CrouchedPct = 0.4`. ✅ Chosen over
	# 05 §5.8's `TdMove_Crouch.SpeedModifier = 0.2`: CrouchedPct is
	# independently confirmed and explained in two separate sections, while
	# 0.2 appears once in a bare parameter dump with no narrative.
	speed_modifier = 0.4

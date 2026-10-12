class_name FallUncontrolledConfig
extends MoveConfig

# The original's TdMove_FallingUncontrolled: PawnPhysics, ControllerState
# PlayerDying and bCheckForSoftLanding, nothing else. [ME:CONFIRMED decompile
# N5 §7] No look constraint either: the view stops because the UncontrolledFall
# state ignores look input.

## How much of the fall's own intensity reaches BLUR, where desaturation gets
## all of it. PROJECT-DEFINED presentation: nothing in the original describes
## the descent's picture.
@export var blur_scale: float = 0.6

func _init() -> void:
	allows_turn = false

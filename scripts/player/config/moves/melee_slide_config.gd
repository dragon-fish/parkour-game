class_name MeleeSlideConfig
extends MoveConfig

# The original's TdMove_MeleeSlide: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_MeleeSlide].

func _init() -> void:
	# [ME:CONFIRMED ini] FrictionModifier = 0.1, with the walking physics'
	# slide friction scales (PawnPhysics).
	friction_modifier = 0.1

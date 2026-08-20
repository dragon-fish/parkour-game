class_name IntoGrabConfig
extends MoveConfig

# The original's TdMove_IntoGrab: the reach between catching a ledge and
# hanging from it. This project used to go straight to Grab, which is why the
# body hung wherever it happened to make contact -- sometimes a long way out
# from the wall, sometimes barely below the lip.
#
# The CDO explains the manoeuvre's most visible property. There is no animation
# LENGTH anywhere in it, only an alignment SPEED: the body is carried to a
# fixed hanging pose at a fixed rate, so the further it has to travel, the
# longer the reach takes. That is why a high ledge caught at a bad moment
# visibly takes longer to settle onto than a low one caught cleanly -- the
# duration is a consequence, not a setting.

func _init() -> void:
	# ✅ TdMove_IntoGrab: bCheckForVaultOver is set, so a reach can still turn
	# into a vault if the geometry turns out to suit one better.
	check_for_vault_over = true

## ✅ `IntoGrabAlignSpeed = 300` uu/s. The rate the body is carried to the
## hanging pose at.
@export var align_speed: float = 3.0

## ✅ `GrabDesiredLedgeOffset = (30.0, 0.0, 92.8)` uu, converted: the body
## settles 0.30 m back from the edge and 0.928 m below it.
##
## The vertical figure is the one that matters most in play -- it is what makes
## every hang look the same regardless of how the ledge was caught.
@export var ledge_back_offset: float = 0.30
@export var ledge_down_offset: float = 0.928

## ✅ `MinGrabLedgeAdjustDistance = 32` uu. Below this the body is already close
## enough; snapping the last three centimetres is invisible and saves a frame
## of drift.
@export var min_adjust_distance: float = 0.32

## ⚠️ PROJECT-DEFINED SAFETY VALVE. The reach cannot run forever: if something
## prevents the body ever arriving, it gives up and falls rather than hanging
## in the air being aligned.
##
## Generous relative to the real case -- the longest legitimate reach is
## roughly ledge_max_height over align_speed, under a second.
@export var max_duration: float = 1.5

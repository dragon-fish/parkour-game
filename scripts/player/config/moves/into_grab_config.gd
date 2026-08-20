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

## From `GrabDesiredLedgeOffset = (30.0, 0.0, 92.8)` uu, but only the vertical
## figure is taken literally.
##
## THE HORIZONTAL ONE CANNOT BE A BODY-CENTRE OFFSET. 30 uu is 0.30 m, and this
## project's capsule has a radius of 0.40 m: settling a centre that close to the
## edge would bury a tenth of a metre of the body in the wall. Whatever the
## original measures it from -- the hands, the collision hull's face, some
## anchor on the animation -- it is not the middle of the pawn.
##
## ⚠️ So this is derived rather than copied: one capsule radius, plus a little,
## which is the closest the body can hang without intersecting the wall it is
## hanging on. The vertical figure needs no such adjustment and is used as-is:
## it is what makes every hang settle into the same pose however it was caught.
@export var ledge_back_offset: float = 0.45
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

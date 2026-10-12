class_name AirBargeConfig
extends BargeConfig

# The original's TdMove_AirBarge: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_AirBarge], over TdMove_Barge's.

func _init() -> void:
	super._init()
	min_trace_distance = 3.0

## [ME:CONFIRMED ini] TotalHeightBoost = 60 uu over HeightBoostDuration =
## 0.25 s: the same 240 uu/s lift a coil gets.
@export var height_boost_duration: float = 0.25
@export var total_height_boost: float = 0.6

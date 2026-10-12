class_name BargeConfig
extends MoveConfig

# The original's TdMove_Barge: CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_Barge]. Lengths in metres, speeds in m/s.

func _init() -> void:
	# [ME:CONFIRMED ini] RedoMoveTime = 0.1.
	redo_move_time = 0.1
	# [ME:CONFIRMED decompile] bConstrainLook: pitch -14000 .. 16384, yaw
	# -5000 .. 5000 about the pawn, which bDisableFaceRotation holds still --
	# so the fan is pinned where the barge began, and the model does not turn.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-14000.0, -5000.0, -32768.0) * (TAU / 65536.0)
	max_look_constraint = Vector3(16384.0, 5000.0, 32768.0) * (TAU / 65536.0)

## [ME:CONFIRMED ini] BargeMinTraceDistance = 90 uu: how far ahead an
## interactable is looked for when not running at it.
@export var min_trace_distance: float = 0.9
## [ME:CONFIRMED ini] BargeTraceTime = 0.5 s: running at it, the look ahead is
## half a second at the barge speed, and the shoulder barge aims that far.
@export var trace_time: float = 0.5
## [ME:CONFIRMED ini] BargeAddOnSpeed = 200 uu/s and BargeMaxSpeed = 500 uu/s:
## the barge speed is min(max, |V.xy| + add).
@export var add_on_speed: float = 2.0
@export var max_speed: float = 5.0
## [ME:CONFIRMED ini] BargeKickThresholdSpeed = 250 uu/s: slower, or not
## running at it, the door is kicked instead of shouldered.
@export var kick_threshold_speed: float = 2.5
## [ME:CONFIRMED decompile] BargeAnimTime = 0.3 s: the shoulder's animation
## rate is this over the time to the door, clamped to 0.7 .. 1.3.
@export var anim_time: float = 0.3

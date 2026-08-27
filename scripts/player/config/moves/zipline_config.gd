class_name ZiplineConfig
extends MoveConfig

# The original's TdMove_ZipLine + TdMove_IntoZipLine. [ME:CONFIRMED 05 §5.5]
# two LOWER bounds and no upper one -- a long enough cable runs to tens of
# km/h, which the owner has seen exceed 80 km/h in the original.

func _init() -> void:
	allows_turn = false  # both hands on the cable
	# The view may swing either way across the cable but the body keeps its
	# heading (bDisableFaceRotation). Same machinery Grab uses.
	constrain_look = true
	absolute_yaw_constraint = true
	freeze_visual_yaw = true
	min_look_constraint = Vector3(-deg_to_rad(80.0), -deg_to_rad(90.0), -PI)
	max_look_constraint = Vector3(deg_to_rad(80.0), deg_to_rad(90.0), PI)
	# NO move-name cooldown: [ME:INFERRED] the original chains rope to rope
	# (owner-measured: release one, catch the next at once), so the re-catch
	# guard is per CABLE -- see same_line_redo_time below and
	# Player.note_line_left().
	redo_move_time = 0.0

## [ME:CONFIRMED 05 §5.5] OWNER-MEASURED floor, repeatedly: 14.36 km/h =
## 3.99 m/s -- which is 400 uu/s to within 0.3%, the SAME 400 the slope gain
## fits. Two fitted constants landing on MinZipAcceleration's literal value
## suggests the CDO pair (MinZipVelocity 300 / MinZipAcceleration 400) does
## not mean what the field names say; whatever the truth, the measurement is
## what ships. Boarding slower than this is raised to it.
@export var min_velocity: float = 3.99
## [ME:CONFIRMED 05 §5.5] OWNER-MEASURED, two reference segments:
##
##     61 m at ~19 deg (sin 0.326): 14 -> 63 km/h in ~5 s    a = 2.72
##     97 m at ~8 deg  (sin 0.139): 14 -> 67 km/h in ~7.5 s  a = 1.96
##
## Linear in the slope: a = base + gain * sin(theta), fitting base 1.39 and
## gain 4.07. [ME:DERIVED] gain (4.07) matches the CDO's MinZipAcceleration
## (400 uu/s^2 -> 4.0 m/s^2) to within 2%, which is very likely that field's
## real role: the slope coefficient, not a floor. A single-segment reading
## reads as a constant ~10 km/h/s and cannot separate the two terms; the
## second segment does.
@export var base_acceleration: float = 1.4
@export var slope_acceleration: float = 4.0
## [ME:CONFIRMED 05 §5.5] HangOffset = (0, 0, -90): the body centre hangs
## this far below the cable.
@export var hang_offset: float = 0.9
## [ME:CONFIRMED 05 §5.5] ZipFadeInTime = 0.1 s: how long the body takes to
## reach the hang point from wherever it caught the cable.
@export var fade_in_time: float = 0.1
## [ME:CONFIRMED 05 §5.5] TdMove_IntoZipLine.ZVelocityFallLimit = -600:
## falling faster than this (m/s, positive) the hands cannot hold on.
@export var fall_limit: float = 6.0

## [ME:CONFIRMED 05 §5.5] SameZipLineRedoMoveTime = 3.0 -- and the owner's
## rope-chaining measurement confirms the SAME-line reading: this guards
## re-catching the cable just left, never the next one. Enforced per line by
## Player.
@export var same_line_redo_time: float = 3.0

## PROJECT-DEFINED, no CDO source. Widest horizontal angle, in degrees,
## between the approach velocity and the ride's travel direction that still
## catches. DO NOT let a jump straight against the cable's direction trigger
## a catch: 100 refuses only a clearly opposed approach -- a perpendicular
## crossing under the cable still catches. Degrees, so the F1 panel reads
## naturally. Tuned by feel.
@export var catch_max_approach_angle: float = 100.0

class_name IntoGrabConfig
extends MoveConfig

# The original's TdMove_IntoGrab, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_IntoGrab]. [ME:CONFIRMED decompile] Metric. What each value
# does is in IntoGrabMove.

@export_group("Native gate")
## IntoGrabMaxAngle, 70 degrees: the pawn's facing against the wall.
@export var into_grab_max_angle: float = deg_to_rad(70.0)
## IntoGrabMinInitialAlignSpeed, -3000 uu/s: the speed into the wall.
@export var into_grab_min_initial_align_speed: float = -30.0
## GrabMinGrabableZNormal, 0.707: the steepest top a hand holds.
@export var grab_min_grabable_z_normal: float = 0.707
## IntoGrabMaxDistance, 200 uu, scaled by 0.4 .. 1 with the speed toward the
## hang point (full at 200 uu/s).
@export var into_grab_max_distance: float = 2.0

@export_group("Reach")
## IntoGrabAlignSpeed, 300 uu/s: the least horizontal speed of the reach.
@export var into_grab_align_speed: float = 3.0
## GrabDesiredLedgeOffset (30, 0, 92.8) uu, as Grab has it.
@export var grab_desired_ledge_offset_z: float = 0.928
## MinGrabLedgeAdjustDistance, 32 uu: the reach re-aims at a ledge found again
## only while the body is further than this from the hang point.
@export var min_grab_ledge_adjust_distance: float = 0.32

@export_group("Catch")
## HangImpactMinZSpeed -600 / HangHardImpactMinZSpeed -1000 uu/s: a catch
## falling faster plays the harder starts; the hardest bars the pull-up for 1 s.
@export var hang_impact_min_z_speed: float = -6.0
## HangHardImpactMinZSpeed.
@export var hang_hard_impact_min_z_speed: float = -10.0

@export_group("Folded hang")
## HangFoldedIntoGrabZSpeedThreshold 150, HangFoldedIntoGrabSpeed2DThreshold
## 50, HangFoldedUpperDeltaDistance 35, HangFoldedLowerDeltaDistance 70,
## HangFoldedMaxDistance 60, HangFoldedDownwardSpeedLimit -300 uu(/s).
@export var hang_folded_into_grab_z_speed_threshold: float = 1.5
@export var hang_folded_into_grab_speed_2d_threshold: float = 0.5
@export var hang_folded_upper_delta_distance: float = 0.35
@export var hang_folded_lower_delta_distance: float = 0.70
@export var hang_folded_max_distance: float = 0.60
@export var hang_folded_downward_speed_limit: float = -3.0

func _init() -> void:
	# This project's hook: the torus wrap waits while the move holds a world
	# position.
	holds_world_path = true
	# Set by the ini; unused, since IntoGrab's own CheckAutoMoves replaces the
	# base's.
	check_for_vault_over = true

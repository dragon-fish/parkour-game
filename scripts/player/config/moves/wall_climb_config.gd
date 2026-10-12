class_name WallClimbConfig
extends MoveConfig

# The original's TdMove_WallClimb, CDO and DefaultPawnMovement.ini
# [TdGame.TdMove_WallClimb]. [ME:CONFIRMED decompile] Metric. What each value
# does is in WallClimbMove and PawnPhysics.phys_wall_climbing.
#
# The climb's rise is AddOnHeight, reached exactly: the climb's velocity
# change is doubled at the end of every physics frame, so its gravity is
# effectively 2 x WallClimbingGravity and its horizontal friction 2 x 6, and
# the launch speed sqrt(4 h g) is the one that tops out at h under 2 g.

@export_group("Entry")
## WallClimbingVerticalStartAngle, 33 degrees: the CAMERA's flat direction
## must be within this of straight into the wall.
@export var wall_climbing_vertical_start_angle: float = deg_to_rad(33.0)
## WallClimbingMaxDistance2D, 120 uu: from the body to the hand-plant point.
@export var wall_climbing_max_distance_2d: float = 1.2
## WallClimbingVelocityStartLimit, 0: the horizontal speed floor.
@export var wall_climbing_velocity_start_limit: float = 0.0
## MinWallHeight, 180 uu: a top found lower than this above the feet is not a
## wall to climb. Also the height Probes.wall_ahead_query() measures against.
@export var min_wall_height: float = 1.8

@export_group("Climb")
## AddOnSpeed2DHeight up to AddOnSpeed2DMaxLimit: 60 uu more rise for an
## approach of 400 .. 650 uu/s (after JumpAddXY is taken off).
@export var add_on_speed_2d_height: float = 0.6
@export var add_on_speed_2d_max_limit: float = 6.5
## AddOnSpeedZHeight up to AddOnSpeedZMaxLimit: 130 uu more rise for a vertical
## speed of 0 .. 320 uu/s at contact.
@export var add_on_speed_z_height: float = 1.3
@export var add_on_speed_z_max_limit: float = 3.2
## WallClimbingGravity, 800 uu/s^2, once the wall is reached; before it, the
## world's.
@export var wall_climbing_gravity: float = 8.0
## WallClimbingVerticalFriction, 6 /s: on the horizontal only.
@export var wall_climbing_vertical_friction: float = 6.0
## MinUpwardsVelocityToDoubleJump, 100 uu/s: the hand plant's second kick
## comes once the rise has slowed below this.
@export var min_upwards_velocity_to_double_jump: float = 1.0

@export_group("Probes")
## How far ahead Probes.wall_ahead_query() looks for a wall to kick up, metres.
## This project's probe, read by the debug overlays only -- not by WallClimb,
## whose entry is the original's hand-plant search.
@export var check_distance: float = 0.6

func _init() -> void:
	check_for_grab = true
	check_for_vault_over = true
	friction_modifier = 0.3

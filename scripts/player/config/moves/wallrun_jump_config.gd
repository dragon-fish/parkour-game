class_name WallrunJumpConfig
extends MoveConfig

# Source: 04 §4.4 `TdMove_WallrunJump` CDO. ✅ ALL FOUR CONFIRMED.
#
# DICE wrote the skill gradient into the parameter names themselves -- Noob
# and ProAdd -- which is the single most important finding in the whole
# research: the same key produces a 4.3x spread depending on how well it is
# executed, with no extra input, no QTE and no tutorial. The community called
# this "wall boost" for years and never knew why it worked.

## `WallRunningPushAwaySpeedNoob = 120` uu/s -- worst execution.
@export var wall_running_push_away_speed_noob: float = 1.2
## `WallRunningPushAwaySpeedProAdd = 400` uu/s -- added on top at best
## execution, for 520 uu/s = 5.2 m/s total.
@export var wall_running_push_away_speed_pro_add: float = 4.0
## `WallRunningPushForwardSpeedMin = 0.1`. ✅
@export var wall_running_push_forward_speed_min: float = 0.1
## `WallRunningJumpOffZHeightForward = 100` uu -- a HEIGHT (1.0 m), converted
## to a launch speed at the point of use.
@export var wall_running_jump_off_z_height_forward: float = 1.0
## `WallRunningJumpOffZHeightMaxAddTurned = 60` uu -- up to 0.6 m more.
@export var wall_running_jump_off_z_height_max_add_turned: float = 0.6

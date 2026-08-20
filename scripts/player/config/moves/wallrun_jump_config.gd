class_name WallrunJumpConfig
extends MoveConfig

# Source: 04 §4.4 `TdMove_WallrunJump` CDO. ✅ ALL FOUR CONFIRMED.
#
# DICE wrote the skill gradient into the parameter names themselves -- Noob
# and ProAdd -- which is the single most important finding in the whole
# research: the same key produces a 4.3x spread depending on how well it is
# executed, with no extra input, no QTE and no tutorial. The community called
# this "wall boost" for years and never knew why it worked.

## Worst execution -- looking away from the wall at the moment of the jump.
## Source: 04 §4.4 `WallRunningPushAwaySpeedNoob = 120` uu/s. ✅
@export var wall_running_push_away_speed_noob: float = 1.2
## Added on top of the Noob push at best execution -- looking straight into
## the wall -- for 520 uu/s = 5.2 m/s total.
## Source: 04 §4.4 `WallRunningPushAwaySpeedProAdd = 400` uu/s. ✅
@export var wall_running_push_away_speed_pro_add: float = 4.0
## Source: 04 §4.4 `WallRunningPushForwardSpeedMin = 0.1`. ✅ as a value,
## ❓ as a role -- the research never established what "push forward" is
## measured against, and nothing reads it. Recorded so the number is not lost.
## The look-direction kick below is expressed by wall_jump_min_away instead,
## which is honestly project-defined rather than pretending to be this field.
@export var wall_running_push_forward_speed_min: float = 0.1

## ⚠️ PROJECT-DEFINED, no confirmed counterpart. How much of the kick must
## point away from the wall, as a fraction of the push, regardless of where
## the player is looking.
##
## The kick otherwise follows the VIEW: measured in the original, Faith leaves
## the wall in the direction the camera faces rather than straight along the
## surface normal, and the sideways component is small. Sending the push along
## the normal alone -- which is what this used to do -- makes a wall kick a
## fixed sideways shove that the player cannot aim, which is the opposite of
## how the technique reads in play.
##
## 0.35 is roughly 20 degrees off the wall. Low enough that the view genuinely
## steers the kick, high enough that looking straight into the wall still
## leaves it.
@export var wall_jump_min_away: float = 0.35
## A HEIGHT (1.0 m), converted to a launch speed at the point of use --
## matching how this project reads every other `*ZHeight` field (spec §2.5).
## Source: 04 §4.4 `WallRunningJumpOffZHeightForward = 100` uu. ✅
@export var wall_running_jump_off_z_height_forward: float = 1.0
## Added on top of the base rise height at best execution, up to 0.6 m more.
## Source: 04 §4.4 `WallRunningJumpOffZHeightMaxAddTurned = 60` uu. ✅
@export var wall_running_jump_off_z_height_max_add_turned: float = 0.6

## How long after touching the wall a jump still counts as "instant", and how
## long until it counts as fully stale. ✅ MEASURED (04 §4.4).
##
## The Noob/ProAdd gradient interpolates on TIMING, not on facing. Across 24
## kick-offs, kicking within 5 frames of contact gave 6x the speed gain of a
## late one (median +5.12 vs +0.81 km/h), while the correlation between the
## gain and how far the view had swung during the run was -0.19 -- i.e. none.
##
## So the "skill" DICE named in these parameters is REACTION SPEED: touch the
## wall and go, and you take the full 520 uu/s; ride the run out and you get
## the bare 120. Implementing it costs one timestamp.
@export var wall_jump_prime_window: float = 0.05
@export var wall_jump_stale_time: float = 0.25

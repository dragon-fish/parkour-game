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
## THE FLOOR IS FOR LOOKING INTO THE WALL, not for looking along it. At 0.35
## (20 degrees) a kick taken while looking straight down the wall -- the view
## almost parallel to it, which is how a run is normally jumped out of -- was
## bent 20 degrees anyway, and both the turned speed and the push went that
## way: at 8 m/s that is 0.7*8*sin20 + 5.2*sin20 = 3.5 m/s sideways, enough
## that a landing straight ahead cannot be reached. Several of the original's
## own wall runs ask for exactly that jump.
##
## 0.15 is about 8.6 degrees: still enough to clear a 0.4 m capsule off the
## surface within a quarter second, and the same rotation still swings a view
## aimed INTO the wall all the way out (looking at the wall gives away = -1,
## which this rotates onto the normal whatever the floor is).
@export var wall_jump_min_away: float = 0.15
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

## How much of the speed carried into the kick is TURNED onto the direction the
## player is looking, 0 to 1.
##
## The kick used to be a pure addition: the push was added to a body still
## carrying its whole along-wall velocity, so at a running 7 m/s a sideways kick
## of a few m/s barely bent the path at all. The owner reported it exactly --
## "looking to the side during a wall run, the push is so small you basically
## cannot jump out."
##
## Turning the carried speed instead makes the run's momentum the CAPITAL and
## the kick the decision about where to spend it, which is what the rest of this
## project's movement already does everywhere else. The push above is still
## added on top; this only decides which way the speed already in the body ends
## up pointing.
##
## ⚠️ PROJECT-DEFINED. Short of 1 on purpose: turning is interpolated between
## the two directions, so a hard turn arrives slightly slower than a soft one,
## which is the same tax the speed system charges everywhere else.
@export var look_redirect: float = 0.7

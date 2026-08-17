class_name WallRunConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_WallRun.

## Minimum horizontal speed required to attach to a wall. Wall running is a
## way to CARRY speed, never a way to create it from nothing.
@export var wall_min_speed: float = 5.0
## How far sideways a wall may be and still be grabbed.
@export var wall_reach: float = 0.75
## Gravity multiplier while on a wall. Well below 1 so the run reads as
## defying gravity, above 0 so it still has a clock.
@export var wall_gravity_scale: float = 0.35
## Forward push applied along the wall, in m/s^2.
@export var wall_accel: float = 18.0
## Upper bound on speed the wall itself can push you to. Held at or below
## PawnConfig.ground_speed and air_speed on purpose -- wall_min_speed's own doc
## comment says the wall is "a way to CARRY speed, never a way to create it
## from nothing", so its own accel must never top the player up past what
## foot speed alone can already reach. Was pinned by
## tests/legacy/test_movement_config.gd's
## test_wall_running_cannot_create_speed_beyond_what_foot_speed_reaches --
## ARCHIVED by Task 1 and NOT in the running suite, so nothing enforces this
## today; restore the pin when the behavioural suite is rewritten.
## Held equal to ground_speed, mirroring the pre-retune default (both were
## 9.0) -- when the gravity/jump/speed trio dropped ground_speed to 7.2 (see
## PawnConfig.gravity's own comment), this followed it down for the same
## reason: leaving it at the old 9.0 would let the wall push the player
## faster than running itself now can, which is exactly the "wall creates
## speed" case the check above exists to catch.
@export var wall_max_speed: float = 7.2
## Wall running ends once total horizontal speed decays below this (measured
## the same way as wall_min_speed, not projected onto the wall's tangent).
## Kept as its own value rather than a fraction of wall_min_speed, mirroring
## Slide's separate slide_entry_speed/slide_exit_speed: attaching and staying
## attached are different questions, and a run should not drop the instant it
## dips just under the speed that started it.
@export var wall_exit_speed: float = 2.5
## Hard cap on one wall run.
@export var wall_max_duration: float = 1.5
## Gentle pull toward the wall surface, in m/s per tick, so the body stays
## glued through small surface irregularities instead of drifting off.
@export var wall_stick_force: float = 0.5

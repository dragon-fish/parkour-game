class_name SlideConfig
extends MoveConfig

# The Godot counterpart of the original's TdMove_Slide.

## Minimum horizontal speed required to start a slide. Below it, crouching just
## crouches — a slide has to be earned with speed already on the clock.
@export var slide_entry_speed: float = 4.0
## One-off speed added on entering a slide. This is the payoff that makes
## sliding worth doing rather than just running.
@export var slide_boost: float = 2.5
## Highest horizontal speed at which entering a slide still grants
## slide_boost. At or below this, a slide converts running speed into a
## burst, capped at this threshold plus slide_boost. ABOVE it, entering a
## slide grants no boost at all — you cannot spend speed you have not
## rebuilt. This is what makes a slide an EXCHANGE rather than a stackable
## bonus: without it, tapping crouch repeatedly nets a boost every single
## time, chaining slides past ground_speed and on toward the slide_max_speed
## safety rail. Defaults to PawnConfig.ground_speed, independently of it (not
## a reference to it, mirroring land_cost_speed_ref/land_dip_speed_ref's own
## note on sharing a default without sharing a variable) so a slide entered
## at a dead run still pays its full boost, but tapping crouch again while
## still at or above ground_speed pays nothing until speed decays back down.
@export var slide_boost_entry_threshold: float = 9.0
## Deceleration while sliding, in m/s^2. Well below PawnConfig.base_friction,
## which is what makes a slide carry.
@export var slide_friction: float = 5.0
## Sliding ends when speed decays to this.
@export var slide_exit_speed: float = 2.0
## Hard cap on slide duration so a slide cannot be held indefinitely on a slope.
@export var slide_max_duration: float = 1.8
## Capsule height while sliding.
@export var slide_capsule_height: float = 0.9
## How fast the slide direction can be steered, in radians per second. Low on
## purpose: a slide commits you to a line.
@export var slide_steer_rate: float = 1.2
## Speed the player can shuffle at when a spent slide cannot stand up because
## something is directly overhead. Without this, a slide that stops under a low
## roof has no exit at all: speed only ever decays, every route back to Ground
## is gated on headroom, and nothing in the Slide state can generate speed —
## the player is stranded until they hit the arena's reset key.
@export var slide_crawl_speed: float = 2.5
## Acceleration a fully vertical drop would add to a slide, scaled by the
## downhill component of the floor under it (so a 20 degree descent contributes
## sin(20 degrees) of this). Spec section 6 requires a downhill slide to resist
## decay or net-accelerate; at the default this outruns slide_friction on
## anything steeper than about 13 degrees, which puts the arena's 16.7 degree
## descent comfortably on the accelerating side rather than balanced on the
## break-even point where any tuning of either knob flips its sign.
@export var slide_slope_accel: float = 22.0
## Hard ceiling on a slide's horizontal speed. A safety RAIL rather than a
## tuning knob: slide_max_duration is gated on headroom, so a long COVERED
## downslope has nothing else bounding it and slide_slope_accel would
## accelerate the player without limit. Set far above anything the arena's
## ramp produces (which peaks near 11.5 m/s), so it never binds in normal play.
@export var slide_max_speed: float = 20.0

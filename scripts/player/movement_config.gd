class_name MovementConfig
extends Resource

# Single source of truth for every feel-related number. Nothing in the state
# scripts may hardcode a value; the F1 tuning panel writes back into an
# instance of this resource at runtime.

@export_group("Ground")
## Target horizontal speed with no sprint key held.
@export var walk_speed: float = 5.0
## Target horizontal speed while sprinting.
@export var sprint_speed: float = 9.0
## How fast horizontal velocity converges on the target, in m/s^2.
@export var ground_accel: float = 60.0
## Deceleration applied when there is no movement input, in m/s^2.
@export var ground_friction: float = 40.0
## Downward bias GroundState writes into velocity.y every tick to keep the
## body glued to the floor across seams and gentle slopes; without it,
## is_on_floor() flickers while running.
@export var floor_snap_speed: float = 2.0

@export_group("Air")
## Air acceleration. Deliberately far below ground_accel: committing to a
## jump is the core of the movement feel.
@export var air_accel: float = 12.0
## Upper bound on the speed air control alone can reach. Momentum carried in
## from other states is never reduced by air control.
@export var air_max_speed: float = 9.0
@export var gravity: float = 24.0
@export var terminal_velocity: float = 60.0

@export_group("Jump")
@export var jump_velocity: float = 7.5
## Grace period after leaving a ledge during which a jump still works.
@export var coyote_time: float = 0.12
## How long a jump press is remembered before landing.
@export var jump_buffer_time: float = 0.12

@export_group("World")
## How far below the floor (world Y = 0) the player must fall — e.g. a missed
## jump over the practice gaps — before being considered out of the level and
## teleported back to spawn. Stored as a positive depth rather than a raw
## negative Y so the tuning panel's auto-generated slider (which assumes a
## positive default and floors its range at zero) works for it like any
## other parameter.
@export var fall_recovery_depth: float = 20.0

@export_group("Landing")
## Fraction of horizontal speed kept after a flat landing at land_dip_speed_ref
## fall speed. Below that fall speed the loss scales down proportionally; this
## is the "speed is easy to lose" half of the momentum design.
@export var land_speed_keep: float = 0.55
## Same, but for a landing where the crouch key was held — the reward for
## knowing the roll is there.
@export var roll_speed_keep: float = 0.94
## Minimum fall speed at which crouching counts as a roll. Below it a crouched
## landing is just a landing, so tapping crouch constantly earns nothing.
@export var roll_min_fall_speed: float = 5.0

@export_group("Slide")
## Minimum horizontal speed required to start a slide. Below it, crouching just
## crouches — a slide has to be earned with speed already on the clock.
@export var slide_entry_speed: float = 4.0
## One-off speed added on entering a slide. This is the payoff that makes
## sliding worth doing rather than just running.
@export var slide_boost: float = 2.5
## Deceleration while sliding, in m/s^2. Well below ground_friction, which is
## what makes a slide carry.
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

@export_group("Camera")
## Height of the camera rig above the player's origin. Baked into player.tscn
## as CameraRig's initial local position by tools/build_player_scene.gd, but
## CameraRig.setup()/update_effects() re-apply this every frame so the F1
## panel can tune it live like every other camera value.
@export var eye_height: float = 0.7
@export var mouse_sensitivity: float = 0.0022
@export var pitch_limit_deg: float = 89.0
@export var fov_base: float = 75.0
@export var fov_max: float = 95.0
## Horizontal speed at which FOV reaches fov_max.
@export var fov_speed_ref: float = 9.0
@export var fov_lerp_speed: float = 6.0
@export var bob_frequency: float = 1.6
@export var bob_amplitude: float = 0.055
## How fast head bob fades in and out as the player leaves and regains the
## ground. Fading rather than hard-cutting the bob offset is what prevents a
## visible snap in camera height at the moment of a jump or a landing.
@export var bob_fade_speed: float = 6.0
@export var land_dip_max: float = 0.32
@export var land_dip_recover: float = 2.2
## Fall speed that produces a full-strength landing dip.
@export var land_dip_speed_ref: float = 18.0

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
## Fall speed at which a landing costs its FULL speed penalty; below it the
## loss scales down proportionally. Deliberately separate from the camera's
## land_dip_speed_ref even though the two share a default: the camera dip and
## the momentum cost are independent design knobs, and tuning how hard the view
## drops must not silently retune the physics.
@export var land_cost_speed_ref: float = 18.0
## Fraction of horizontal speed kept after a flat landing at land_cost_speed_ref
## fall speed. Below that fall speed the loss scales down proportionally; this
## is the "speed is easy to lose" half of the momentum design.
## Values above 1.0 are clamped in code — see AirState._apply_landing_cost.
@export var land_speed_keep: float = 0.55
## Same, but for a landing where the crouch key was held — the reward for
## knowing the roll is there. Also clamped to 1.0: a landing may cost speed or
## cost nothing, but it must never ADD any.
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
## Highest horizontal speed at which entering a slide still grants
## slide_boost. At or below this, a slide converts running speed into a
## burst, capped at this threshold plus slide_boost. ABOVE it, entering a
## slide grants no boost at all — you cannot spend speed you have not
## rebuilt. This is what makes a slide an EXCHANGE rather than a stackable
## bonus: without it, tapping crouch repeatedly nets a boost every single
## time, chaining slides past sprint_speed and on toward the slide_max_speed
## safety rail. Defaults to sprint_speed, independently of it (not a
## reference to it, mirroring land_cost_speed_ref/land_dip_speed_ref's own
## note on sharing a default without sharing a variable) so a slide entered
## at a dead sprint still pays its full boost, but tapping crouch again while
## still at or above sprint speed pays nothing until speed decays back down.
@export var slide_boost_entry_threshold: float = 9.0
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
## How long a crouch press is remembered before landing, mirroring
## jump_buffer_time. This is what makes the roll-into-slide chain reachable: a
## roll needs crouch HELD through the impact, but Slide entry keys off the
## press EDGE (to stop a held key strobing in and out of Slide), and that edge
## fires in mid-air. Buffering the press — never the held state — lets it open
## a slide on touchdown without reopening one every time a slide ends.
@export var crouch_buffer_time: float = 0.15

@export_group("Probes")
## Smallest upward (Y) component a surface normal may have and still count as
## ground CharacterBody3D's own locomotion already walks, rather than
## something Probes.gd should react to -- roughly matching floor_max_angle
## (45 degrees at Godot's default; 0.7 ~= cos(45.6 degrees)). This is the
## single stated definition of "walkable" the vault and ledge probes share,
## read two opposite ways depending on which ray is asking:
##   - a DOWNWARD probe's hit (vault_query's and ledge_query's landing
##     surface) must be AT OR ABOVE this to count as a top worth standing on;
##   - a FORWARD probe's hit (vault_query's shin-height obstacle check) must
##     be BELOW this to count as a genuine face rather than a slope the
##     player would simply walk up.
## One number, because a ramp reads as flat ground either way it is probed:
## measured directly, a shin ray planted on the arena's 18.4 degree UpRamp
## reports normal (0, 0.949, 0.316) -- comfortably above this threshold, i.e.
## walkable ground, not an obstacle face -- which is exactly what used to let
## a plain climbable ramp read as a vaultable obstacle and re-trigger on every
## step. Previously two separate hardcoded literals inside probes.gd (one per
## query) that happened to agree; moved here so there is one knob instead of
## two copies that could silently drift apart.
@export var min_walkable_normal_y: float = 0.7

@export_group("Vault")
## Highest obstacle top, measured from the player's feet, that can be vaulted.
@export var vault_max_height: float = 1.3
## How far ahead of the body the vault probe reaches.
@export var vault_reach: float = 1.4
## Minimum horizontal speed required to vault. Vaulting from a standstill would
## turn every waist-high box into a free elevator.
@export var vault_min_speed: float = 2.5
## How long the vault motion takes. Short enough to feel snappy, long enough
## to read as a deliberate action rather than a teleport.
@export var vault_duration: float = 0.32
## Fraction of the approach speed carried out the far side.
@export var vault_speed_keep: float = 0.85
## How far past the obstacle top the vault places the player.
##
## NOTE (transit speed): vault_duration does not scale with how far the body
## actually travels, so at vault_min_speed the body crosses a long path in the
## same fixed time as a short one — around the middle of the move it can be
## travelling several times faster than the approach speed even though the
## EXIT speed (vault_speed_keep) is a net loss. Not a correctness bug (nothing
## reads a mid-vault speed), just a visible fact about this design worth
## knowing before retuning either knob.
@export var vault_exit_forward: float = 0.6
## Peak height of the vertical arc ScriptedMove.advance() adds over the
## straight line from vault start to landing, so the body reads as rising
## over the obstacle instead of clipping through it.
@export var vault_arc_height: float = 0.15

@export_group("Ledge")
## Lowest and highest ledge tops, measured from the player's feet, that can be
## grabbed. The lower bound keeps low ledges going through Vault instead.
@export var ledge_min_height: float = 1.4
@export var ledge_max_height: float = 2.8
## How far ahead of the body a ledge can be reached.
@export var ledge_reach: float = 1.0
## How long the mantle motion takes.
@export var mantle_duration: float = 0.42
## Horizontal speed granted on top after a mantle.
@export var mantle_exit_speed: float = 2.0
## After releasing a ledge, how long before another can be grabbed. Without
## this, dropping off a ledge instantly re-grabs the same one.
@export var ledge_regrab_cooldown: float = 0.45
## How far past the ledge edge the mantle's landing point sits, so the body
## ends up standing ON the platform rather than teetering right at its lip.
## Mirrors vault_exit_forward's role for VaultState.
@export var mantle_forward_offset: float = 0.4
## Peak height of the vertical arc ScriptedMove.advance() adds over the
## straight line from the hang position to the mantle's landing point, so the
## body reads as climbing up and over the lip instead of clipping through it.
## Mirrors vault_arc_height's role for VaultState -- see ScriptedMove's own
## note on why the arc is a per-call value rather than a shared literal.
@export var mantle_arc_height: float = 0.3

@export_group("Wall Run")
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
## sprint_speed and air_max_speed on purpose -- wall_min_speed's own doc
## comment says the wall is "a way to CARRY speed, never a way to create it
## from nothing", so its own accel must never top the player up past what
## foot speed alone can already reach. See
## tests/test_movement_config.gd's own relationship test pinning this.
@export var wall_max_speed: float = 9.0
## Wall running ends once total horizontal speed decays below this (measured
## the same way as wall_min_speed, not projected onto the wall's tangent).
## Kept as its own value rather than a fraction of wall_min_speed, mirroring
## Slide's separate slide_entry_speed/slide_exit_speed: attaching and staying
## attached are different questions, and a run should not drop the instant it
## dips just under the speed that started it.
@export var wall_exit_speed: float = 2.5
## Hard cap on one wall run.
@export var wall_max_duration: float = 1.5
## Vertical impulse from a wall jump.
@export var wall_jump_up: float = 6.5
## Impulse away from the wall surface.
@export var wall_jump_push: float = 6.0
## After leaving a wall, how long before a wall with a SIMILAR normal can be
## attached again. This blocks re-climbing the SAME face over and over --
## it deliberately does NOT block zig-zagging between two DIFFERENTLY-facing
## walls, which stays allowed and is what the practice area's chaining relies
## on. Without this cooldown, bouncing straight back onto the very face just
## left would climb forever — the classic wall-run exploit.
@export var wall_reattach_cooldown: float = 0.5
## How alike two wall normals must be to count as "the same wall", as a dot
## product. 1.0 means identical facing.
@export var wall_same_normal_dot: float = 0.85
## Gentle pull toward the wall surface, in m/s per tick, so the body stays
## glued through small surface irregularities instead of drifting off.
@export var wall_stick_force: float = 0.5
## Camera roll while wall running, in degrees.
@export var wall_camera_roll_deg: float = 14.0
## How fast the camera rolls into and out of the wall tilt, in degrees/second.
@export var wall_camera_roll_speed: float = 56.0

@export_group("Animation")
## Horizontal ground speed above which CharacterAnimator plays the run clip
## instead of idle. A feel/readability value like every other threshold here
## -- it drives no physics, only which animation reads as "moving".
@export var run_animation_speed_threshold: float = 1.0

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
## How far the camera drops while sliding, in metres. Must keep the sliding
## eye at or below the top of the CROUCHED capsule (which sits at the body
## origin, i.e. 0m above it — see Player.set_capsule_height()), or the camera
## pokes through the roof of exactly the low tunnels this feature exists to
## let the player fit under: with eye_height 0.7, a drop below ~0.7 leaves the
## eye above that capsule top and inside the ceiling geometry from the
## outside. 0.75 clears it with a small margin.
@export var slide_camera_drop: float = 0.75
## How fast the camera moves between standing and sliding height.
@export var crouch_lerp_speed: float = 9.0
## How much the camera follows the attached body's head/neck node's
## POSITION each tick, from 0 (ignore it completely -- today's camera,
## eye_height plus bob/dip/crouch only) to 1 (sit exactly at the node's
## current position). ORIENTATION is never affected by this value -- see
## CameraRig.update_effects()'s own comment -- only translation.
##
## Defaulted LOW, not somewhere in the middle: this project's own body
## wrapper's run/jump clips were authored to be watched from behind, not worn
## as a first-person view, and a full-strength follow is expected to read as
## nauseating rather than merely "a bit much". The intent is for an owner to
## dial UP from a calm baseline until it starts to bother them, not dial DOWN
## from something already uncomfortable.
##
## NOTE: the F1 panel's sliders size themselves to RANGE_FACTOR (3x) the
## property's own default with no upper-bound hint of their own (see
## tuning_panel.gd) -- at this low a default the live slider cannot reach the
## full 1.0 "follows the node completely" end at all. CameraRig.update_effects()
## clamps to [0, 1] regardless, so this is a live-tuning reach limitation, not
## a correctness one; a preset .tres file or a direct script edit can still
## reach 1.0 if that is ever worth doing.
@export var camera_head_follow_strength: float = 0.15

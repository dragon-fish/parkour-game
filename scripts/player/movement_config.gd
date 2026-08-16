class_name MovementConfig
extends Resource

# Single source of truth for every feel-related number. Nothing in the state
# scripts may hardcode a value; the F1 tuning panel writes back into an
# instance of this resource at runtime.

@export_group("Ground")
## Target horizontal speed while the walk modifier (Ctrl) is held. There is no
## sprint key: the original reaches its top speed through an acceleration
## curve over time, not by holding a button, so ground speed is otherwise a
## single top speed (ground_speed below) rather than a walk/sprint pair. This
## field's OLD meaning ("no sprint held") is gone; it is now the slow,
## deliberate walk GBA_WalkMod produces.
## Source: docs/mirrors-edge-deep-research/02-速度系统.md §2.2 -- ME's
## `WalkVelocity` = 50 uu/s -> 0.5 m/s. The same section flags this discrete
## tier (and its four siblings) as MORE LIKELY an animation-blend threshold
## than a true speed clamp ("这五个值更可能是动画混合的阈值...而非速度钳制值"),
## since the real ground ceiling is the speed curve (GroundSpeed). Used anyway,
## per the owner's own direction that Ctrl should move the player "very
## slowly" -- 0.5 m/s (7% of ground_speed) reads as exactly that, not as an
## implausible number, so there was no reason to substitute a different one.
@export var walk_speed: float = 0.5
## Target ground speed. There is no sprint key -- see walk_speed's own comment
## -- so this is simply the top speed running reaches, unconditionally; the
## original's acceleration-curve build-up toward it is separate, later work.
## Source: docs/mirrors-edge-deep-research/09-Godot移植指南.md §9.1 -- ME's
## GroundSpeed 720 uu/s -> 7.2 m/s. Part of the gravity/jump_velocity/
## ground_speed trio; see MovementConfig.gravity's own comment for why these
## three move together (ME runs slower than this project did, but jumps
## roughly twice as far, because gravity dropped by a third).
@export var ground_speed: float = 7.2
## How fast horizontal velocity converges on the target, in m/s^2.
@export var ground_accel: float = 60.0
## Deceleration applied when there is no movement input, in m/s^2.
@export var ground_friction: float = 40.0
## Downward bias GroundState writes into velocity.y every tick to keep the
## body glued to the floor across seams and gentle slopes; without it,
## is_on_floor() flickers while running.
@export var floor_snap_speed: float = 2.0

@export_group("Air")
## Source: docs/mirrors-edge-deep-research/09-Godot移植指南.md §9.1 / 02-速度系统.md
## §2.3 -- ME's `AirControl = 0.025` is not an acceleration in its own right;
## the guide reads it as a MULTIPLIER on ground accel ("AirControl 0.025 ×
## 加速度"). Applied to this project's own ground_accel (60.0, itself already
## ~= ME's AccelRate 61.44, see ground_accel's own comment) rather than to
## ME's raw AccelRate, since this is the number our air_accelerate() actually
## gets compared against:
##   air_accel = ground_accel * 0.025 = 60.0 * 0.025 = 1.5
## This is deliberately not a speed-ceiling fix (see air_max_speed below for
## why the old air_max_speed = 9.0 was the wrong lever entirely) -- with the
## post-retune 1.58 s hangtime (gravity 24.0 -> 8.0, see MovementConfig.gravity),
## the old air_accel (12.0) could ratchet horizontal speed past ground_speed
## over repeated jumps; at 1.5, a full hangtime of continuous same-direction
## air control adds at most air_accel * 1.58 =~ 2.4 m/s, and landing's own
## speed cost (_apply_landing_cost) removes far more than that on any landing
## hard enough to matter -- see
## tests/test_air_state.gd's test_air_strafing_across_chained_jumps_never_
## exceeds_the_ground_speed_cap for a direct, driven-state measurement.
@export var air_accel: float = 1.5
## Outer bound on the speed air control alone can reach. Momentum carried in
## from other states is never reduced by air control.
## Source: docs/mirrors-edge-deep-research/09-Godot移植指南.md §9.1 -- ME's
## `AirSpeed 2400` uu/s -> 24.0 m/s at this project's confirmed 1 uu = 1 cm
## scale, i.e. essentially uncapped (3.3x GroundSpeed's own 720 uu/s). This
## replaces the OLD model this field encoded (a hard ceiling close to
## ground_speed, meant to prevent air control from creating speed on its own)
## with ME's actual one: air speed is barely bounded at all, because the real
## defence against an air-control exploit is air_accel being almost zero (see
## its own comment), not a low ceiling here.
## Player.air_accelerate() never actually targets this value alone -- its real,
## PRACTICAL ceiling is min(air_max_speed, max(ground_speed, current speed
## along the wish direction)), so this field only matters for momentum ALREADY
## above ground_speed (a wall-run or slide boost carried into the air), which
## it never reduces. Below ground_speed, air control tops out at ground_speed
## itself, however long the flight -- otherwise mere AIRTIME (a long fall, not
## even a deliberate exploit) could slowly climb toward this field's own 24.0
## and manufacture speed no ground state could reach on its own, which is
## exactly what a plain long fall did before this ceiling existed: see
## tests/test_landing.gd's test_a_landing_can_never_add_speed_however_the_
## keep_ratio_is_tuned and tests/test_slide_state.gd's
## test_chained_slide_then_jump_cannot_stack_the_entry_boost.
@export var air_max_speed: float = 24.0
## Source: docs/mirrors-edge-deep-research/09-Godot移植指南.md §9.1 Ground/Air/
## Jump table -- ME's DefaultGravityZ 800 uu/s^2 -> 8.0 m/s^2 at this project's
## confirmed 1 uu = 1 cm scale (see the research README's unit derivation).
## Changed together with jump_velocity and ground_speed -- the guide is
## explicit that retuning any one of the three alone makes the feel worse,
## not better. Gravity a third of the old value is what turns a 0.63 s hop
## into a 1.58 s arc: the floaty, committed jump IS the Mirror's Edge feel,
## not a side effect of it.
@export var gravity: float = 8.0
@export var terminal_velocity: float = 60.0

@export_group("Jump")
## Source: same table as gravity above -- ME's BaseJumpZ 630 uu/s -> 6.3 m/s.
## Part of the gravity/jump_velocity/ground_speed trio; see gravity's own
## comment for why these three move together.
@export var jump_velocity: float = 6.3
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
## Source: docs/mirrors-edge-deep-research/09-Godot移植指南.md §9.1 Landing
## table -- ME's HardLandingHeight 530 uu -> a 9.21 m/s impact speed at the
## confirmed 1 uu = 1 cm scale, the fall speed at which ME's own landing
## penalty is fully severe. The prior default (18.0) was roughly double that.
## Re-anchoring this after the gravity retune (24.0 -> 8.0, see
## MovementConfig.gravity) rather than before it: under the new, ME-accurate
## gravity a given fall height now produces a lower impact speed than it used
## to (v = sqrt(2*g*h) scales with sqrt(g)), so the two changes are meant to
## land together -- this value was never reachable at anything but very tall
## drops under the old gravity either way.
@export var land_cost_speed_ref: float = 9.21
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
## time, chaining slides past ground_speed and on toward the slide_max_speed
## safety rail. Defaults to ground_speed, independently of it (not a
## reference to it, mirroring land_cost_speed_ref/land_dip_speed_ref's own
## note on sharing a default without sharing a variable) so a slide entered
## at a dead run still pays its full boost, but tapping crouch again while
## still at or above ground_speed pays nothing until speed decays back down.
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

@export_group("Crouch")
## Fraction of ground_speed the player moves at while standing-crouched (not
## sliding). Source: docs/mirrors-edge-deep-research/03-损速机制.md §3.4's
## confirmed loss-mechanism table -- ME's `CrouchedPct = 0.4` ("下蹲 | 速度 ×
## 0.4"), also recorded as the Pawn-level "下蹲速度倍率" in
## 02-速度系统.md §2.3. Chosen over 05-动作库总览.md's `TdMove_Crouch:
## SpeedModifier=0.2` -- that value appears once, in a bare parameter dump
## with no narrative, while CrouchedPct is independently confirmed (✅) and
## explained in two separate sections; CrouchedPct is also the Pawn-wide
## multiplier, matching what this state actually needs (a flat fraction of
## ground_speed), rather than some other Move class's own, undocumented
## modifier.
@export var crouch_speed_pct: float = 0.4
## Capsule height while standing-crouched. Defaults to the SAME number as
## slide_capsule_height, independently of it (not a reference — mirroring
## land_cost_speed_ref/land_dip_speed_ref's own note on sharing a default
## without sharing a variable): a slide that decays into Crouch while the key
## is still held must not visibly pop, and a mismatched height would also
## reopen the exact headroom problem crouch exists to solve under a roof a
## slide already fits under. Independently tunable anyway, like every other
## pair in this file that happens to share a number.
@export var crouch_capsule_height: float = 0.9

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
## ground_speed and air_max_speed on purpose -- wall_min_speed's own doc
## comment says the wall is "a way to CARRY speed, never a way to create it
## from nothing", so its own accel must never top the player up past what
## foot speed alone can already reach. See
## tests/test_movement_config.gd's own relationship test pinning this.
## Held equal to ground_speed, mirroring the pre-retune default (both were
## 9.0) -- when the gravity/jump/speed trio dropped ground_speed to 7.2 (see
## MovementConfig.gravity's own comment), this followed it down for the same
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
## Camera roll while wall running, in degrees. Lowered from 14.0 alongside
## the camera bob amplitude cut (see MovementConfig.bob_amplitude) per the
## owner's playtest direction that camera roll should come down together
## with bob amplitude -- this is the only roll-amplitude value the camera
## system has (see camera_rig.gd's update_effects()), so it is what that
## direction is read as targeting. Not sourced from the research: the ME
## data has no value for this field either (09-Godot移植指南.md §9.1 marks it
## "not found in ME's config"), only a note that the wall-tilt DIRECTION this
## project already uses is right.
@export var wall_camera_roll_deg: float = 8.0
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
## DIVERGENCE FROM SOURCE, KEPT DELIBERATELY -- do not "correct" this back to
## ME's own value. The research (09-Godot移植指南.md §9.1 Camera table) confirms
## the original uses a FIXED 90 degrees with no speed-driven FOV at all: DICE's
## own account is that they opened the FOV to the widest angle before the image
## visibly bows, then left it there, and got their sense of speed from camera
## motion (landing dip, wallrun roll) instead.
##
## The owner has explicitly decided NOT to follow that: ME's fixed 90 was
## chosen for 2008 console viewing distances and reads as uncomfortably narrow
## on a PC monitor. Speed-driven FOV (90 at rest, 105 at top speed) is kept
## instead -- it is the common idiom for modern first-person parkour (Titanfall,
## Ghostrunner both use it), and the owner finds it more comfortable to play,
## even though the original explicitly rejects the technique. See
## docs/decisions-pending-your-review.md for the owner's own record of this
## choice.
@export var fov_base: float = 90.0
@export var fov_max: float = 105.0
## Horizontal speed at which FOV reaches fov_max -- i.e. "top speed" in the
## fov_base/fov_max comment above. Defaults to ground_speed's OWN value,
## independently of it (mirroring land_cost_speed_ref/land_dip_speed_ref and
## slide_boost_entry_threshold's own note on sharing a default without sharing
## a variable): wall_max_speed is capped at ground_speed too (see its own
## comment), so foot speed alone already IS the practical top speed a player
## can sustain. Previously left at a stale 9.0 (this project's OLD sprint
## speed, from before the sprint key was removed) after the gravity/jump/
## speed retune dropped ground_speed to 7.2 -- at that stale value the FOV
## never actually reached fov_max under ordinary running, silently breaking
## the "105 at top speed" claim above.
@export var fov_speed_ref: float = 7.2
@export var fov_lerp_speed: float = 6.0
## DIVERGENCE FROM SOURCE, KEPT DELIBERATELY: the research (09-Godot移植指南.md
## §9.1 Camera table) records that DICE ultimately REMOVED head bob entirely,
## citing vestibular conflict, and that ME's sense of speed comes from camera
## motion (landing dip, wallrun roll) rather than bob or FOV scaling. This
## project keeps bob -- the owner wants it tuned, not deleted -- so this is a
## known, recorded choice, not an oversight carried over from before the
## research existed.
##
## Tuned instead per the owner's own playtest direction: cycle once per
## footstep (up from the old, slower cadence) with lower amplitude -- high
## frequency, low amplitude, rather than a guessed multiplier on the old
## value.
##
## _bob_phase in camera_rig.gd accumulates as
## `delta * bob_frequency * horizontal_speed`, i.e. by DISTANCE travelled
## (speed * delta), not by wall-clock time -- so bob_frequency is radians of
## phase per METRE covered, and one full 2*PI cycle happens every
## `2*PI / bob_frequency` metres, independent of current speed. Deriving "one
## cycle per footstep" therefore means picking a footstep distance, not a
## frequency in Hz directly:
##   - step rate assumed: 180 steps/min = 3.0 Hz, the widely-cited running
##     cadence benchmark (commonly attributed to Jack Daniels' observation
##     that distance runners cluster near 180 spm across a range of paces) --
##     used here as the closest well-established real-world anchor, since
##     neither this project's own animations nor the ME research fix a
##     footstep rate.
##   - at the new top speed (ground_speed = 7.2 m/s, see its own comment),
##     distance per footstep = 7.2 / 3.0 = 2.4 m.
##   - bob_frequency = 2*PI / 2.4 = 2.618 (rad/m), so a full bob cycle
##     completes every 2.4 m of ground covered -- one cycle per footstep at
##     top speed, matching the owner's direction, without hand-tuning a
##     multiplier.
## (Sanity check against the OLD value: 1.6 rad/m -> 2*PI/1.6 = 3.93 m per
## cycle, which at the OLD top speed of 9.0 m/s worked out to roughly 2.3 Hz
## -- appreciably slower than a real footstep cadence, which is exactly the
## "slower than it should be" the owner was reacting to.)
@export var bob_frequency: float = 2.618
## Lowered alongside the frequency increase above, per the owner's explicit
## "high frequency, low amplitude" direction rather than a sourced number --
## the research has no target here since ME removed bob outright (see the
## divergence note on bob_frequency). 0.03 m sits within the real-world range
## commonly cited for a runner's vertical centre-of-mass oscillation
## (roughly 3-5 cm), which is a reasonable anchor now that the frequency
## above is itself locked to a real footstep cadence rather than an
## arbitrary multiple.
@export var bob_amplitude: float = 0.03
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

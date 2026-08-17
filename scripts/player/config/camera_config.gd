class_name CameraConfig
extends Resource

# The perception layer -- everything about how the world is presented to the
# player, as opposed to PawnConfig/MoveConfig, which govern how the body
# actually moves.

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
## Camera roll while wall running, in degrees. Lowered from 14.0 alongside
## the camera bob amplitude cut (see CameraConfig.bob_amplitude) per the
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

## Recorded from the original, not yet wired to anything. Source: 05 §5.10.
## ✅ These are the real shape of "how much does the view move" in the
## original: amplitude is a function of MOMENTUM, hard-clamped, rather than a
## constant. There is no procedural head-bob amplitude or frequency anywhere
## in the game's 2031 CDOs -- DICE removed head bob during development. Kept
## here because when the owner comes back to tune bob (which this project
## keeps on purpose, see bob_frequency's own note), these are better knobs
## than a constant amplitude.
@export var camera_anim_momentum_influence: float = 0.0001
@export var camera_forward_max: float = 0.5
@export var camera_downward_max: float = 0.4

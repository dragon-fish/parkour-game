class_name CameraConfig
extends Resource

# The perception layer -- everything about how the world is presented to the
# player, as opposed to PawnConfig/MoveConfig, which govern how the body
# actually moves.

## Height of the camera rig above the player's origin. Baked into player.tscn
## as CameraRig's initial local position by tools/build_player_scene.gd, but
## CameraRig.setup()/update_effects() re-apply this every frame so the F1
## panel can tune it live like every other camera value.
## [ME:CONFIRMED 09 §9.1] BaseEyeHeight = 76 uu. 0.76 m above the capsule
## centre puts the eye at 1.66 m off the floor on this project's 1.8 m body --
## THE FIRST-PERSON CAMERA IS NOT AT THE MODEL'S EYES, AND MUST NOT BE MOVED
## THERE. It sits at the neck, pushed slightly forward -- what essentially every
## FPS does, arrived at by the industry over many years rather than picked here.
## Four things break the moment it is moved to the eyes:
##
##   * The neck is directly below the eyes, so looking down puts it in frame
##     unavoidably. From in front of it, the downward cone clears it entirely.
##   * A weapon held at the shoulder needs the view far enough forward to see
##     it at all; from inside the skull it is behind the near plane or behind
##     the body.
##   * The nose, cheeks and hair intersect the near plane.
##   * A head bone carries the whole of an animation authored to be watched
##     from behind. See camera_head_follow_strength: 9 cm of bob against the
##     1-3 cm a first-person view tolerates.
##
## THE SAME PLACEMENT IS ARRIVED AT OUTSIDE GAMES, which is worth knowing
## before treating it as a rendering workaround: vlog cameras are worn on the
## neck or the chest rather than on the head, for two of the reasons above --
## a head mount shakes with every glance, and the lower, steadier viewpoint
## reads as MORE natural first person rather than less.
##
## THE TEST IS WHAT READS RIGHT, NOT WHAT IS TRUE. At a real eye height you
## cannot see your own hands while walking unless you deliberately raise them,
## and every first-person game shows them swinging anyway -- because that is
## what the view is expected to look like, not because it is accurate. Anatomy
## is worth citing when it AGREES with a placement that already feels right;
## it is not what the placement is derived from, and a change argued from it
## alone is arguing from the wrong thing.
##
## ⚠️ DO NOT READ THE OFFSETS BELOW AS ERRORS TO BE CORRECTED. They are not
## compensating for the camera failing to pitch about the neck joint the way a
## head does -- not pitching that way is the point. Hanging the eye off the
## neck joint has been tried and abandoned; VRM even ships the author's own
## viewpoint (a LookOffset node, 0.06 m above the head bone with essentially no
## forward component) and it is the wrong position for all four reasons above.
##
## ⚠️ AND THEY ARE NOT INDEPENDENT DIALS. Each is pinned by a different worst
## case, from opposite directions, and moving one to fix what you are looking
## at will silently break the case the other is holding:
##
##   eye_height   pinned from ABOVE by crouching into a low gap -- raise it and
##                the eye goes through the ceiling of the gap.
##   eye_forward  pinned from BELOW by looking straight down (pitch -89) --
##                shrink it and the view goes into the character's own chest.
##
## Anyone retuning either needs both in hand, and a check of the other case.

## the original's own eye line, not a guessed one.
@export var eye_height: float = 0.76
@export var mouse_sensitivity: float = 0.0022
@export var pitch_limit_deg: float = 89.0
## [ME:CONFIRMED 09 §9.1] the original uses a FIXED 90 degrees with no
## speed-driven FOV at all: DICE opened the FOV to the widest angle before
## the image visibly bows, then left it there, and got their sense of speed
## from camera motion (landing dip, wallrun roll) instead.
##
## DIVERGENCE FROM SOURCE, KEPT DELIBERATELY -- DO NOT "correct" this back to
## the original's fixed 90. ME's fixed 90 was chosen for 2008 console viewing
## distances and reads as uncomfortably narrow on a PC monitor. Speed-driven
## FOV (90 at rest, 105 at top speed) is kept instead -- it is the common
## idiom for modern first-person parkour (Titanfall, Ghostrunner both use
## it) and reads more comfortably here, even though the original explicitly
## rejects the technique. See docs/decisions-pending-your-review.md for the
## record of this choice.
@export var fov_base: float = 90.0
@export var fov_max: float = 105.0
## Horizontal speed at which FOV reaches fov_max -- i.e. "top speed" in the
## fov_base/fov_max comment above. Defaults to ground_speed's OWN value,
## kept independently rather than reading PawnConfig.ground_speed directly:
## wall running's own along-wall acceleration is capped by the energy-curve
## speed_cap() (see WallRunMove's own maintenance step), which itself never
## exceeds ground_speed, so foot speed alone already IS the practical top
## speed a player can sustain. KEEP THIS IN SYNC WITH ground_speed -- a stale
## value here means FOV never actually reaches fov_max under ordinary
## running, silently breaking the "105 at top speed" claim above.
@export var fov_speed_ref: float = 7.2
@export var fov_lerp_speed: float = 6.0
## DIVERGENCE FROM SOURCE, KEPT DELIBERATELY -- the research (09-Godot移植指南.md
## §9.1 Camera table) records that DICE ultimately REMOVED head bob entirely,
## citing vestibular conflict, and that ME's sense of speed comes from camera
## motion (landing dip, wallrun roll) rather than bob or FOV scaling. DO NOT
## delete bob to match that: this project keeps it tuned instead.
##
## Tuned to cycle once per footstep, high frequency and low amplitude, rather
## than a guessed multiplier on a slower cadence.
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
##   - at the top speed (ground_speed = 7.2 m/s, see its own comment),
##     distance per footstep = 7.2 / 3.0 = 2.4 m.
##   - bob_frequency = 2*PI / 2.4 = 2.618 (rad/m), so a full bob cycle
##     completes every 2.4 m of ground covered -- one cycle per footstep at
##     top speed.
@export var bob_frequency: float = 2.618
## Lowered alongside the frequency increase above: high frequency, low
## amplitude, rather than a sourced number -- the research has no target here
## since ME removed bob outright (see the divergence note on bob_frequency).
## 0.03 m sits within the real-world range commonly cited for a runner's
## vertical centre-of-mass oscillation (roughly 3-5 cm), a reasonable anchor
## now that the frequency above is locked to a real footstep cadence rather
## than an arbitrary multiple.
@export var bob_amplitude: float = 0.03
## How fast head bob fades in and out as the player leaves and regains the
## ground. Fading rather than hard-cutting the bob offset is what prevents a
## visible snap in camera height at the moment of a jump or a landing.
@export var bob_fade_speed: float = 6.0
@export var land_dip_max: float = 0.32
@export var land_dip_recover: float = 2.2
## Fall speed that produces a full-strength landing dip.
@export var land_dip_speed_ref: float = 18.0

## The view's nod on take-off and touchdown. PROJECT-DEFINED, all of them.
##
## Take-off: jump_pitch_kick_min_deg from a standstill, linear to
## jump_pitch_kick_deg at jump_pitch_kick_speed_ref (horizontal). Negative is
## down: a standing jump dips the view slightly and a running one lifts it.
## Peaks over jump_pitch_kick_rise_time, eases back over
## jump_pitch_kick_recover_time, each along its own curve (the _trans/_ease
## pairs, Godot's standard easings).
##
## Touchdown: always down by land_pitch_kick_deg, whatever the speed or the
## fall, and quick both ways (land_pitch_kick_rise_time, _recover_time).
## [ME:CONFIRMED by play] the landing nod is the same small dip every time --
## faint enough to lose once running -- EXCEPT the landing that ends an
## airborne stretch with a coil in it, which throws the head by
## coil_land_pitch_kick_deg at its own, slower pace (coil_land_pitch_kick_rise_time,
## _recover_time), and comes back like a spring: the way home is an
## ease-out-back that swings coil_land_pitch_kick_bounce_deg past level before
## it settles, all inside the recover time. [ME:CONFIRMED by play] the coil's
## landing springs back a little. See Player.last_landing_coiled.
## The nods seen from outside are scaled by third_person_pitch_kick_scale,
## faded with the view: a nod that is the landing from inside is the whole
## world lurching from behind.
@export var third_person_pitch_kick_scale: float = 0.3
@export var jump_pitch_kick_min_deg: float = -2.0
@export var jump_pitch_kick_deg: float = 5.0
@export var jump_pitch_kick_speed_ref: float = 2.0
@export var jump_pitch_kick_rise_time: float = 0.25
@export var jump_pitch_kick_recover_time: float = 0.55
@export var jump_pitch_kick_rise_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var jump_pitch_kick_rise_ease: Tween.EaseType = Tween.EASE_OUT
@export var jump_pitch_kick_recover_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var jump_pitch_kick_recover_ease: Tween.EaseType = Tween.EASE_OUT
@export var land_pitch_kick_deg: float = 1.5
@export var coil_land_pitch_kick_deg: float = 15.0
@export var coil_land_pitch_kick_rise_time: float = 0.2
@export var coil_land_pitch_kick_recover_time: float = 0.3
@export var coil_land_pitch_kick_bounce_deg: float = 2.0
@export var land_pitch_kick_rise_time: float = 0.1
@export var land_pitch_kick_recover_time: float = 0.1

# --- shake, driven by the level -----------------------------------------------
#
# Something heavy passing close enough to be felt. The level asks for one in
# the ORIGINAL's own numbers (a Mall train: Amplitude 1500, Frequency 0.003 for
# one train and 0.005 for the other) and these two turn them into metres and
# hertz.
#
# [ME:UNKNOWN] what unit either of the original's numbers is in. Nothing found
# says, so they are not converted, they are SCALED, and these are dials to be
# turned by eye. What survives the scaling is the RATIO -- the second train
# shakes 1.67 times faster than the first -- and that ratio is the part worth
# being faithful to. DO NOT replace these with a derivation; there is nothing
# to derive from.

## Metres of eye displacement per unit of the original's Amplitude.
@export var shake_amplitude_scale: float = 0.00002
## Hertz per unit of the original's Frequency.
@export var shake_frequency_scale: float = 2000.0
## How long the shake takes to reach full strength, and to die away once its
## hold has run out, in seconds. EASED at both ends: a shake that switches on
## reads as a dropped frame rather than as something passing.
@export var shake_attack: float = 0.15
@export var shake_release: float = 0.45
## How far the camera drops while sliding, in metres. Must keep the sliding
## eye at or below the top of the CROUCHED capsule (which sits at the body
## origin, i.e. 0m above it — see Player.set_capsule_height()), or the camera
## pokes through the roof of exactly the low tunnels this feature exists to
## let the player fit under: a drop below eye_height leaves the eye above that
## capsule top and inside the ceiling geometry from the outside.
##
## The invariant is `slide_camera_drop >= eye_height`; 0.81 keeps a ~0.05 m
## margin above eye_height (0.76). tests/test_config_layout.gd pins the
## STRICTER form, `> eye_height`, since check_greater is the only comparison
## the test harness offers -- so the pin refuses the equal case this comment
## would tolerate. That is the safe direction (an eye exactly level with the
## capsule top is the boundary this margin exists to stay off), not a
## disagreement to reconcile.
@export var slide_camera_drop: float = 0.81
## How fast the camera moves between standing and sliding height.
@export var crouch_lerp_speed: float = 9.0

## How long the per-model slide eye lift takes to LET GO, in seconds. The
## lift is present through the slide and vanishes the instant Shift is
## released; it must ride the 0.5 s stand-up rather than the eye snapping
## back.
##
## DO NOT ease this on crouch_lerp_speed: at 9.0 m/s a 0.15 m lift would be
## gone in a sixtieth of a second, which reads as a cut.
##
## A TIME rather than a rate, unlike its neighbours, and deliberately: the lift
## itself is per-model (BodyProfile.slide_eye_lift), so a fixed rate would take
## a different length of time on every body. Half a second is half a second.
##
## Matches Player.body_slide_exit_blend_time, which is the animation half of the
## same moment -- the body picking itself up out of a slide.
@export var eye_lift_release_time: float = 0.5

## PROJECT-DEFINED. How quickly the first-person eye hands over between its
## two clip-offset regimes (ignore the offset outside scripted moves, follow it
## inside -- see Player._camera_head_offset()). A time constant; near 0 snaps.
## DO NOT snap this to 0: StepUp applies a 0.2 m backward offset, and without
## a blend it pops visibly on entry and exit instead of easing.
@export var scripted_eye_offset_blend_time: float = 0.2

## How long the third-person camera takes to cross from one shoulder to the
## other, in seconds. It matters most for the wall run, which swaps sides on
## its own -- a shot that jumps across the body reads as a cut rather than as
## a camera move -- but the manual cycle wanted it too.
##
## A TIME rather than a rate, for the same reason as eye_lift_release_time
## above: third_person_right is a per-taste distance, so a fixed rate would
## take a different length of time at every setting.
@export var third_person_shoulder_time: float = 0.25

## Where the eye is pinned while dying WITH A BODY ATTACHED, in degrees.
## Positive looks up. Switching to third person and pressing V mid-clip lines
## up with the animation: a third-person death does not take the cinematic,
## so the eye runs the ordinary path and the head-follow carries it along
## with the death clip. This value only supplies where to point.
##
## Only applies with a body attached. Without one there is nothing for the
## eye to follow, and DeathSequence's own scripted fall is still the answer --
## see its play().
@export var death_pitch_deg: float = 25.0

## The same, in third person, but -25: the camera hangs BEHIND the rig, so
## pitching the rig up swings the arm DOWN -- straight into the floor a dead
## body is lying on. Looking down swings it up, which is where a camera
## watching a body on the ground wants to be. A positive value here puts the
## camera underground.
@export var death_pitch_third_person_deg: float = -25.0

## How far the eye may trail a SCRIPTED body turn in first person, in radians.
##
## HELD SHORT, and the reason is a first-person one throughout: a lag is a
## softening, not a detour. Past a certain size the eye is no longer trailing the
## turn, it is pointing somewhere else entirely -- in first person, at the inside
## of whatever the body is pressed against. Reported in play as the view lunging
## into the wall and then snapping back to the ledge. Anything bigger than this
## is better taken as a cut.
@export var scripted_yaw_max_lag: float = 0.35

## How far the first-person eye is lifted while dying, in metres. The
## head-follow puts the eye exactly where the head bone is, and a body lying
## on the floor has its head ON the floor -- so without this, the eye ends up
## inside it.
##
## First person only. In third person the camera is metres away and has no
## such problem.
##
## THIS NUMBER IS COUPLED TO THE CLIP'S OWN OFFSET, and the coupling runs the
## opposite way to the obvious one. _camera_head_offset() SUBTRACTS the clip
## offset back out (Player, and test_clip_offsets.gd locks it), so raising the
## model does not raise the eye -- it leaves the eye where it was while the
## visible body climbs past it, putting the eye that much DEEPER inside the
## body. So a clip offset of +N metres wants this value to go UP by N, not
## down.
@export var death_eye_lift: float = 0.4

## The same, during an uncontrolled fall, in metres. LiftAir_Fall_Air holds
## the body horizontal with its hips at about 0.19 m, so the head bone the
## eye is following is close to the floor -- close enough to end up inside
## whatever the body passes. A smaller number than death_eye_lift for the
## same reason, scaled to that smaller offset.
@export var fall_uncontrolled_eye_lift: float = 0.15
## The same, lying on the back (LayOnGroundMove), in metres. Still wanted
## with the body propped up on its hands (the body scene's LyingPose): the head
## is clear of the floor then, but the eye riding it looks down along the body
## into its own clothes, and the lift is what puts the view over them.
@export var lay_on_ground_eye_lift: float = 0.2
## How fast the eye catches up after the body was lifted over a low obstacle
## (see Player.try_step_up). Exponential, so this is a rate, not a duration:
## ~12 settles a 0.35 m step in roughly 0.15 s, which reads as a stride. Lower
## it to make the lag more obvious, raise it toward a hard snap.
@export var step_smooth_speed: float = 12.0

## PROJECT-DEFINED. How fast the eye catches up when a MOVE turns the body,
## as opposed to when the player does.
##
## The two deserve different treatment, which is the same lesson the step
## follow taught: the eye does not have to track the capsule frame for frame.
## Under the player's own hand it must -- a laggy mouse is intolerable -- but a
## scripted turn is something happening TO the player, and snapping the view
## through it reads as a cut. DO NOT let this go to a hard snap: the reach
## onto a ledge squares the body up to the wall, sometimes through tens of
## degrees, and a snap there is exactly the kind of cut this field exists to
## avoid.
##
## Exponential, so a rate: ~10 absorbs a 45 degree correction in about a fifth
## of a second.
@export var scripted_yaw_catchup_speed: float = 10.0
## How much the camera follows the attached body's head/neck node's
## POSITION each tick, from 0 (ignore it completely -- today's camera,
## eye_height plus bob/dip/crouch only) to 1 (sit exactly at the node's
## current position). ORIENTATION is never affected by this value -- see
## CameraRig.update_effects()'s own comment -- only translation.
##
## THIS IS NOT A "HOW MUCH HEAD BOB" DIAL. It is how firmly the eye rides the
## skull: with a body attached, its NECK can pass through the view during a
## run, while standing still and looking down stays fine -- that clipping IS
## the measurement that the eye is not riding the head closely enough.
##
## Whatever fraction is not followed becomes RELATIVE motion between the eye
## and the skull it is meant to sit inside. Against a body that bobs its head
## 9 cm per stride (measured -- docs/feel-backlog.md §42), 0.15 gives the eye
## 1.3 cm of that and leaves the other 7.6 cm as head sliding through it.
##
## 1.0 is therefore the value that MEANS anything, and it costs nothing to
## use: what is followed is the head's DISPLACEMENT FROM ITS REST POSE, not its
## absolute position, so the eye keeps wherever it was placed -- eye_height,
## and in practice a little ahead of the neck, as first-person games place it
## -- and only inherits the motion. A naive follow at 1.0 that parks the
## camera on the head node's own origin would throw that placement away; this
## does not.
##
## The honest cost is the bob itself: at 1.0 you inherit the whole of whatever
## the body's animation was authored with -- for the reference body that is
## 9 cm, against the 1-3 cm a first-person view tolerates. Not a setting to
## fix but a fact about a clip authored to be watched from behind: an
## animation not made for first person is hard to sit through up close. The
## answer there is a body whose motion was authored for first person, or a
## third-person view -- not a fraction of this one, which only trades nausea
## for clipping.
##
## 0.0 opts out entirely and restores the purely procedural eye (eye_height
## plus bob/dip/crouch), bit-for-bit what every body-less setup already gets.
@export var camera_head_follow_strength: float = 1.0
## Camera roll while wall running, in degrees. Tied to the camera bob
## amplitude (see CameraConfig.bob_amplitude): keep the two moving together
## when tuning feel -- this is the only roll-amplitude value the camera
## system has (see camera_rig.gd's update_effects()).
##
## [ME:UNKNOWN 09 §9.1] the original has no recorded value for this field.
## [ME:CONFIRMED 09 §9.1] the wall-tilt DIRECTION this project already uses
## is correct.
@export var wall_camera_roll_deg: float = 8.0
## How fast the camera rolls into and out of the wall tilt, in degrees/second.
@export var wall_camera_roll_speed: float = 56.0

## Recorded from the original, not yet wired to anything.
## [ME:CONFIRMED 05 §5.10] the real shape of "how much does the view move" in
## the original: amplitude is a function of MOMENTUM, hard-clamped, rather
## than a constant. There is no procedural head-bob amplitude or frequency
## anywhere in the game's 2031 CDOs -- DICE removed head bob during
## development. Kept here because these are better knobs than a constant
## amplitude, for whenever bob (which this project keeps on purpose, see
## bob_frequency's own note) gets tuned against them.
@export var camera_anim_momentum_influence: float = 0.0001
@export var camera_forward_max: float = 0.5
@export var camera_downward_max: float = 0.4

## How fast a SCRIPTED LOOK SWEEP crosses the fan, in radians per second.
##
## Different from scripted_yaw_catchup_speed above, which is about the eye
## catching up to a body that moved under it. This one is the eye itself being
## moved -- Q during a wall run swings the view a quarter turn without touching
## the body, so there is no lag to bleed off, only a view to carry across.
##
## MEASURED: Q during a wall run carries the view through its 90 degree fan
## in 0.2 s, which is 7.85 rad/s. DO NOT derive this figure by eye or
## stopwatch again -- a felt guess consistently undershoots the timed one.
@export var look_sweep_speed: float = 7.85

## How long Q takes to swing the view half a turn where Q is simply a flick of
## the mouse, seconds -- see CameraRig.flick_half_turn(). Clockwise, as every
## Q turn is.
##
## [ME:INFERRED] from play: Q wherever the yaw is free and nothing scripted
## owns the body is the same as flicking the mouse 180 degrees in about this.
@export var q_flick_time: float = 0.3

## How fast the yaw fan's edge is eased in to meet a view that is already
## outside it, in radians per second.
##
## Only the fan MOVING produces that situation -- a wall run re-centring its fan
## on the wall it just attached to, or carrying it round a curve. A player
## pushing against an edge that has not moved is clamped hard, as always.
##
## PROJECT-DEFINED, the same idea as pitch_recover_speed on the other axis.
## Exponential, so a rate: ~8 carries a 57 degree correction -- the widest a
## wall-run attach can produce -- in about a third of a second.
@export var look_settle_speed: float = 8.0

## How far the eye banks through a vault, at the middle of the arc.
##
## [ME:INFERRED] as a MAGNITUDE: the original's account of this is
## qualitative only -- the camera tilts slightly as it traces an arc over the
## obstacle -- so this is set to be felt rather than noticed. Eased in and out
## across the vault's own duration, so it is never a step.
##
## THE SIGN FOLLOWS THE VISIBLE ANIMATION, NOT THE ORIGINAL'S HAND.
## [ME:CONFIRMED 05 §5.7] the original plants the LEFT hand (bLeftHandIK on
## both middle-tier rows), which is what this value was chosen to match
## before there was a visible body to disagree with it. The animation pack's
## SafetyVault plants the RIGHT hand instead, no left-handed vault clip
## exists in either pack, and mirroring a clip is a Blender job rather than a
## line of code -- so the camera bank is flipped to agree with the visible
## arm instead. A bank that leans the opposite way from the arm you can see
## is worse than one that leans the "wrong" way against a game nobody is
## holding this one next to. Flip it back the day a left-handed clip exists.
@export var vault_roll_deg: float = -7.0

## How much of the balance roll survives in third person.
##
## SMALL ON PURPOSE. In first person the roll IS the feedback -- the horizon
## tipping is what tells you which way you are going over. Seen from outside,
## the same roll tips the whole world around a character who is visibly leaning
## anyway, which reads as nausea rather than as information. The body's own lean
## carries the signal there; see BalanceConfig.max_body_lean_deg.
@export var third_person_balance_roll_scale: float = 0.15

## Time constant, seconds, on which the balance roll and FOV squeeze follow
## what BalanceMove asks for. Bites on the way OUT: the move zeroes both the
## instant the beam is left or lost, and without the ease a horizon tipped
## by up to max_camera_roll_deg snaps level in one frame -- the owner's call
## that a view leaving the beam eases back rather than cuts. The ride itself
## barely notices it, since the lean moves on a slower clock than this.
@export var balance_recover_time: float = 0.25

## Where the eye sits when the third-person view is on, as THREE FLOATS rather
## than the Vector3 this obviously wants to be.
##
## The reason is the tuning panel: it walks MovementConfig's sub-resources and
## collects TYPE_FLOAT only (see tuning_panel.gd), so a Vector3 never appears in
## it and could only be changed by editing this file and restarting. Framing a
## third-person camera is the exact thing you want to drag a slider for while
## running around, so it is three floats and lives in the panel.
##
## Named for what they do rather than x/y/z: positive `right` is over the right
## shoulder, positive `up` raises the eye, positive `back` pulls away from the
## head. All zero is the first-person camera exactly.
##
## A DEBUG VIEW FIRST, for the same reason docs/asset-candidates.md gives as
## the first prerequisite for any character model: a first-person game cannot
## show you its own body, so nothing about the animation, the mount height, or
## the parkour poses can be checked from inside it. Watching your own vault
## from outside is how you find out it looks wrong. Not a tuned over-the-
## shoulder framing -- placed to SEE the body first, then adjust.
@export var third_person_right: float = 0.6
@export var third_person_up: float = 0.35
@export var third_person_back: float = 3.0

@export var third_person_min_fraction: float = 0.15

## The model's size while the THIRD-PERSON body is on screen, about its feet.
## Nothing else follows it: not the capsule, not the moves, not the camera,
## whose head-follow reads the head as if the model were full size. A level
## built to first-person scale makes a full-size body loom in third person;
## smaller reads better, at the price of hands that stop short of the ledges
## the moves were measured against. A player setting (SettingsStore).
@export var third_person_body_scale: float = 1.0

## Radius of the sphere the third-person probe sweeps, in metres. What it buys
## is CLEARANCE: the camera comes to rest at least this far off whatever it
## backed away from, instead of flat against it.
##
## THE FLOOR IS GEOMETRY, NOT TASTE. A camera sitting exactly on a surface has
## that surface cutting through its near plane, so half the shot is inside the
## wall -- the near plane has width, and a ray probe cannot know that. Clearing
## it needs the near plane's half-diagonal: at near = 0.05 (Godot's default,
## and this project never sets it) and fov_max = 105 vertical, that is 0.065 up
## and 0.116 across on a 16:9 view, so 0.133 -- and 0.165 at 21:9. Anything
## below that and the clipping comes back on a wide monitor.
##
## Above the floor it IS taste, and the trade runs both ways: a bigger radius
## keeps the camera further off walls everywhere, including corridors where it
## did not need to back off at all. The shipped 0.2 is the smallest value that
## clears 21:9 with room to spare; 0.2-0.35 is the band worth trying.
##
## MEASURED, so the number is not a lie -- camera backed into a flat wall, the
## gap it comes to rest with:
##
##     dialled  0.05   0.10   0.20   0.35   0.45   0.60   0.80
##     actual   0.051  0.101  0.201  0.352  0.451  0.527  0.527
##
## DO NOT dial past about 0.45. The clearance tracks the radius to within one
## percent below that and then stops tracking it at all -- 0.60 and 0.80 give
## the identical 0.527, so the sweep has hit some cap of the physics backend's
## own. A radius that large is an absurd camera anyway; what matters is that
## Width of the band in front of a look limit where the input is progressively
## damped, degrees. Zero restores the hard stop.
##
## A CLAMP ALONE READS AS HITTING SOMETHING. The mouse keeps moving and the
## view simply stops, with nothing in between -- and every constrained move in
## this project shares that edge, so it is one feel and not several. In the
## original the last couple of degrees go heavy instead: you can tell the limit
## is coming before you arrive at it.
##
## Scaled by the room LEFT, so the input fades toward the edge rather than
## being cut at it: half a band out the mouse moves the view half as far, and
## the approach is asymptotic. That also means the limit is never quite
## reached, which is the point -- there is no frame where the view slams to a
## stop.
##
## Degrees from a look limit at which the view moves at HALF speed. Zero
## restores the hard stop.
##
## INVERSE, NOT A BAND: the scale is room / (room + this), so there is no edge
## where damping switches on and no corner in the response. Resistance grows
## continuously the whole way in and the limit is approached asymptotically,
## which is what reads as weight. A band -- full speed outside it, a straight
## ramp inside -- was tried first and is two straight lines with a kink where
## they meet; at any width narrow enough not to feel mushy it was also crossed
## inside a tick or two and could not be felt at all.
##
## What the number means, directly: at this many degrees out the view moves at
## half the speed the mouse asks for, at three times it about three quarters,
## at a third of it about a quarter. Far from any limit the factor is
## indistinguishable from 1, so ordinary looking is untouched.
##
## ONE NUMBER SERVES LIMITS OF VERY DIFFERENT SIZES -- 89 degrees of pitch, a
## 170 degree hang, a 45 degree shimmy -- so it is deliberately small: the tail
## is long and gentle rather than the last stretch being heavy.
## MEASURED, pitch driven into its 89 degree limit at a slow 1.5 degrees per
## tick. Samples eight ticks apart, over the last stretch:
##
##     0.0   85.50 -> 89.00                            the hard stop
##     1.5   81.85 -> 88.95 -> 89.00
##     3.0   79.09 -> 86.89 -> 88.97 -> 89.00
##     6.0   74.73 -> 82.36 -> 87.18 -> 88.75 -> 88.97
##
## Verified by feel from there. The first attempt at this feature shipped a
## 2.5 degree BAND and could not be felt at all -- worth knowing, because the
## width that sounds right when describing the original is not the width that
## survives a mouse crossing it in one tick.
@export var look_damp_half_deg: float = 3.0

## the dial stops being honest there, and it does so silently.
@export var third_person_probe_radius: float = 0.2

## Which physics layers the third-person probe treats as something to keep the
## camera out of. Layer 1 is the world, and the world is the only thing the
## shot has to stay clear of.
##
## DO NOT leave this at every layer, which is what an unset query mask means.
## A hanging cloth is a physics body the player is meant to walk straight
## through; probed against, it pulled the camera in and let go once a tick and
## the shot convulsed. Anything else that is solid to the simulation but not to
## the shot -- a pushable prop, a character -- has the same problem, so it is a
## mask rather than a soft-body special case.
@export_flags_3d_physics var third_person_probe_mask: int = 1

## The render layer carrying the body's FIRST-PERSON meshes, as a mask.
##
## VRM has a mechanism for this in the spec, and godot-vrm implements it: with
## the importer's head_hiding_method set to Layers, it generates a headless
## variant of the body and puts the two on separate layers -- measured on the
## owner's own export as "Body (Headless)" on layer 2 and Body/Face/Hair on
## layer 4.
##
## A camera renders every layer by default, so BOTH variants draw at once, and
## the face and hair sit exactly where the eye is. That is the clipping, and it
## is not something to solve by hiding meshes one at a time: the model already
## ships the answer, the camera just has to pick a side.
##
## Defaults match godot-vrm's own import defaults. A body with no layer split
## at all -- every mesh on layer 1, which is every non-VRM model -- is
## unaffected, since neither of these masks touches layer 1.
@export_flags_3d_render var first_person_body_layers: int = 2

## The render layer carrying the body's THIRD-PERSON meshes -- the full head.
## See first_person_body_layers.
@export_flags_3d_render var third_person_body_layers: int = 4

## How close and how far the third-person eye may be pulled with the wheel, in
## metres. third_person_back is where it starts; these bound where it can go.
@export var third_person_min_distance: float = 1.2
@export var third_person_max_distance: float = 6.0
## Metres per wheel notch.
@export var third_person_zoom_step: float = 0.35

## Metres per pixel while dragging the offset with the middle button held.
@export var third_person_drag_sensitivity: float = 0.004

## How far a middle-button press may travel and still count as a CLICK rather
## than a drag, in pixels. Below it, releasing cycles the shoulder preset.
@export var third_person_click_slack: float = 6.0

## Cold-blue ambient tint strength for the LEVEL, from 0 (neutral white
## ambient, no colour cast) to 1 (the full cold tint templates/base_level.tscn
## and tools/arena_builder.gd bake into the WorldEnvironment's
## ambient_light_color at build time -- Color(0.224, 0.467, 0.741), see the
## AMBIENT_SOURCE_COLOR comment at both of those). Defaults to 1.0 to match
## what is already baked into both scene sources, so leaving this dial alone
## changes nothing.
##
## Cheap v1 of a cool-blue shadow look evoking Mirror's Edge
## (docs/superpowers/specs/2026-08-25-menu-design.md): shadowed ground is lit
## almost entirely by ambient light in this renderer, so tinting ambient blue
## reads as cold shadows without a full-screen grading shader.
##
## LIVES HERE, NOT ON Arena, EVEN THOUGH AMBIENT IS A LEVEL CONCERN, NOT A
## PLAYER ONE. The F1 tuning panel only ever walks MovementConfig's
## sub-resources for TYPE_FLOAT exports (tuning_panel.gd collect_tunables) --
## it has no notion of "the level" to collect from, and Arena is not one of
## MovementConfig's config groups. This is the honest bridge: Arena already
## holds a `config: MovementConfig` (shared with the player and the panel), so
## it reads THIS field back out of it every _process() frame and lerps its
## own WorldEnvironment's ambient_light_color between neutral white and the
## tint above -- the same "consumer re-applies every frame so a live F1 drag
## takes effect immediately" pattern every other field in this file already
## follows (see this file's own header comment on eye_height).
@export var ambient_cold_strength: float = 1.0

## How long the view takes to travel between the first-person eye and the
## pulled-back one, whether the player pressed V or a level forced it.
## PROJECT-DEFINED; the original never changes view at all.
##
## Both ENDS are untouched by this: at 0 and at 1 the camera sits exactly
## where it sat before there was a blend, so every offset in this file that
## was tuned against the first-person eye still means what it meant. Only the
## journey is new.
@export var view_blend_time: float = 0.12

## How much screen blur the view change carries at its midpoint. Zero at both
## ends by construction, so the channel is free whenever no view is changing.
##
## It is here to COVER A SEAM, not for its own sake: the body swaps between
## its first-person and third-person meshes at one instant, and that pop has
## to happen somewhere. Blurring hardest exactly where the swap lands is the
## same trick a driving game plays when it cuts between chase and bonnet.
@export_range(0.0, 1.0, 0.05) var view_blend_blur: float = 0.4

## Where in that journey the body swaps between its first-person and
## third-person render layers. A VRM carries a full body and a headless one on
## separate layers, so the swap is a pop wherever it happens; putting it a
## third of the way out means the camera has already left the head before the
## face appears, and has not yet re-entered it when the face goes away.
##
## DO NOT set this to 0 or 1: at either end the swap coincides with the camera
## being inside the head, which is the clipping the split exists to prevent.
@export_range(0.05, 0.95, 0.05) var view_blend_body_swap: float = 0.35

## [13.4] WHERE THE WOUNDED PICTURE BEGINS, as a fraction of full health.
## Below this the colour starts draining; at zero it is fully grey.
##
## The original has no health bar -- the picture IS the readout -- so these
## two thresholds are the whole of the interface. PROJECT-DEFINED: the
## original's own numbers were never measured.
@export var wounded_desaturation_at: float = 0.5

## [13.4] Where the edge of the screen starts pulsing red. Below the grey
## threshold on purpose: draining colour says "you have been hurt", and the
## red is the last band, saved for actually being about to die. DO NOT swap
## the two -- reversed, the gentlest cue arrives at the most dangerous moment.
@export var wounded_alarm_at: float = 0.3

## How hard the red edge closes in at zero health, and how often it breathes.
## Gentle on purpose: it has to be readable while running without becoming
## the thing being looked at.
@export var wounded_alarm_strength: float = 0.45
@export var wounded_alarm_hz: float = 0.8

## [13.4] LOSING CONSCIOUSNESS, reached over the death sequence rather than
## cut to: the picture dims, steepens, and goes soft, on top of the grey the
## death already has. Dimming alone reads as a fade-out; steepening with it is
## what makes the light go while the shapes stay.
@export var death_brightness: float = 0.72
@export var death_contrast: float = 1.4
@export var death_blur: float = 0.45

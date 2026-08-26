class_name CameraConfig
extends Resource

# The perception layer -- everything about how the world is presented to the
# player, as opposed to PawnConfig/MoveConfig, which govern how the body
# actually moves.

## Height of the camera rig above the player's origin. Baked into player.tscn
## as CameraRig's initial local position by tools/build_player_scene.gd, but
## CameraRig.setup()/update_effects() re-apply this every frame so the F1
## panel can tune it live like every other camera value.
## Source: 09 §9.1 `BaseEyeHeight = 76` uu. ✅ Was a round 0.7 carried over
## from before the research existed; 0.76 above the capsule centre puts the
## eye at 1.66 m off the floor on this project's 1.8 m body, which is the
## original's own eye line rather than a guessed one.
@export var eye_height: float = 0.76
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
## independently of it (mirroring land_cost_speed_ref/land_dip_speed_ref's own
## note on sharing a default without sharing a variable): wall running's own
## along-wall acceleration is capped by the energy-curve speed_cap() (see
## WallRunMove's own maintenance step), which itself never exceeds
## ground_speed, so foot speed alone already IS the practical top speed a
## player can sustain. Previously left at
## a stale 9.0 (this project's OLD sprint
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
## let the player fit under: a drop below eye_height leaves the eye above that
## capsule top and inside the ceiling geometry from the outside.
##
## RAISED FROM 0.75 ALONGSIDE eye_height's move to the confirmed 0.76: this is
## a DERIVED value, not an independent one -- the invariant above is
## `slide_camera_drop >= eye_height`, and 0.75 satisfied it only while the eye
## sat at 0.70. 0.81 restores the same ~0.05 m margin the old pair had.
## tests/test_config_layout.gd pins the STRICTER form, `> eye_height`, since
## check_greater is the only comparison the test harness offers -- so the pin
## refuses the equal case this comment would tolerate. That is the safe
## direction (an eye exactly level with the capsule top is the boundary this
## margin exists to stay off), not a disagreement to reconcile.
@export var slide_camera_drop: float = 0.81
## How fast the camera moves between standing and sliding height.
@export var crouch_lerp_speed: float = 9.0

## How long the per-model slide eye lift takes to LET GO, in seconds.
##
## ✅ The owner: "the lift is there through the slide and then vanishes the
## instant Shift is released -- the eye snaps back. It should ride the 0.5 s
## stand-up." It was easing on crouch_lerp_speed like everything else here, and
## at 9.0 m/s a 0.15 m lift is gone in a sixtieth of a second, which is a cut.
##
## A TIME rather than a rate, unlike its neighbours, and deliberately: the lift
## itself is per-model (BodyProfile.slide_eye_lift), so a fixed rate would take
## a different length of time on every body. Half a second is half a second.
##
## Matches Player.body_slide_exit_blend_time, which is the animation half of the
## same moment -- the body picking itself up out of a slide.
@export var eye_lift_release_time: float = 0.5

## ⚠️ PROJECT-DEFINED. How quickly the first-person eye hands over between its
## two clip-offset regimes (ignore the offset outside scripted moves, follow it
## inside -- see Player._camera_head_offset()). A time constant; near 0 snaps.
## Exists because the hand-over used to be binary and the owner saw it:
## "StepUp应用往后0.2m的偏移没有过渡，进入退出时会闪一下."
@export var scripted_eye_offset_blend_time: float = 0.2

## How long the third-person camera takes to cross from one shoulder to the
## other, in seconds.
##
## ✅ The owner: "give the over-shoulder camera a bit of easing." It matters
## most for the wall run, which swaps sides on its own -- a shot that jumps
## across the body reads as a cut rather than as a camera move -- but the
## manual cycle wanted it too.
##
## A TIME rather than a rate, for the same reason as eye_lift_release_time
## above: third_person_right is a per-taste distance, so a fixed rate would
## take a different length of time at every setting.
@export var third_person_shoulder_time: float = 0.25

## Where the eye is pinned while dying WITH A BODY ATTACHED, in degrees.
## Positive looks up.
##
## ✅ The owner, after trying it: dying in third person and pressing V mid-clip
## "lines up really well with the animation". Of course it does -- a
## third-person death does not take the cinematic, so the eye runs the ordinary
## path and the head-follow carries it along with the death clip. That IS the
## effect; the only thing missing was somewhere to point.
##
## ⚠️ Only with a body. Without one there is nothing for the eye to follow, and
## DeathSequence's own scripted fall is still the answer -- see its play().
@export var death_pitch_deg: float = 25.0

## The same, in third person. ✅ The owner: "it should be -25 there, or the
## camera ends up underground."
##
## The geometry agrees. The camera hangs BEHIND the rig, so pitching the rig up
## swings the arm DOWN -- straight into the floor a dead body is lying on.
## Looking down swings it up, which is where a camera watching a body on the
## ground wants to be.
@export var death_pitch_third_person_deg: float = -25.0

## How far the first-person eye is lifted while dying, in metres.
##
## ✅ The owner: "the first-person death camera needs about 0.3 m of height
## compensation or it clips." The head-follow puts the eye exactly where the
## head bone is, and a body lying on the floor has its head ON the floor -- so
## the eye ends up inside it. The clip is right; the eye just cannot be quite
## that faithful to it.
##
## First person only. In third person the camera is metres away and has no such
## problem.
##
## ⚠️ THIS NUMBER IS COUPLED TO THE CLIP'S OWN OFFSET, and the coupling runs the
## opposite way to the obvious one. _camera_head_offset() SUBTRACTS the clip
## offset back out (Player, and test_clip_offsets.gd locks it), so raising the
## model does not raise the eye -- it leaves the eye where it was while the
## visible body climbs past it, putting the eye that much DEEPER inside the body.
## So a clip offset of +N metres wants this to go UP by N, not down.
##
## ✅ The owner raised LiftAir_Fall_Impact by 0.1 m and read the follow-up off
## fall_uncontrolled_eye_lift below (0.15 + 0.1 = 0.25). The intent was "+0.1";
## the base is this 0.3, not that 0.15.
## How far the eye may trail a SCRIPTED body turn in first person, in radians.
##
## ⚠️ HELD SHORT, and the reason is a first-person one throughout: a lag is a
## softening, not a detour. Past a certain size the eye is no longer trailing the
## turn, it is pointing somewhere else entirely -- in first person, at the inside
## of whatever the body is pressed against. Reported in play as the view lunging
## into the wall and then snapping back to the ledge. Anything bigger than this
## is better taken as a cut.
@export var scripted_yaw_max_lag: float = 0.35

@export var death_eye_lift: float = 0.4

## The same, during an uncontrolled fall, in metres.
##
## ✅ The owner: "the first-person uncontrolled-fall loop needs the same
## compensation as the death, about 0.15 m, or it clips."
##
## Same cause as death_eye_lift above and a smaller number for the same reason:
## LiftAir_Fall_Air is a body dropping horizontally with its hips at about
## 0.19 m, so the head bone the eye is following is close to the floor -- close
## enough to end up inside whatever the body passes.
@export var fall_uncontrolled_eye_lift: float = 0.15
## How fast the eye catches up after the body was lifted over a low obstacle
## (see Player.try_step_up). Exponential, so this is a rate, not a duration:
## ~12 settles a 0.35 m step in roughly 0.15 s, which reads as a stride. Lower
## it to make the lag more obvious, raise it toward a hard snap.
@export var step_smooth_speed: float = 12.0

## ⚠️ PROJECT-DEFINED. How fast the eye catches up when a MOVE turns the body,
## as opposed to when the player does.
##
## The two deserve different treatment, which is the same lesson the step
## follow taught: the eye does not have to track the capsule frame for frame.
## Under the player's own hand it must -- a laggy mouse is intolerable -- but a
## scripted turn is something happening TO the player, and snapping the view
## through it reads as a cut. The reach onto a ledge squares the body up to the
## wall, sometimes through tens of degrees, and did exactly that.
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
## skull, and the owner worked that out from a symptom rather than from the
## code: with a body attached, its NECK kept passing through the view during a
## run, while standing still and looking down was perfectly fine. Their reading
## is exactly right -- if the eye rode the head, the head could never reach it,
## so the clipping IS the measurement that it did not.
##
## Whatever fraction is not followed becomes RELATIVE motion between the eye
## and the skull it is meant to sit inside. Against a body that bobs its head
## 9 cm per stride (measured -- docs/feel-backlog.md 42), 0.15 gave the eye
## 1.3 cm of that and left the other 7.6 cm as head sliding through it.
##
## 1.0 is therefore the value that MEANS anything, and it now costs nothing to
## use: what is followed is the head's DISPLACEMENT FROM ITS REST POSE, not its
## absolute position, so the eye keeps wherever it was placed -- eye_height,
## and in practice a little ahead of the neck, as first-person games place it
## -- and only inherits the motion. (Before, following at 1.0 would have parked
## the camera on the head node's own origin and thrown that placement away.)
##
## The honest cost is the bob itself: at 1.0 you inherit the whole of whatever
## the body's animation was authored with. For the owner's current body that is
## 9 cm, against the 1-3 cm a first-person view tolerates -- not a setting to
## fix but a fact about a clip authored to be watched from behind. Their own
## words: an animation not made for first person is very hard to keep a
## straight face through. The answer there is a body whose motion was authored
## for first person, or a third-person view -- not a fraction of this one,
## which only trades nausea for clipping.
##
## 0.0 opts out entirely and restores the purely procedural eye (eye_height
## plus bob/dip/crouch), bit-for-bit what every body-less setup already gets.
@export var camera_head_follow_strength: float = 1.0
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

## How fast a SCRIPTED LOOK SWEEP crosses the fan, in radians per second.
##
## Different from scripted_yaw_catchup_speed above, which is about the eye
## catching up to a body that moved under it. This one is the eye itself being
## moved -- Q during a wall run swings the view a quarter turn without touching
## the body, so there is no lag to bleed off, only a view to carry across.
##
## ✅ DERIVED FROM A MEASUREMENT. Q during a wall run carries the view through
## its 90 degree fan in 0.2 s, which is 7.85 rad/s.
##
## Third value for this field, and the history is worth keeping because the
## first correction was right and the second was the eye being asked to do a
## stopwatch's job. 6.0 was a guess. 9.0 came from the owner asking for
## two-thirds of that duration, by feel. 5.24 came from a first stopwatch
## reading of "a little under 0.3 s", which turned out to be the eye again --
## the timed figure is 0.2 s, and lands right beside the by-feel adjustment.
@export var look_sweep_speed: float = 7.85

## How fast the yaw fan's edge is eased in to meet a view that is already
## outside it, in radians per second.
##
## Only the fan MOVING produces that situation -- a wall run re-centring its fan
## on the wall it just attached to, or carrying it round a curve. A player
## pushing against an edge that has not moved is clamped hard, as always.
##
## ⚠️ PROJECT-DEFINED, and the same idea as pitch_recover_speed on the other
## axis. Exponential, so a rate: ~8 carries a 57 degree correction -- the widest
## a wall-run attach can produce -- in about a third of a second.
@export var look_settle_speed: float = 8.0

## How far the eye banks through a vault, at the middle of the arc.
##
## ⚠️ PROJECT-DEFINED as a MAGNITUDE. The owner's account of the original is
## qualitative -- "the camera tilts slightly as it traces a graceful arc over
## the obstacle" -- so this is set to be felt rather than noticed. Eased in and
## out across the vault's own duration, so it is never a step.
##
## THE SIGN NOW FOLLOWS THE ANIMATION, and it was flipped to do so.
##
## The original plants the LEFT hand -- 05 §5.7's table records bLeftHandIK on
## both middle-tier rows -- and this value was chosen for that, back when there
## was no visible body for it to disagree with. The animation pack's
## SafetyVault plants the RIGHT hand, no left-handed vault exists anywhere in
## either pack, and mirroring a clip is a Blender job rather than a line of
## code.
##
## ✅ So the owner's call: flip the camera instead. A bank that leans the
## opposite way from the arm you can see is worse than one that leans the
## "wrong" way against a game nobody is holding this one next to. Flip it back
## the day a left-handed clip exists.
@export var vault_roll_deg: float = -7.0

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
## A DEBUG VIEW FIRST. The owner's reason for wanting one is the same one
## docs/asset-candidates.md gives as the first prerequisite for any character
## model: a first-person game cannot show you its own body, so nothing about
## the animation, the mount height, or the parkour poses can be checked from
## inside it. Watching your own vault from outside is how you find out it looks
## wrong. Not a tuned over-the-shoulder framing -- placed to SEE the body, and
## the owner's own scoping applies: "先跑起来", get it running, then adjust.
@export var third_person_right: float = 0.6
@export var third_person_up: float = 0.35
@export var third_person_back: float = 3.0

@export var third_person_min_fraction: float = 0.15

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
## ✅ THE OWNER: "写个shader让游戏里的阴影颜色都带点这种偏蓝的感觉" (Mirror's
## Edge). This is the cheap v1 (docs/superpowers/specs/2026-08-25-menu-design.md,
## "顺带的氛围实验"): shadowed ground is lit almost entirely by ambient light in
## this renderer, so tinting ambient blue reads as cold shadows without a
## full-screen grading shader.
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

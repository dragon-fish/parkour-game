class_name Player
extends CharacterBody3D

# Owns the shared movement data and the movement primitives. It deliberately
# contains no transition logic — that belongs to the moves.
#
# Move names live on Move, not here: Player references the move classes, so
# the moves must not reference Player back.

var config: MovementConfig
var input_source: InputSource

## Whether clicking into the viewport hands the pointer back to this body.
##
## MUST BE FALSE IN THE ANIMATION LAB. There the body is a recording being
## watched, not a character being played, and every click belongs to the
## observer camera rather than to the body. Left true, the first click on
## the 3D view re-captures the cursor and the panel becomes unreachable.
var owns_mouse := true
var move_manager: MoveManager

## Downward speed at the moment of the most recent landing. Read by CameraRig.
var last_landing_speed: float = 0.0
## True when the most recent landing was a roll. Read by the camera and HUD.
var last_landing_rolled: bool = false
## Accumulated fall height the most recent landing was judged on -- i.e.
## fall_tracker.fall_height read the instant before set_grounded() reset it.
## Exists because that value is otherwise unobservable from outside the same
## physics tick: the counter is gone by the time anything else runs. Set by
## FallingMove alongside last_landing_rolled.
var last_landing_fall_height: float = 0.0
## Last polled input, exposed for the debug HUD.
var last_input: MoveInput = MoveInput.new()

var _input_locked: bool = false

## Set by WalkingMove/FallingMove the instant SpeedVaultConfig.should_commit()
## fires, immediately before returning SPEED_VAULT -- the committed variant a
## same-tick pick_variant() already matched, carried across the state
## transition since MoveManager.physics_update() has no other channel to pass
## data between two Move instances. Read once, by SpeedVaultMove.enter(),
## which clears it back to {} after reading. Empty is the normal REST value
## between vaults, not a pending one -- see SpeedVaultMove.enter()'s own
## "invent nothing" guard for what an empty dictionary at read time means.
var pending_vault_variant: Dictionary = {}
## True when the vault about to start was only admissible because
## AirborneMove._vault_speed_z() opened the falling-rescue window. Travels the
## same one-shot channel as pending_vault_variant above, and for the same
## reason: it is a fact about the ENTRY, and the move that reads it clears it.
var pending_vault_rescue: bool = false

## The ledge IntoGrabMove locked onto, handed across to GrabMove, on the same
## channel and for the same reason as pending_vault_variant above.
##
## GrabMove used to re-query on entry, which stopped working the moment
## IntoGrab started MOVING the body: by the time the reach finishes, the body
## sits 0.45 m back and most of a body-length below the lip, and the probe can
## no longer see the edge it was just carried to. The grab aborted on its first
## tick and dropped the player -- measured in play as IntoGrab -> Grab ->
## Falling across two frames.
##
## The reach already decided which edge this is. Deciding again from a worse
## vantage point can only disagree.
var pending_ledge: Dictionary = {}

## The InterestLines whose volumes the body is currently inside. Maintained by
## the lines themselves (InterestLine calls the two hooks below), never by a
## probe -- [ME:CONFIRMED 05 §5.6.5] any move that interacts along a line has
## an interest point in the original; anything geometrically self-evident does
## not.
var interest_lines: Array[InterestLine] = []

## The checkpoint the next respawn happens at, or null for the level's own
## spawn point. LAST TOUCHED WINS -- [ME:CONFIRMED] noclipping the original
## and flying back to suicide still respawns at the last checkpoint touched,
## so a loop's apparent nearest-point behaviour is just re-touching (see
## Checkpoint). Survives deaths and resets by design.
var active_checkpoint: Checkpoint = null

## Entry point for DeathVolume, duck-typed the same way touch_checkpoint() is.
##
## THE DEAD DO NOT DIE TWICE, for the same reason a corpse does not save: a
## body already on its way out through the fall cutscene must not have a second
## ending queued behind the first.
func die_in_volume() -> void:
	if _dying or move_manager.current_name == Move.FALL_UNCONTROLLED:
		return
	death_cause = DeathCause.VOLUME
	died_in_volume.emit()

func touch_checkpoint(checkpoint: Checkpoint) -> void:
	# THE DEAD DON'T SAVE. A checkpoint records "reached alive and in
	# control": a fatal dive that clips the volume on the way to the ragdoll
	# must not turn a death into a teleport -- DO NOT let it, or a player can
	# skip past a level by diving off a height straight through a checkpoint's
	# volume. Landing on one ALIVE still counts, which is the shortcut a
	# parkour game should reward.
	if _dying or move_manager.current_name == Move.FALL_UNCONTROLLED:
		return
	# The line only fires when the active respawn actually CHANGES --
	# pacing back and forth through the same gate stays quiet -- and only
	# for a checkpoint the level author gave a name.
	var changed: bool = checkpoint != active_checkpoint
	active_checkpoint = checkpoint
	if changed and checkpoint.display_name != "" and notice != null:
		notice.show_text("检查点 %s 已保存" % checkpoint.display_name)

func enter_interest_line(line: InterestLine) -> void:
	if not interest_lines.has(line):
		interest_lines.append(line)

func exit_interest_line(line: InterestLine) -> void:
	interest_lines.erase(line)
	# Leaving the volume is what re-arms the line -- see note_line_left().
	_lines_awaiting_exit.erase(line.get_instance_id())

## Entry points for ModifierVolume, duck-typed the same way touch_checkpoint()
## and enter_interest_line() are: the volume does not know what a Player is.
##
## `fresh_contact` separates WALKING IN from a volume renewing what it already
## put there -- the only distinction the volume itself can make, and it makes
## it already (_apply_entry_effects versus the refresh tick). What it means is
## the Player's business, and for one effect it means a great deal.
func apply_status(spec: StatusSpec, source: Object, priority: int,
		fresh_contact: bool = false) -> void:
	# TOUCHING THE WIRE AGAIN IS A NEW CUT. The stagger immunity exists so a
	# volume renewing four times a second cannot re-stagger the player on the
	# tick the lockout ends, leaving no tick in which to walk out. It was never
	# meant to make wire free to stand on: without this, the escape window is
	# also a window in which the player can hop off and back on unharmed, and
	# the wire becomes a platform to bounce along.
	#
	# The escape is untouched, because leaving is not entering. A player who
	# walks out during the window stays out; only one who chooses to come back
	# pays again, which is the whole point.
	if fresh_contact and spec != null and spec.effect == Status.Effect.STAGGER:
		_stagger_immunity = 0.0
	statuses.apply(spec, source, priority)

func remove_status(effect: int, subject: StringName) -> void:
	statuses.remove(effect, subject)

## The closest line of `kind` the body is inside, by distance from the body to
## the line's nearest point, or null. Two overlapping volumes are rare enough
## that "closest" is all the arbitration this needs.
func nearest_interest_line(kind: InterestLine.Kind) -> InterestLine:
	var best: InterestLine = null
	var best_distance: float = INF
	for line in interest_lines:
		if not is_instance_valid(line) or line.kind != kind:
			continue
		# A level may forbid one named line while its siblings stay usable.
		# Filtered HERE because this is the only place anything asks which
		# line is reachable; the six callers all come through it.
		#
		# ONLY THE CATCH IS REFUSED, never a ride already under way: LineMove
		# stores its line on entry and stops asking, so a rope forbidden under
		# a player already hanging from it does not drop them.
		if statuses.is_line_blocked(line.tag):
			continue
		var at: Vector3 = line.sample(line.closest_offset(global_position))["position"]
		var distance: float = at.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = line
	return best

## Whether the player is standing on something. DECLARED by the active state
## rather than read from is_on_floor(), because scripted-move states drive the
## body's position directly and never call move_and_slide() — is_on_floor()
## would report whatever was true before the move began.
var grounded: bool = false

## World-space Y the player was last known to be resting on solid ground,
## refreshed every tick set_grounded(true) is declared (so it tracks a sloped
## or stepped floor, not just the very first tick of a Ground stint). Read by
## WallRunMove to bound how much height a chain of wall-jumps can add above
## real ground -- see its own comment on why that bound has to be measured
## from here rather than from a fixed reference.
var ground_reference_y: float = 0.0

## SENTINEL, not a real reading: -1.0 means "no landing pending", never an
## actual impact speed. A landing's impact_speed is itself a legitimate 0.0
## (e.g. a state arriving next that can land at rest) — callers must always
## branch on `>= 0.0`, never `> 0.0`, or a genuinely zero-speed landing gets
## silently treated as "nothing happened". Chose documentation over a
## parallel `bool` flag to keep consume_landing()'s single-float contract
## (matches the brief's declared interface) rather than widening it.
var _pending_landing: float = -1.0

## Number of set_grounded() calls made so far, ever. Read ONLY by MoveManager,
## which snapshots it when a move is entered and checks it has moved by the end
## of that move's first physics_update — that is how "a move DECLARES its
## grounded-ness" is enforced structurally instead of by convention. The
## absolute value is meaningless; only differences between snapshots are.
var grounded_declarations: int = 0

func set_grounded(value: bool) -> void:
	grounded = value
	grounded_declarations += 1
	if value:
		ground_reference_y = global_position.y
		# ANY ground contact resets the fall-height counter -- this is the whole
		# mechanism behind the community's drop-roll technique (03 §3.5): touch
		# down, and the accumulated height is gone before stepping off again.
		if fall_tracker != null:
			fall_tracker.reset(global_position.y)

## Clears `grounded` WITHOUT counting as a declaration. Called only by
## MoveManager, as the fail-safe half of the invariant above: a move that
## never declared must not go on inheriting the previous move's value — a
## WallRun that forgot the call would inherit Walking's `true` and refill coyote
## time every tick, i.e. infinite jumps. Deliberately not routed through
## set_grounded(), or the fail-safe would satisfy the very check it exists to
## keep reporting.
func clear_grounded_undeclared() -> void:
	grounded = false

## Reported by a state at the moment it detects a landing. impact_speed must
## be >= 0.0 — see the sentinel note on _pending_landing above.
func notify_landed(impact_speed: float) -> void:
	_pending_landing = impact_speed
	last_landing_speed = impact_speed

## Returns this tick's landing impact speed, or -1.0 if there was none — a
## real landing can itself be 0.0, so callers must check `>= 0.0`, not
## `> 0.0` (see the sentinel note on _pending_landing above). The event is
## consumed, so a landing can only ever be acted on once.
func consume_landing() -> float:
	var value := _pending_landing
	_pending_landing = -1.0
	return value

## Landing tiers, from 03 §3.1's confirmed TdMove_Landing thresholds. Read as
## fall HEIGHTS -- the original's own parameters are heights, and converting
## them to impact speeds (which is what this project used to do) is what
## erased the free band.
enum { TIER_FREE, TIER_SOFT, TIER_ROLLABLE, TIER_HARD }

## Accumulated fall height since the last ground contact. Built in setup().
var fall_tracker: FallTracker

## Temporary modifications a level has put on this player -- speed caps,
## forbidden moves, a forced view. Read through the query methods; nothing
## outside StatusList interprets an entry.
var statuses: StatusList

## Where speed_cap()'s scale has actually got to, as opposed to where the
## status list says it should be. Eased over pawn.speed_cap_blend_time so a
## level's speed change reads as a slow-down rather than a cut -- see
## _blend_speed_scale().
var _speed_scale: float = 1.0

## Seconds of stagger immunity still owed. Armed when a landing lockout lets
## go, so a level that keeps re-applying STAGGER cannot chain them.
var _stagger_immunity: float = 0.0

## Set by MoveManager on the tick it commits a stagger, so LandingMove can
## tell a wire cut from a hard landing and charge the momentum differently.
## One-shot: the reader clears it, same as pending_vault_variant.
var pending_stagger: bool = false

## Emitted on the touchdown that ends an uncontrolled fall. The fall itself is
## already lost by then -- this only tells whoever owns respawning that the
## body has finished arriving.
signal died_from_fall

## A volume the level marked lethal. Separate from died_from_fall because the
## two want different endings: that one earns the topple cutscene, this one is
## a curtain and a respawn, which is the entire reason a level uses it.
signal died_in_volume

## The ground-speed curve (02 §2.1/02 §2.5): layer 2 of the two-layer speed
## model, see SpeedEnergy's own header comment. Built in setup(), driven every
## tick by _update_speed_energy(). Every move that wants "top speed" reads
## speed_cap() below rather than config.pawn.ground_speed directly -- that
## field is now only the curve's own upper bound.
var speed_energy: SpeedEnergy

## Last tick's wish direction, for charging heading changes. Zero means "no
## input last tick", which is deliberately NOT a heading -- see
## _charge_turn().
var _last_wish_dir: Vector3 = Vector3.ZERO

## Time left in the stand-up after a slide.
##
## PROJECT-DEFINED FROM PLAY: a slide that ends with the player instantly
## back at full running speed makes sliding free, and the original visibly
## spends a moment getting back up. Two things happen while it runs -- the
## speed budget stops growing, so the ceiling is pinned at whatever the slide
## left it at, and the eye rises from crouch height over the whole window
## rather than snapping up with the capsule.
##
## Re-entering the slide is blocked over the same window, but by
## SlideConfig.redo_move_time through MoveManager's own gate rather than here.
var _slide_recovery_timer: float = 0.0

## The heading the body left the ground with, and how long it has been away.
## Turning is not billed in mid-air -- there is no traction to lose it
## through -- but a body that takes off facing one way and lands facing
## another HAS turned, and used to arrive owing nothing. Settled once, on
## touchdown.
var _takeoff_dir: Vector3 = Vector3.ZERO
## Ground speed at the last take-off. [ME:CONFIRMED] measured in the
## original: catching a rope resets the ride's entry speed to the ground
## speed at the moment of the last take-off -- wall-jumps in between change
## nothing, and a second rope resets to the same figure. Captured beside
## _takeoff_dir, read by ZiplineMove.enter().
var _takeoff_ground_speed: float = 0.0
## Per-LINE cooldowns (zipline, swing, ...): InterestLine instance id -> seconds left.
## Per CABLE, not per move: the owner measured rope-to-rope chaining in the
## original (release one rope, catch the next at once), which a move-name
## cooldown forbids. SameZipLineRedoMoveTime only ever guarded the SAME line.
var _line_cooldowns: Dictionary = {}
var _airborne_time: float = 0.0
## Temporary gravity multiplier for FREE FLIGHT -- [ME:INFERRED 05 §5.4] the
## original leans on exactly this: local gravity modification recurs across
## swing, barge and coil, and is a major source of its "floaty but
## controllable" feel. Lives on Player once rather than growing a copy per
## move. Consumed by Move.carry_ballistically() and
## AirborneMove.apply_air_physics(); the wall moves keep their own scalings.
var _gravity_multiplier: float = 1.0
var _gravity_window_left: float = 0.0

func apply_gravity_window(multiplier: float, seconds: float) -> void:
	_gravity_multiplier = multiplier
	_gravity_window_left = maxf(seconds, 0.0)

func effective_gravity() -> float:
	return config.pawn.gravity \
		* (_gravity_multiplier if _gravity_window_left > 0.0 else 1.0)

func _tick_gravity_window(delta: float) -> void:
	if _gravity_window_left > 0.0:
		_gravity_window_left = maxf(_gravity_window_left - delta, 0.0)

func landing_tier(fall_height: float) -> int:
	var pawn := config.pawn
	if fall_height < pawn.skill_roll_landing_height:
		return TIER_FREE
	if fall_height < pawn.soft_landing_height:
		return TIER_SOFT
	if fall_height < pawn.hard_landing_height:
		return TIER_ROLLABLE
	return TIER_HARD

## Fraction of horizontal speed a landing from `fall_height` keeps.
##
## BINARY, not a ramp. [ME:CONFIRMED 03 §3.1] a 4.95 m drop taken WITHOUT
## rolling costs nothing at all -- speed keeps climbing after touchdown --
## while ~7 m unrolled zeroes it outright and plays the knee-clutch animation.
## There is no partial band anywhere in between.
##
## DO NOT model this as a ramp with a roll acting as a partial discount (e.g.
## charging a little at 2.5 m, more at 4.0 m, a 35% roll discount above the
## soft band): below the threshold nothing is charged, and at or above it a
## roll is not a discount but a full cancellation.
##
## `skill_roll_landing_height` and `soft_landing_height` therefore take no part
## in this calculation -- they gate animation and whether a roll may trigger at
## all. landing_tier() still reports them for those consumers.
func landing_keep_ratio(fall_height: float, rolled: bool) -> float:
	if fall_height < config.pawn.hard_landing_height:
		return 1.0
	return 1.0 if rolled else 0.0

## Assigned in player.tscn. Optional so headless tests can run without one.
@export var camera_rig: CameraRig

## Assigned in player.tscn. Optional so hand-built test players still work.
@export var probes: Probes

## The player's own full-screen effect layer. Null in headless tests that build
## a bare Player, so every caller must guard.
@export var screen_effects: ScreenEffects
## The one-line text layer (checkpoint saves). Assigned by
## tools/player_builder.gd; optional so a hand-built test player without one
## simply stays silent.
@export var notice: Notice

## The visible character body to attach under BodyRoot at runtime, or null
## for none. Deliberately NOT wired by tools/build_player_scene.gd -- see
## BodyRoot's own comment there: a committed player.tscn can never reference
## a specific model, licensed or otherwise, so this is left for a LOCAL,
## untracked override to set (e.g. an inherited scene of player.tscn that
## points body_scene at an owner's own model) rather than for generator
## output to carry. Instanced once, in _ready(), by _attach_body(). A body
## is entirely optional: everything downstream (CharacterAnimator, the
## head-follow camera) is built to no-op cleanly with none attached, not
## merely "usually work" -- was pinned by tests/legacy/test_body_attachment.gd
## -- ARCHIVED by Task 1 and NOT in the running suite, so nothing enforces
## this today; restore the pin when the behavioural suite is rewritten.
## A whole body's worth of settings in one resource, applied over the
## body_* properties below before anything is attached.
##
## Every level used to repeat those properties on its own Player instance, and
## the owner had already been caught by that -- finding a mount offset right in
## one level and missing in another, with no memory of where it had been set. A
## profile is the one place a body is described; a level names it and nothing
## else.
##
## Null is entirely supported: the properties below are then whatever the scene
## set them to, which is how every body was configured before this existed.
@export var body_profile: BodyProfile

@export var body_scene: PackedScene

## Per-model correction for the mount point under BodyRoot, ADDED ON TOP of
## the automatic vertical placement body_mount_transform() derives from the
## capsule (see its own comment) -- not a replacement for it. Defaults to
## zero: a model authored with its own origin at its feet needs no
## correction at all once the automatic placement lands those feet at the
## capsule's bottom. A model whose own origin sits somewhere else (hips,
## centre of mass, whatever the source rig used) can be nudged into place
## here instead.
##
## Per-model, exactly like body_scene itself -- lives here, next to it, NOT
## in MovementConfig. MovementConfig is the tuning panel's domain and is
## about how the game FEELS; this is about which model is attached and how
## it sits, a fact about the asset, not a feel value anyone would want to
## dial while playing.
@export var body_mount_offset: Vector3 = Vector3.ZERO
## See CameraRig.eye_forward. Pushed there on body attach.
@export var body_eye_forward: float = 0.0

## Per-model facing/orientation correction for the mount point, in degrees
## about each local axis (same convention as Node3D.rotation_degrees).
## Defaults to zero: most models are authored already facing -Z, matching
## this project's own forward. A model exported facing the wrong way (or
## lying on its side) can be corrected here rather than by re-exporting the
## asset. Same per-model reasoning as body_mount_offset above -- lives on
## Player, not MovementConfig.
@export var body_mount_rotation_degrees: Vector3 = Vector3.ZERO

## EVERY VRM NEEDS Vector3(0, 180, 0) HERE. The VRM specification has models
## face +Z, Godot's forward is -Z, and godot-vrm does not reconcile the two.
##
## The symptom is not "the body faces backwards", which is why it costs time:
## it reads as the THIRD-PERSON CAMERA being on the wrong side, with the
## character apparently running in reverse. The camera is correct; the back
## it is framing is a face.
##
## Measured before the correction: the eye bones sat +0.023 behind the head
## bone and the toes +0.106 behind the foot, both positive, i.e. facing +Z.
## Both signs flip with the half turn.

## Uniform scale applied to the attached body, so a model authored at its own
## natural height can sit on this project's capsule without being rebuilt.
##
## The capsule is 1.8 m with the eye 1.66 m above the feet, both
## [ME:CONFIRMED] measured from the original -- and those are the numbers
## every threshold in the game hangs off (reach 1.87, vault ceiling 1.89,
## standing apex 1.24). They do not move to suit a model. But the MODEL does
## not have to be 1.8 m for its eyes to land at 1.66: an anime character
## built at a normal height and scaled up a few percent reads as itself,
## whereas one actually modelled at 1.8 m reads as Attack on Titan.
##
## Their VRoid test export measured 1.535 m to the eye bones, so 1.081 -- eight
## percent, invisible in first person, where there is no absolute-scale
## reference in view at all.
##
## Scale the EYES onto eye_height, not the head bone: a humanoid Head bone's
## origin sits at the base of the skull, and matching that instead puts the real
## eyes above the camera. The same export reads 1.473 at the head bone and 1.535
## at the eyes -- 6 cm of error for asking the wrong bone.
##
## Feet stay pinned to the capsule bottom regardless: a feet-origin model scales
## about its own origin, which is exactly where the mount already places it.
@export var body_mount_scale: float = 1.0

## PLACING THE MODEL AGAINST THE CAMERA, not the other way round. The owner's
## rule, from how they mounted this project's other body: nudge the model back
## and up a little so the fixed camera ends up JUST IN FRONT OF ITS NECK --
## "most FPS games put the camera at the neck, not at the eyes".
##
## eye_height stays where it is through all of this. It is 1.66 m measured from
## the original, and while only the camera and the death sequence read it, it is
## the number the whole feel was calibrated against. What moves is the model.
##
## The two knobs trade against each other and neither wins outright:
##
##   * offset.y raises the neck toward the camera, and lifts the model's FEET
##     off the floor by the same amount.
##   * scale raises the neck too, by making the whole body bigger -- with no
##     float, but an anime character actually modelled tall is the thing the
##     owner called Attack on Titan.
##
## Splitting between them is why this body sits at scale 1.13 with a 7 cm lift
## rather than either extreme: 1.187 with no lift, or 1.081 with 15 cm of it.
## Measured result -- the neck lands 1 cm under the camera and 9.7 cm behind it.

## Optional scenes whose AnimationPlayers carry clips to MERGE into the
## attached body's own, so a model that ships no locomotion can borrow it from
## animation packs.
##
## A LIST, because no single free pack covers a parkour game: one library has
## the locomotion and the roll, another has the slide and the ledge climb, and
## neither has the other's. Merged in order, and the FIRST clip of a given name
## wins -- so put the pack whose version you prefer earlier.
##
## VRM is the case that forces this: the format carries no animation at all by
## design, so an imported VRM's AnimationPlayer holds only blend-shape
## expressions -- blink, happy, aa -- and the body simply stands there. The
## clips have to come from somewhere else.
##
## What makes the merge possible rather than merely convenient is Godot's
## import-time retargeting: a pack imported with a BoneMap against
## SkeletonProfileHumanoid has its tracks rewritten to address
## `%GeneralSkeleton:Hips` and friends -- a UNIQUE-NAME path plus profile bone
## names. Any other humanoid imported the same way answers to exactly those, so
## the clips are portable without touching them. See
## tools/build_ual_bone_map.gd.
##
## DO NOT ASSUME RETARGETING MATCHES REST POSES -- it only matches NAMES.
## Two rigs that disagree about what a T-pose is will play the same track to
## different-looking results. That is a real limit of doing this by import
## settings alone, not something this property hides.
@export var body_animation_libraries: Array[PackedScene] = []

## Which node inside `body_scene` the head-follow camera should track, as a
## path RELATIVE TO THE BODY INSTANCE'S ROOT. Empty (the default) falls back
## to _find_head_node()'s name search.
##
## The search is a BFS substring match, which is right for "point this at
## whatever model someone dropped in" and wrong the moment a model names an
## ancestor after the head too. The wine_fox body does exactly that: its real
## head sits at .../AllHead2/MHead/Head2/Head, and "AllHead2" both contains
## "head" and is three levels shallower, so the search claimed it -- leaving
## the camera tracking a group node above the neck rather than the head.
##
## Deliberately an override rather than a smarter search: preferring the
## deepest match instead of the shallowest would be a guess about every OTHER
## model's node naming, made to fix one model whose path is known exactly.
##
## Per-model, so it lives here beside body_scene and body_mount_offset rather
## than in MovementConfig -- a fact about the asset, not a feel value.
@export var body_head_path: NodePath

## A VRM NEEDS THIS SET. godot-vrm builds a BoneAttachment3D on the head
## bone -- which is exactly what the follow wants -- but the model also
## carries an ordinary mesh node called Head, sitting at the model's own
## origin, down at the FEET. The BFS search reaches the mesh first and the
## camera then tracks a point that never moves.
##
## Measured: with the search left to itself the eye travelled 0.0001 m over a
## run while the head bone travelled 12.7 cm; pointed at
## GeneralSkeleton/Head it travelled 0.1439 m.
##
## DO NOT blame BoneAttachment3D's update timing for a stuck eye -- it works
## correctly and measures the same 12.7 cm once the right node is read. The
## defect is entirely which node gets picked.

## The travel speed, in m/s, at which this body's locomotion clips read as
## natural -- i.e. where CharacterAnimator leaves the playback rate at 1.0 and
## scales around. Zero disables the scaling entirely and leaves every clip at
## its authored pace.
##
## Defaults to pawn.ground_speed's own value so an unconfigured body starts
## neutral: normal running plays the clip at the rate its author intended, and
## only departures from that pace stretch or compress it. It is a fact about the
## CLIP's cadence, though, not about this project's speeds -- a body whose run
## was authored for a slower character wants a lower number here even though
## nothing about the movement changed.
##
## Per-model, so it sits here beside body_scene rather than in MovementConfig,
## for the same reason body_mount_offset does.
## Per-clip correction to where the body sits. See BodyProfile.clip_offsets,
## which is where this comes from and where the reasoning lives.
@export var body_clip_offsets: Dictionary = {}

## Per-clip offsets that change over the clip AND with the obstacle, keyed by
## hand in the animation lab.
##
##     { clip_name: [ { "h": 1.2, "w": 0.4, "keys": [ {"t":, "pos":, "rot":} ] } ] }
##
## ONE CURVE PER CLIP IS NOT ENOUGH: the same clip plays against a 0.9 m sill
## and a 1.8 m parapet, against a 0.1 m rail and a 2 m ledge, and the pose is
## wrong in a different direction each time -- a body that clears a thin rail
## cleanly clips a wide one, at the same moment of the same animation. The
## saved data therefore keys one curve per (height, width) combination, and
## the running game always looks up the nearest one to apply.
##
## NEAREST, NOT EXACT, and deliberately: the grid is a sample of a continuous
## space, so a wall 1.13 m tall has to borrow from the nearest thing that was
## actually authored. Nothing in a level will ever land on a grid point.
@export var body_clip_curves: Dictionary = {}

## The obstacle the current move is working against: (height, width) in metres,
## or a negative height when there is none.
##
## Declared by the MOVE rather than measured here, for the reason
## docs/camera-authority.md gives about the camera: the mover knows what it
## probed, and anything reconstructing it afterwards is guessing.
var active_obstacle: Vector2 = Vector2(-1.0, 0.0)

## Which PART of each clip to play. See BodyProfile.clip_timings, and
## apply_clip_timing() for what it does with it.
@export var body_clip_timings: Dictionary = {}

@export var body_run_reference_speed: float = 7.2

## How long one clip cross-fades into the next, in seconds. Zero restores the
## hard cut this project had before.
##
## Without it every change of state is a CUT, and Godot makes that worse than
## it sounds: AnimationNodeStateMachinePlayback.travel() "follows the shortest
## path", and "if the path does not connect from the current state, the
## animation will play after the state teleports" -- with reset_on_teleport
## defaulting to true, so the incoming clip also restarts from frame zero. A
## limb mid-swing jumps to wherever the next clip's first frame puts it.
##
## The owner spotted the surviving one directly: entering the run clip made the
## neck lurch forward. Their read is right that a lean into a run is good
## animation -- the defect is that it arrived in a single frame instead of over
## one.
##
## Per-model, so it sits here beside body_scene, for the same reason
## body_mount_offset does: how long a blend should take depends on how the
## body's clips were authored.
@export var body_animation_blend_time: float = 0.15

## How long the animation gate keeps a finished scripted clip on screen while
## an ordinary one is asking -- the grace window in which a SECOND scripted
## clip (the sandwich) may still claim the other slot directly instead of
## popping through "states". PROJECT-DEFINED DIAL. The transients this
## protects against live 1-3 ticks (measured; see CharacterAnimator._route()),
## so it is far shorter than body_animation_blend_time -- and the freeze it
## costs at the end of every scripted move shrinks with it. DO NOT reuse the
## full body_animation_blend_time window here, or a scripted move's end holds
## its last frame for the whole window, which reads as a visible freeze.
@export var body_gate_hold_time: float = 0.05

## How long a clip leaving a SLIDE cross-fades, which is longer than everything
## else.
##
## The owner's reason, and it is about the move rather than the animation: a
## slide ends into a recovery the player cannot act through (slide.recovery_time
## is a second), so the body coming out of it should look like it is picking
## itself up, not like it changed its mind. At the ordinary 0.15 s the stand-up
## is over well before the lockout is, and the mismatch reads as the animation
## being ahead of the character.
@export var body_slide_exit_blend_time: float = 0.5

## How long a slide cross-fades into a CROUCH, as opposed to into a stand-up.
##
## Between the other two on purpose. A slide into a crouch is continuous -- the
## body stays down, so it does not need the half second the stand-up does -- but
## the owner found the ordinary 0.15 s cut too abrupt for a change of pose that
## large. Twice the base, which is where 0.3 comes from.
@export var body_slide_to_crouch_blend_time: float = 0.3

## Raises the eye during a SLIDE, in metres, for THIS body only.
##
## NOT A FUDGE FOR A BAD ASSET -- the price of a correct decision, which the
## owner spotted themselves: "being blocked by the chest means the camera is at
## the NECK rather than the eyes, so the last adjustment was right."
##
## It follows. A neck-height eye is inside the ribcage the moment the body goes
## prone, and the slide clip is genuinely prone -- the head drops 1.27 m and
## ends 40 cm off the floor. Everything here is behaving as designed; the design
## simply has this consequence, and something has to absorb it.
##
## SLIDE ONLY, on the owner's correction: an ordinary crouch does not put the
## chest anywhere near the eye, and lifting there would just be wrong. The slide
## clip is the one that goes properly prone -- the head drops 1.27 m against the
## crouch's 0.74.
##
## Per-model rather than global because how much it takes depends on the body's
## own proportions, and zero for a body whose chest never reaches the eye.
@export var body_slide_eye_lift: float = 0.0

## The clips whose EXIT gets the longer fade above. Only the slide, because it
## is the only move here whose recovery outlasts an ordinary transition.
const _SLOW_EXIT_CLIPS: Array[StringName] = [&"Slide", &"Slide_Exit", &"sneak"]

## Clips in which the body is already LOW. Leaving a slide for one of these is
## not a stand-up, so it does not get the long fade: the owner's point is that
## a slide into a crouch is continuous -- the body simply stays down -- while a
## slide into a run is the picking-yourself-up the half second exists for.
const _CROUCHED_CLIPS: Array[StringName] = [
	&"Slide", &"Slide_Start", &"Slide_Exit", &"sneak", &"sneaking",
	&"Crouch_Idle", &"Crouch_Fwd",
]

## Locomotion clips that also get a REVERSED twin in the graph, for walking
## backwards. A body that has the clip gets both; one that does not gets
## neither.
##
## Why a twin rather than a negative time scale: AnimationNodeTimeScale
## documents reversal, but a negative value has a long tail of reported trouble
## with LOOPING clips -- godotengine/godot#27215 is exactly "plays backwards,
## then rewinds to the beginning and stops" -- and every clip here loops. That
## issue was closed as `archived` during the 3.x-to-4.x cleanup rather than
## fixed. An AnimationNodeAnimation with play_mode = PLAY_MODE_BACKWARD reaches
## the same result without a negative scale ever existing.
##
## A reversed forward-run is not a backward-run: the foot contacts and the
## arm swing are both wrong, and no amount of blending hides that. Accepted
## as the cheap approximation anyway, because running backwards while the
## legs run forwards reads even worse.
const _REVERSIBLE_CLIPS: Array[StringName] = [
	&"run", &"Walk", &"Sprint", &"Walk_Carry", &"sneak", &"Crouch_Fwd",
]

## Suffix marking the reversed twin of a clip. Read by CharacterAnimator, which
## strips it to find the clip a name really refers to.
const BACKWARD_SUFFIX := "_Backward"

## The instance of body_scene actually attached under BodyRoot, or null if
## none. Exposed as a plain var (not just a BodyRoot child lookup) so tests
## and other systems can inspect what got attached without reaching into
## BodyRoot's children by name.
var body: Node3D = null

## The head- or neck-shaped node found in `body` for the head-follow camera
## to track, or null if there is no body or nothing in it matched. Resolved
## once, in _attach_body(), by _find_head_node() -- see its own comment for
## the search. Read every physics tick by _physics_process() to feed
## CameraRig.set_head_offset()/clear_head_position().
var head_node: Node3D = null

## The body's mount transform as captured at attach time -- see _attach_body().
var _body_mount: Transform3D = Transform3D.IDENTITY
## Where the per-clip offset has actually eased to, as position and degrees.
## Eased rather than snapped: the clips themselves cross-fade, and an offset
## that jumped on the frame the clip changed would be a visible step in the
## middle of a smooth blend.
var _clip_offset_position: Vector3 = Vector3.ZERO
var _clip_offset_rotation: Vector3 = Vector3.ZERO
## 0..1: how much of the clip offset the EYE currently follows. Driven every
## tick by _drive_clip_offset(); read by _camera_head_offset().
var _scripted_eye_follow: float = 0.0
## True while a move has declared the body FOLDED -- see set_body_folded().
var _body_folded: bool = false
## How far the model has actually eased down for that fold, in metres.
var _fold_drop: float = 0.0
## True while a SCRIPTED move owns the body's height, so the clip's own
## vertical hip motion must not be added on top. See set_clip_lift_cancelled().
## How much of the clip's own hip lift survives. See set_clip_lift_kept().
var _kept_clip_lift: float = 1.0
## How much of that cancellation is actually being applied, 0 to 1, eased.
##
## DO NOT SNAP THIS. Switching the cancellation off instantly takes the lift
## from 0.825 m to zero in one frame -- a clip cut short at 44 percent still
## has its hips up when the move hands off -- and the camera visibly jumps up
## a notch the instant the vault ends. Ease it the same way body_fold_drop is
## eased.
var _lift_cancel_amount: float = 0.0
## OFF BY DEFAULT: the ragdoll generated from a rig at runtime gets you as far
## as "playable and funny" and no further. What is left needs per-joint angle
## ranges authored by hand (a knee bends one way, an elbow the other),
## collision exclusions between neighbouring limbs, and a skeleton that is not
## scaled -- see Ragdoll's own notes. Every shipped ragdoll is hand-built for
## its model; this project has not done that work.
##
## Kept behind a switch rather than deleted: it works, it is entertaining, and
## flipping this is the whole cost of having it back.
@export var ragdoll_enabled: bool = false

## Built lazily on the first death, and only for a body whose bones are named
## like a humanoid. Null everywhere else, which is every non-VRM body this
## project has ever attached.
var ragdoll: Ragdoll = null
## The skeleton and Hips index, resolved once at attach -- this is read
## every tick and find_bone() is a string search.
var _skeleton: Skeleton3D = null
var _hips_bone: int = -1

## Where head_node sat, in this Player's local space, BEFORE any animation had
## a chance to move it -- captured once in _attach_body(). The head-follow
## camera reports displacement from here rather than an absolute position, so
## the eye keeps its own resting place and only inherits the head's MOTION.
## See CameraRig._head_local_offset.
##
## Captured at attach, not on the first physics tick: _wire_body_animation()
## activates the AnimationTree immediately, so by the first tick the pose has
## already moved and "rest" would be one arbitrary frame of a run cycle.
var head_rest_local: Vector3 = Vector3.ZERO


## Drives the attached body's arms onto whatever the body is actually touching.
## Built in _attach_body() when the body has a humanoid skeleton, and null
## otherwise -- every call on it is guarded, so a body without one is simply a
## body whose hands follow its animation. See HandIK's own header.
var hand_ik: HandIK = null


## Turns the attached body's head toward where the camera is pointing. Built
## alongside the twist, and null for a body without a humanoid neck. See
## HeadLook's own header.
var head_look: HeadLook = null

## The world yaw the MODEL is currently showing, which is not always the body's
## own. See _drive_body_yaw().
var _visual_yaw: float = 0.0
## The swing's model lean (radians about the body's X), smoothed onto
## BodyRoot in _drive_body_yaw(). Set by SwingMove, zeroed on exit.
var _swing_pitch_target: float = 0.0
var _visual_yaw_started: bool = false

var _standing_height: float = 0.0

## Backing store for travel_speed(); see its doc comment.
var _travel_speed: float = 0.0

var _coyote_timer: float = 0.0

## Time left in the window that follows a step-up, during which leaving the
## floor is NOT a ledge exit. try_step_up() raises the body IN PLACE and lets
## move_and_slide() carry it forward onto the step over the next tick or two,
## so the whole manoeuvre is airborne by construction. Moves that bail to
## Falling the moment they leave the floor were therefore cancelling
## themselves on clutter they had successfully ridden over.
var _step_grace_timer: float = 0.0

## Last tick's grounded reading, for try_step_down(). A body that was already
## airborne when the tick began is falling, and must not be set back down on
## whatever happens to be within a step below it.
var _was_grounded: bool = false

## DEBUG CHEAT, toggled with T. Frees the body from collision and gravity and
## flies it along the view at a fixed speed, so a spot deep in a level can be
## reached without replaying the route to it. This project has no checkpoints,
## which is what makes it worth having.
##
## The move manager is pinned to Walking throughout and simply not ticked --
## the body is driven directly here instead -- so nothing downstream has to
## learn about a state that only exists for testing.
var noclip: bool = false

## DEBUG. Fast enough to cross the arena without waiting, slow enough to
## stop where you meant to.
const NOCLIP_SPEED := 21.0
var _jump_buffer_timer: float = 0.0
## Buffers a crouch-key press for roll_trigger_time (05 §5.2's confirmed
## TdPawn.RollTriggerTime, extremely forgiving next to the genre's usual
## 0.1-0.2 s). Renamed from _crouch_buffer_timer: GBA_Crouch is one key with
## five outlets and only three discriminators -- airborne/grounded, speed,
## accumulated fall height -- so the buffer itself is not "about crouching",
## it is the single press every one of those outlets reads. See
## walking_move.gd's own table comment for the full resolution.
var _roll_buffer_timer: float = 0.0

## Seconds a Q press stays alive waiting for a move that can use it.
##
## EXISTS BECAUSE A Q PRESS AT THE START OF A WALL RUN WAS BEING DROPPED: the
## press arrives before the run has a fan to sweep across, and without a
## buffer it is simply lost. Same shape as the jump buffer above, and the
## same reason: the player pressed at the moment that FELT right, and the
## game was a few frames from being able to honour it.
var _turn_buffer_timer: float = 0.0
## True when a state has asked for the standing capsule back but a ceiling was
## in the way. See request_standing_capsule().
var _standing_restore_pending: bool = false

## Which side the current wall is on: -1 left, +1 right, 0 none. Read by the
## camera to decide which way to roll.
var wall_side: int = 0

@onready var _stand_clearance: ShapeCast3D = get_node_or_null("StandClearance")

func standing_height() -> float:
	return _standing_height

## Live height of the collision capsule right now — shrunk while Slide or
## Crouch (or any future state that calls set_capsule_height()) is active,
## the standing height otherwise. Read fresh via $CollisionShape3D rather
## than cached, mirroring set_capsule_height()'s own reasoning below: this
## can run before setup() has necessarily duplicated the capsule into a
## per-instance copy. The single source of truth both body_mount_transform()
## (the body's feet-alignment, read once at attach time before any resize
## has happened) and _physics_process()'s camera crouch cue (read every
## tick) share, so a future low state needs nothing more than calling
## set_capsule_height() to get both right for free — see
## _physics_process()'s own comment on the camera cue.
func current_capsule_height() -> float:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return 0.0
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return 0.0
	return capsule.height

## Live radius of the collision capsule. Read by try_step_up(), which has to
## know how far forward its landing probe must reach before the capsule's own
## centre clears an obstacle's face -- see its own comment.
func current_capsule_radius() -> float:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return 0.0
	var capsule := shape_node.shape as CapsuleShape3D
	return capsule.radius if capsule != null else 0.0

## Pure placement arithmetic -- the ONE formula both the runtime attach path
## and BodyRoot's editor-only preview (see body_root.gd) use, and the ONLY
## place it is written down. Deliberately STATIC, and deliberately taking
## plain values rather than reading anything off `self`: BodyRoot is a @tool
## script that runs while the *editor* has Player as a PLACEHOLDER instance
## (Player is intentionally not @tool -- see its own header comment), and a
## placeholder instance refuses every INSTANCE method call ("Attempt to call
## a method on a placeholder instance" -- the exact crash this fixes). A
## static call needs no instance at all: `Player.compute_mount_transform(...)`
## runs this same compiled code whether Player is a live object or a
## placeholder, so BodyRoot can call it directly instead of maintaining a
## second copy of the formula that could quietly drift from this one.
static func compute_mount_transform(capsule_height: float, mount_offset: Vector3, 		mount_rotation_degrees: Vector3, mount_scale: float = 1.0) -> Transform3D:
	var origin := Vector3(0.0, -capsule_height * 0.5, 0.0) + mount_offset
	# Scale goes into the BASIS, with the origin untouched. A model whose own
	# origin is at its feet therefore scales about its feet, which is precisely
	# where this mount has already put it -- so changing the scale never lifts
	# the body off the floor or sinks it into one. Guarded against zero and
	# negatives: either would collapse or mirror the body, and neither is
	# something anyone means by "how tall".
	var basis := Basis.from_euler(mount_rotation_degrees * (PI / 180.0)) 		.scaled(Vector3.ONE * maxf(mount_scale, 0.001))
	return Transform3D(basis, origin)

## The local Transform3D the visible body sits at under BodyRoot: vertical
## placement derived from current_capsule_height() -- never hardcoded -- so
## a feet-origin model's feet land exactly at the capsule's bottom, and this
## stays correct if the capsule is ever resized in the editor or the
## generator. Read (and applied) exactly once, at attach time --
## _attach_body() runs from _ready(), before any state has had a chance to
## shrink the capsule for a slide or a crouch -- so this always captures the
## STANDING height, matching how the body's own crouch already reads
## (through its animation, not by physically lowering the mount point).
## body_mount_offset/body_mount_rotation_degrees add whatever per-model
## correction is still needed on top of that automatic placement. Just a
## thin instance-side wrapper around compute_mount_transform() above, which
## is the actual shared logic -- see its own comment for why that split
## exists.
func body_mount_transform() -> Transform3D:
	return compute_mount_transform(current_capsule_height(), body_mount_offset, 		body_mount_rotation_degrees, body_mount_scale)

## True when a standing body would FIT with its feet at `feet_point`.
##
## THE SAME SHAPECAST, MOVED. has_headroom() below asks the question here, and
## this asks it somewhere else -- which is all "is there room to pull up onto
## this ledge" ever needed. A first attempt wrote a fresh upward raycast in
## Probes for that, and it did not work; this mechanism was sitting on Player
## the whole time, doing the job for the crouch-to-stand restore.
##
## A SHAPE, not a ray, and that is the point: a body has width. A ray fired up
## from an edge threads between two slabs that a body could never fit through,
## and it misses a cap it grazes.
##
## Restored afterwards rather than left where it was put: the node's resting
## place is the body's own centre, and has_headroom() reads it there every time
## a crouch tries to stand up.
func fits_standing_at(feet_point: Vector3) -> bool:
	if _stand_clearance == null:
		return true
	var resting: Vector3 = _stand_clearance.global_position
	# Lifted a hair clear of the surface being stood ON. A shapecast resting
	# exactly on a face reports a collision with it, so testing "would a body
	# fit with its feet here" against the very ledge those feet are on comes
	# back as blocked -- which would refuse every mantle in the game.
	const CLEARANCE_LIFT := 0.03
	_stand_clearance.global_position = feet_point 		+ Vector3.UP * (standing_height() * 0.5 + CLEARANCE_LIFT)
	_stand_clearance.force_shapecast_update()
	var blocked: bool = _stand_clearance.is_colliding()
	_stand_clearance.global_position = resting
	return not blocked

## True when the standing-size capsule fits where the body currently is.
## Tests that build a Player by hand have no probe node, so absence means yes.
func has_headroom() -> bool:
	if _stand_clearance == null:
		return true
	_stand_clearance.force_shapecast_update()
	return not _stand_clearance.is_colliding()

## Resizes the capsule while keeping its BOTTOM fixed relative to the body
## origin, so footing and is_on_floor() are unaffected by the change.
## Looks the node up live via $CollisionShape3D rather than caching it in an
## @onready var: setup() (below) calls the same lookup before this player's
## own _ready()/onready pass has necessarily run — TestWorld.build() calls
## setup() on the same tick a player enters the tree, and add_child() does
## not run @onready/_ready() synchronously, so it has not fired yet. Verified
## against both a hand-built player and one instantiated from player.tscn
## (tests/world_fixture.gd uses the latter): @onready vars are still null
## immediately after add_child() returns in either case. An @onready-cached
## reference would be null at that point.
func set_capsule_height(height: float) -> void:
	# Any explicit resize supersedes a restore that was still owed — most
	# importantly a fresh slide entered while one was pending, which must not
	# later have the player stood up mid-slide by the deferred restore.
	_standing_restore_pending = false
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return
	if _standing_height <= 0.0:
		_standing_height = capsule.height
	capsule.height = height
	# THE FEET STAY PUT, ALWAYS.
	#
	# DO NOT ANCHOR THE CAPSULE AT THE CROWN so a vault can hold the head level
	# instead of the feet: with the collision anchored at the head, a landing
	# body rests its WAIST on the ground, and the standing-capsule restore then
	# grows the capsule 0.9 m downward -- half the character underground the
	# moment a deferred restore fires. The collision belongs on the floor the
	# body is standing on. It is the MODEL and the EYE that follow the
	# shortened capsule's top; see body_fold_drop().
	shape_node.position.y = -(_standing_height - height) * 0.5

## Resizes the capsule about its own CENTRE: the feet rise by exactly as much
## as the headroom grows. Coil's, and nothing else's.
##
## ✅ MEASURED, not inferred. The owner read it straight off ME Tweaks'
## collision-box visualiser in the original: "胶囊缩放不是以头为准！是以中心
## 为准！也就是说同时会增加头顶的空间". A coil and a crouch shrink the SAME
## capsule to the SAME height (CoilConfig.capsule_height); the anchor is the
## entire difference between them.
##
## ⚠️ WHY THIS IS A SECOND FUNCTION AND NOT A PARAMETER ON THE ONE ABOVE.
## An anchor parameter lived on set_capsule_height() for one commit and was
## removed -- see its own note: a crown-anchored vault left a body resting its
## WAIST on the ground, and the deferred restore then grew the capsule 0.9 m
## downward, putting half the character underground. The owner caught it in
## play.
##
## That failure is still reachable from here, and CoilMove is what closes it:
## a centred capsule grown back to standing drops its floor by half the shrink,
## so the coil ends itself the moment the STANDING feet would reach a surface
## (fits_standing_at(), which the move asks every tick) rather than when the
## shrunken ones do. Kept apart from set_capsule_height() so that obligation
## travels with the one move that has taken it on, instead of being an argument
## any caller can pass.
func set_centred_capsule_height(height: float) -> void:
	# Same supersede-a-pending-restore rule as set_capsule_height(), and for
	# the same reason.
	_standing_restore_pending = false
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		return
	if _standing_height <= 0.0:
		_standing_height = capsule.height
	capsule.height = height
	# THE CENTRE STAYS PUT. The shape's origin IS the body's origin (the
	# capsule sits at position zero in player.tscn), so centring the shrink is
	# simply leaving the offset alone -- and setting it explicitly rather than
	# leaving it untouched is what returns the body from a crouch or a slide,
	# whose own resize left this negative.
	shape_node.position.y = 0.0

## Asks for the standing capsule back, honouring the roof. Restores it at once
## when there is room, otherwise records that a restore is OWED and performs it
## on the first tick headroom permits.
##
## This exists because gating the restore on the caller's side cannot work: a
## slide that runs off a ledge must transition to Air whether or not there is a
## ceiling — a player who walks off an edge falls, roof or no roof — so that
## exit path cannot be headroom-gated the way the jump path is. Deferring at
## the CAPSULE instead covers every exit uniformly: jump, crouch release,
## speed decay, timeout, and walking off an edge mid-crawl alike can never
## spawn a 1.8 m capsule inside geometry.
func request_standing_capsule() -> void:
	if has_headroom():
		set_capsule_height(_standing_height)
	else:
		# Set AFTER the branch above, never before: set_capsule_height() clears
		# this flag, so ordering the two the other way round would drop it.
		_standing_restore_pending = true

## Silences input without stopping the move layer. The body keeps ticking --
## grounded declarations and transitions all run as usual -- it just reads a
## tick with nothing held, so WalkingMove's own friction brings it to rest.
## Used by the death cutscene, which owns the camera but must not leave the
## body drivable underneath it.
func lock_input() -> void:
	_input_locked = true

func unlock_input() -> void:
	_input_locked = false

## Whether input is currently being swallowed -- during the death cutscene, or
## an uncontrolled fall. Read by the crosshair, which hides itself when the
## player is not actually driving.
func is_input_locked() -> bool:
	return _input_locked

## Opens the stand-up window. Called by SlideMove.exit().
func begin_slide_recovery() -> void:
	_slide_recovery_timer = config.slide.recovery_time

## How far through the stand-up the body is, 1 at the instant the slide ended
## and 0 once it is over. Read by the camera to raise the eye, and by the speed
## budget to know it must not grow.
func slide_recovery_fraction() -> float:
	if config == null or config.slide.recovery_time <= 0.0:
		return 0.0
	return clampf(_slide_recovery_timer / config.slide.recovery_time, 0.0, 1.0)

func _service_pending_capsule_restore() -> void:
	if _standing_restore_pending and has_headroom():
		set_capsule_height(_standing_height)

func setup(cfg: MovementConfig, src: InputSource) -> void:
	config = cfg
	# Per-player half of SettingsStore (camera sensitivity/FOV) -- the
	# engine-wide half (window/audio) is applied once at boot by PauseUi.
	SettingsStore.apply_to_config(SettingsStore.load_settings(), config)
	input_source = src
	fall_tracker = FallTracker.new()
	speed_energy = SpeedEnergy.new(config.pawn)
	statuses = StatusList.new()

	# The capsule resource is shared by every instance of player.tscn, so
	# resizing it in place would let one player's slide shrink every other
	# player in the scene — including, in tests, worlds from previous cases.
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule != null:
		var owned := capsule.duplicate() as CapsuleShape3D
		shape_node.shape = owned
		_standing_height = owned.height

	# Godot's own floor snap, sized to a step rather than left at its 0.1 m
	# default. Walking DOWN a stair leaves the body briefly unsupported, and a
	# snap shorter than the step cannot catch it -- which is Walking/Falling
	# flickering the whole way down a staircase. Anything taller than a step is
	# a real drop and must be allowed to fall.
	floor_snap_length = config.pawn.max_step_height

	_build_moves()

	if probes != null:
		probes.setup(config, _standing_height * 0.5)

## Clears per-life transient state that outlives a single frame: the coyote,
## jump-buffer and roll-buffer timers, and the last landing speed CameraRig
## reads for its dip. Called on a manual reset (Arena's R key) so a leftover
## buffered jump from just before the reset cannot fire the instant the player
## respawns grounded, and so a landing dip from the old life cannot appear
## after a fresh spawn. Does not touch the move manager itself — callers
## restart that separately, and MoveManager.start() clears its own
## redo_move_time cooldowns (including the ledge re-grab one this function
## used to carry by hand) for exactly the same reason.
##
## grounded is also cleared here rather than left to whatever the previous
## life last declared: Arena.reset_player() teleports to spawn and then skips
## exactly one physics tick before the move manager resumes (see its own
## comment), and _tick_timers() runs on the very first re-enabled tick —
## before WalkingMove has had a chance to declare anything. Without this, that
## one tick reads last life's grounded value and can wrongly refill coyote
## time (if the old life ended airborne, a resting spawn would start with
## none) or wrongly withhold it (the reverse).
func reset_state() -> void:
	_coyote_timer = 0.0
	_step_grace_timer = 0.0
	_was_grounded = false
	_jump_buffer_timer = 0.0
	_roll_buffer_timer = 0.0
	_turn_buffer_timer = 0.0
	# Mirrors CameraRig.reset_state()'s own end_cinematic() call. A manual
	# reset (Arena's R key) can land mid-death-cutscene, and it bypasses
	# DeathSequence entirely -- so the unlock that sequence would eventually
	# have run never reaches a body that has already respawned. Without this,
	# the R key hands back a player who can see but cannot move until the
	# cutscene's timer happens to run out.
	_input_locked = false
	if fall_tracker != null:
		# A respawn is a ground contact for this purpose: baseline the counter
		# to wherever the body now stands, or the first tick after the teleport
		# scores the whole teleport distance as a fall.
		fall_tracker.reset(global_position.y)
	if speed_energy != null:
		speed_energy.reset()
	# A respawn is not a transition to watch: the ceiling starts where the new
	# life's statuses put it, with no slide inherited from the old one.
	_speed_scale = statuses.speed_scale() if statuses != null else 1.0
	_stagger_immunity = 0.0
	_last_wish_dir = Vector3.ZERO
	_takeoff_dir = Vector3.ZERO
	_takeoff_ground_speed = 0.0
	_line_cooldowns.clear()
	_gravity_window_left = 0.0
	_airborne_time = 0.0
	_slide_recovery_timer = 0.0
	wall_side = 0
	# A respawn teleports out of any volume without the area ever reporting
	# the exit, so the list is cleared here rather than trusted.
	interest_lines.clear()
	_visual_yaw_started = false
	_swing_pitch_target = 0.0
	if camera_rig != null:
		camera_rig.extra_eye_forward = 0.0
		camera_rig.extra_eye_lift = 0.0
	# A respawn teleport is not travel: leave the camera's speed cue at rest
	# rather than letting the first tick after the reset read the old life's.
	_travel_speed = 0.0
	last_landing_speed = 0.0
	last_landing_fall_height = 0.0
	grounded = false
	# Set directly rather than through set_grounded(true) (which would also
	# flip `grounded` back on, contradicting the line above): global_position
	# has already been moved to the spawn point by the time Arena.reset_player()
	# calls this (see its own comment on ordering), so this is the correct
	# fresh reference immediately, without waiting for WalkingMove's first
	# declaration a tick or two after the reset.
	ground_reference_y = global_position.y
	_pending_landing = -1.0
	# A reset teleports the player to a known-clear spawn, so a restore owed
	# from a slide under some ceiling is both stale and satisfiable right now.
	# request_standing_capsule() clears the flag on the way through, and
	# re-arms it in the impossible case that the spawn is itself blocked.
	_standing_restore_pending = false
	request_standing_capsule()

func _build_moves() -> void:
	move_manager = MoveManager.new()
	move_manager.player = self
	add_child(move_manager)

	# name -> [move instance, its own config]. One table instead of the
	# seven near-identical blocks this used to be, so a new move is one row.
	var table := [
		[Move.WALKING, WalkingMove.new(), config.walking],
		[Move.JUMP, JumpMove.new(), config.jump],
		[Move.COIL, CoilMove.new(), config.coil],
		[Move.FALLING, FallingMove.new(), config.falling],
		[Move.FALL_UNCONTROLLED, FallUncontrolledMove.new(), config.fall_uncontrolled],
		[Move.LANDING, LandingMove.new(), config.landing],
		[Move.SKILL_ROLL, SkillRollMove.new(), config.skill_roll],
		[Move.SLIDE, SlideMove.new(), config.slide],
		[Move.CROUCH, CrouchMove.new(), config.crouch],
		[Move.SPEED_VAULT, SpeedVaultMove.new(), config.speed_vault],
		[Move.INTO_GRAB, IntoGrabMove.new(), config.into_grab],
		[Move.GRAB, GrabMove.new(), config.grab],
		[Move.WALL_RUN, WallRunMove.new(), config.wall_run],
		[Move.WALL_CLIMB, WallClimbMove.new(), config.wall_climb],
		[Move.TURN_180, Turn180Move.new(), config.turn_180],
		[Move.ZIPLINE, ZiplineMove.new(), config.zipline],
		[Move.SWING, SwingMove.new(), config.swing],
		[Move.LADDER, LadderMove.new(), config.ladder],
	]
	for row in table:
		var move: Move = row[1]
		move.player = self
		move.config = config
		move.cfg = row[2]
		move_manager.add_child(move)
		move_manager.register(row[0], move)

	move_manager.start(Move.WALKING)

func _ready() -> void:
	# BEFORE the attach, and before anything reads a body_* property: the whole
	# point is that they hold the profile's values by the time they matter.
	if body_profile != null:
		body_profile.apply(self)
	if body_scene != null:
		_attach_body(body_scene)

## Takes a profile the SCENE did not carry, and attaches whatever body it names.
##
## EXISTS BECAUSE THE PROFILE CANNOT BE BAKED INTO A COMMITTED SCENE. The one
## this project plays with points at a licensed model that is not in the
## repository, so a generated main.tscn naming it would be a committed reference
## to a file most checkouts do not have -- and test_generated_scenes.gd, which
## compares the builder's output against what is committed, would fail on any
## machine without it.
##
## So the level asks at RUNTIME instead, the same way it asks for the sandbox
## and the calibration course: if the file is there, use it; if not, carry on
## with no body at all. See Arena._load_body_profile().
##
## _ready() has already run by then, which is the whole reason this is a method
## rather than a property write: apply() sets body_scene as one of the things it
## sets, so the attach has to be re-triggered afterwards.
func adopt_body_profile(profile: BodyProfile) -> void:
	if profile == null:
		return
	body_profile = profile
	profile.apply(self)
	if body_scene != null:
		_attach_body(body_scene)

## Instances `scene` under BodyRoot and wires up everything that depends on
## having a real body: the idle/run/jump AnimationTree (see
## _wire_body_animation()) and the head-follow camera's target node (see
## _find_head_node()). Does nothing -- not even instancing -- if BodyRoot is
## missing or `scene` fails to instance as a Node3D, so a malformed
## body_scene degrades to "no body" rather than crashing startup.
func _attach_body(scene: PackedScene) -> void:
	# DIAGNOSTIC. Arena._ready's own marks put 2383 of its 2393 ms inside
	# _load_body_profile, which is this. Cumulative, not per-step -- GDScript
	# lambdas capture by value. DO NOT DELETE THESE LOG MARKS -- log generously
	# here, and keep adding more as this path changes.
	var _began := Time.get_ticks_msec()
	var _mark := func(what: String) -> void:
		print("[load]     _attach_body %-24s %6d ms elapsed" % [what, Time.get_ticks_msec() - _began])
	var body_root := get_node_or_null("BodyRoot") as Node3D
	if body_root == null:
		return
	var instance := scene.instantiate()
	if not (instance is Node3D):
		return
	body = instance as Node3D
	body_root.add_child(body)
	_mark.call("instantiate + add_child")
	# CAPTURED, not recomputed. body_mount_transform() derives its height from
	# current_capsule_height(), which shrinks for a crouch or a slide -- and the
	# body is not supposed to move when that happens, because its own animation
	# is what shows the crouch. Reading it once here is what that guarantee has
	# always rested on; _drive_clip_offset() composes onto this cached copy
	# rather than asking again every tick.
	_body_mount = body_mount_transform()
	body.transform = _body_mount
	_merge_animation_library(body)
	_mark.call("_merge_animation_library")
	_wire_body_animation(body)
	_mark.call("_wire_body_animation")
	_skeleton = _find_skeleton(body)
	_hips_bone = _skeleton.find_bone(&"Hips") if _skeleton != null else -1
	# NOT BUILT HERE. Twelve rigid bodies and eleven joints are not free, and
	# most lives never end in one -- see Ragdoll for what it is and why it is a
	# one-way door.
	ragdoll = Ragdoll.new()
	head_node = _resolve_head_node(body)
	_attach_hand_ik(body)
	_mark.call("skeleton + ragdoll + hand IK")
	if camera_rig != null:
		camera_rig.eye_forward = body_eye_forward
	_attach_head_look(body)
	_mark.call("head look")
	if head_node != null:
		head_rest_local = to_local(head_node.global_position)

## Every clip name CharacterAnimator's _target_animation() knows how to ask
## for, across every state (see that function for the per-state fallback
## chains that pick among these). NOT every clip a body might carry -- only
## the ones this project's animation logic can ever ATTACH TO A NODE and
## travel() to. idle/run/jump are the near-universal three; sneak/sneaking/
## ladder_stillness are specific to the YSM/Blockbench ecosystem the owner's
## model comes from (see the animation-vocabulary report) and are simply
## absent, not broken, on any other body.
const _KNOWN_ANIMATION_CLIPS: Array[StringName] = [
	&"idle", &"run", &"jump", &"sneak", &"sneaking", &"ladder_stillness",
	# From Quaternius' Universal Animation Library, merged in via
	# body_animation_libraries. Listed by their own names rather than renamed to
	# match the six above: a clip called Slide is not this project's `slide`,
	# it is one particular pack's idea of one, and flattening that distinction
	# is how a body ends up silently playing the wrong author's intent.
	#
	# The pack's FREE tier is a fantasy/combat set -- swords, farming, zombies --
	# so these five are the whole of what a parkour game can use from it. There
	# is no run and no plain idle in it at all.
	&"Slide", &"Slide_Start", &"Slide_Exit", &"ClimbUp_1m", &"Walk_Carry",
	&"NinjaJump_Start", &"NinjaJump_Idle", &"NinjaJump_Land",
	# The pack has eight Idle_* clips and not one plain idle: they are a
	# lantern, a phone call, a shield, a head-shake. FoldArms is the least
	# costumed of them and is here purely so a standing body is not looping a
	# WALK, which is what it did with no idle available at all.
	&"Idle_FoldArms",
	# From the FIRST Universal Animation Library, which is where the locomotion
	# lives -- the two packs are near-disjoint and this project needs both.
	&"Idle", &"Walk", &"Sprint", &"Roll",
	&"Jump", &"Jump_Start", &"Jump_Land", &"Crouch_Idle", &"Crouch_Fwd",
	# From the PAID tiers of both packs, and every one of them replaces a
	# placeholder that had stood since before there was anything to put there.
	# A body without them keeps the placeholder: these names simply never
	# resolve, and _first_available() walks past them. See
	# assets/animations/FULL-LIBRARY.md.
	#
	# A CLIP MISSING FROM THIS LIST gets no node in the graph at all, which
	# makes travel() to it an engine error rather than a miss. Routing a new
	# name means adding it here in the same breath.
	&"SafetyVault",
	# The two vaults with no hand in them -- see CharacterAnimator's
	# Move.SPEED_VAULT case, and SpeedVaultMove.is_scramble().
	&"StepUp",
	&"WallRun_L", &"WallRun_R", &"WallRun_Jump_L", &"WallRun_Jump_R",
	&"ClimbUp_2m", &"ClimbLedge", &"Climb_Idle", &"Climb_Enter", &"Climb_Exit",
	# The ladder's climb cycles (full tier only; free-tier bodies fall back
	# to Climb_Idle). Absent from this list they had library clips but no
	# DO NOT DROP THESE FROM THE LIST: without an entry here a clip gets no
	# state-machine node, even when the body's AnimationPlayer carries it, and
	# the climb plays nothing at all.
	&"Climb_Up", &"Climb_Down",
	# WITHOUT THESE TWO LINES THE ROUTING FOR THEM IS DEAD CODE. Only clips
	# named here become nodes in the state machine, and CharacterAnimator asks
	# _has_clip() -- which asks the GRAPH, not the body -- so a clip the body
	# ships and this list omits reads exactly like a clip the body does not
	# have: the fallback chain silently takes the next candidate. Drop these
	# two and the shimmy plays Climb_Idle throughout with no left/right climb
	# animation ever visible, even though the body has the clips.
	&"Climb_Left", &"Climb_Right",
	# Turn180_L is wired and never asked for: the move only ever turns right.
	# Here anyway, so that the day the turn stops being one-sided the clip is
	# already in the graph rather than a silent miss.
	&"Turn180_L", &"Turn180_R",
	# The level's death sequence, not a Move -- see CharacterAnimator.
	&"Death01", &"Death02",
	# The uncontrolled fall and its arrival.
	&"LiftAir_Fall", &"LiftAir_Fall_Air", &"LiftAir_Fall_Impact",
	# The coil's tuck. ⚠️ THE NAME IS NOT THE POSE: GroundSit_Idle is the
	# knees-hugged sit, and that is what a mid-air coil looks like -- ✅ the
	# owner found it, "虽然听上去很怪但动作好像是抱膝". Caught by the owner
	# before it shipped, too: "席地坐动作可能不在白名单，你得加一下". Free-tier
	# bodies never resolve it and keep Crouch_Idle, exactly as the paragraph
	# at the top of this block describes.
	&"GroundSit_Idle",
	# THE EIGHT-WAY SETS, and the whole reason the reversed-twin hack below can
	# stop being the answer for a body that has them. Listed out rather than
	# generated from CharacterAnimator.DIRECTION_SETS because this list is also
	# what the all-pairs transition wiring walks, and a name appearing here that
	# the body lacks is skipped rather than costing anything.
	#
	# The two packs disagree on the side names -- UAL1 says Left/Right, UAL2
	# says L/R -- so these are transcribed from the library, not patterned.
	&"Jog_Fwd", &"Jog_Fwd_L", &"Jog_Fwd_R", &"Jog_Left", &"Jog_Right",
	&"Jog_Bwd", &"Jog_Bwd_L", &"Jog_Bwd_R",
	&"Walk_Fwd", &"Walk_Fwd_L", &"Walk_Fwd_R", &"Walk_L", &"Walk_R",
	&"Walk_Bwd", &"Walk_Bwd_L", &"Walk_Bwd_R",
	&"Crouch_Fwd_L", &"Crouch_Fwd_R", &"Crouch_Left", &"Crouch_Right",
	&"Crouch_Bwd", &"Crouch_Bwd_L", &"Crouch_Bwd_R",
]

## Runtime twin of the AnimationTree/CharacterAnimator block that used to be
## baked directly into player.tscn by tools/build_player_scene.gd (see JOB 1
## report for why that had to move here): the graph itself is completely
## generic, but root_node/anim_player can only be resolved once a real body
## -- with a real AnimationPlayer -- exists to point them at, which is
## exactly the thing the committed scene must never assume it has.
## A body with no child literally named "AnimationPlayer" is a supported,
## silently animation-less body, not an error: CharacterAnimator already
## no-ops cleanly with anim_tree left null (see its own _ready()/
## _physics_process()), so simply never creating one here is enough.
##
## The graph gets a node ONLY for a clip _body_has_clip() confirms the body
## actually carries -- never one for every name in _KNOWN_ANIMATION_CLIPS
## unconditionally. This is what lets a committed AnimationTree serve a body
## from a completely different asset pipeline (or no body at all, or a body
## whose AnimationPlayer carries none of these names): CharacterAnimator's
## own fallback logic (see its _has_clip()) can only ever travel() to a name
## that is a real node in this graph, so a name simply never getting added
## here is what keeps that safe rather than an engine error waiting to
## happen the moment some state asks for a clip that does not exist.
## Copies every clip from body_animation_libraries into the attached body's own
## AnimationPlayer, so _wire_body_animation() below sees them as clips the body
## has. Called BEFORE it, for exactly that reason.
##
## Silent no-op at every step where the answer is "there is nothing to merge":
## no library configured, a library that fails to instance, a library with no
## AnimationPlayer, or a body without one. Same stance as _attach_body() takes
## for a malformed body -- this whole subsystem is presentational, and a missing
## animation is a body that stands still, not a crash.
##
## Existing clips WIN. A body that ships its own `run` keeps it: the library is
## there to fill gaps, and silently replacing an author's own animation with a
## generic one would be the opposite of helpful.
func _merge_animation_library(body_node: Node3D) -> void:
	if body_animation_libraries.is_empty():
		return
	var target := body_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if target == null:
		return
	# has_ probed first: get_animation_library() on a missing name logs an
	# engine error, and a fresh AnimationPlayer (an FBX body's wrapper scene,
	# unlike a VRM's) starts with no "" library at all.
	var library: AnimationLibrary
	if target.has_animation_library(""):
		library = target.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		target.add_animation_library("", library)
	for packed in body_animation_libraries:
		if packed == null:
			continue
		var source_scene := packed.instantiate()
		if source_scene == null:
			continue
		var source := _find_animation_player(source_scene)
		if source == null:
			source_scene.free()
			continue
		for clip_name in source.get_animation_list():
			if library.has_animation(clip_name):
				continue
			# Duplicated, not referenced: the source scene is freed below, and
			# an Animation still owned by it would go with it.
			library.add_animation(clip_name, source.get_animation(clip_name).duplicate())
		source_scene.free()

## Builds the arm IK on the body's skeleton, if it has one this can drive.
##
## Silently does nothing otherwise, which covers every non-humanoid body --
## including this project's own Blockbench one, whose bones are named after
## cubes rather than limbs. That body keeps animating exactly as it did.
func _attach_hand_ik(body_node: Node3D) -> void:
	hand_ik = null
	var skeleton := _find_skeleton(body_node)
	if skeleton == null:
		return
	var ik := HandIK.new()
	ik.name = "HandIK"
	add_child(ik)
	if ik.attach(skeleton):
		hand_ik = ik
	else:
		ik.queue_free()

## Eases the visible body toward the offset its CURRENT CLIP asks for.
##
## The mount places the body for a standing pose, which is the only pose it can
## be right for; a pack's clips are authored around their own idea of where the
## ground or the ledge is. See BodyProfile.clip_offsets for what this is for and
## what it cannot do.
##
## Eased on body_animation_blend_time rather than a knob of its own, and that is
## deliberate: it is the window the clips themselves are cross-fading over, so
## the body slides into place across exactly the same frames the pose does.
func _drive_clip_offset(delta: float) -> void:
	if body == null:
		return
	# How much of the offset the EYE follows right now. Eased on its own
	# camera-side time constant rather than flipping with scripted_progress():
	# the clip starts the tick its move's clip is chosen (CharacterAnimator._route()
	# hands it straight to the gate, which does not wait) and outlives it, so a
	# binary hand-over snaps the view by whatever the offset has reached -- DO
	# NOT SNAP: StepUp's 0.2 m offset flashed visibly on both entry and exit
	# before this was eased.
	var follow_target: float = 1.0 if scripted_progress() >= 0.0 else 0.0
	var follow_t: float = 1.0 - exp(-delta / maxf(config.camera.scripted_eye_offset_blend_time, 0.001))
	_scripted_eye_follow = lerpf(_scripted_eye_follow, follow_target, follow_t)
	# The wall run follows the head at half strength -- the authored lean is
	# ~0.7 m and the full ride reads as flying off the wall.
	if camera_rig != null:
		camera_rig.set_head_follow_scale(
			config.wall_run.head_follow_scale
			if move_manager.current_name == Move.WALL_RUN else 1.0)
	var wanted_position := Vector3.ZERO
	var wanted_rotation := Vector3.ZERO
	var offset: Array = clip_offset_for(_current_clip())
	if not offset.is_empty():
		wanted_position = offset[0]
		wanted_rotation = offset[1]
	# Exponential, so the rate does not depend on the tick length.
	var t: float = 1.0 - exp(-delta / maxf(body_animation_blend_time, 0.001))
	_clip_offset_position = _clip_offset_position.lerp(wanted_position, t)
	_clip_offset_rotation = _clip_offset_rotation.lerp(wanted_rotation, t)
	# EASED, not snapped. Dropping the eye 0.9 m in one frame is a jump cut, and
	# it rides the same blend the clips do so the body and the pose arrive
	# together.
	var wanted_drop: float = 0.0
	if _body_folded:
		wanted_drop = maxf(standing_height() - current_capsule_height(), 0.0)
	# NOT WHILE A SCRIPTED MOVE OWNS THE BODY: the pelvis must stay pinned to
	# the capsule's centre for the whole arc.
	#
	# THE FOLD IS WHAT WAS BREAKING THAT PIN, and it took decomposing the
	# model's Y to see it -- the lift cancellation was doing its job. Over one
	# 1.5 m vault: mount held at -0.942, lift rose to 0.682 and came back, and
	# the DROP climbed from 0.179 to 0.850 and stayed. The pelvis came off the
	# arc by most of a metre and none of it was the arc's fault.
	#
	# The fold exists so the eye rides a shortened capsule down. During a
	# scripted move the path already says where the body is, absolutely and every
	# tick, so there is nothing left for the fold to correct -- applying it here
	# would double-count the same correction this file guards against elsewhere.
	if scripted_progress() >= 0.0:
		wanted_drop = 0.0
	_fold_drop = lerpf(_fold_drop, wanted_drop, t)
	# SNAPPED, NOT EASED, WHEN NOTHING IS KEPT: cancelling the hip lift at the
	# root through an easing ramp is only APPROXIMATELY equal to removing the
	# motion at its source, and the approximation is visible -- the pelvis
	# drifts off the path for as long as the ramp lasts.
	#
	# The ramp was protecting against nothing here. These clips start and end
	# at rest -- measured first key to last, ClimbUp_2m moves (-0.00, +0.09,
	# +0.00) and StepUp, SafetyVault and ClimbUp_1m move nothing -- so there is no
	# step to ease over at either boundary.
	#
	# THAT PREMISE IS ABOUT FRAME 0, AND A TRIM CAN QUIETLY BREAK IT. StepUp's
	# 0.1667 s trim starts exactly in the pre-push crouch, hips 0.158 m BELOW
	# rest (measured from ual2_full's own keys) -- and with the dip cancelled
	# too, the root snapped 0.19 m up on the switch tick. DO NOT TRIM STEPUP'S
	# CLIP FURTHER BACK to fix that snap -- the trimmed action IS the foot-lift.
	# What changed instead is that _cancelled_lift() no longer cancels the dip.
	# See its own note.
	var wanted_cancel: float = 1.0 - _kept_clip_lift
	if is_zero_approx(_kept_clip_lift):
		_lift_cancel_amount = wanted_cancel
	else:
		_lift_cancel_amount = lerpf(_lift_cancel_amount, wanted_cancel, t)
	_apply_clip_offset()

## The [position, rotation_degrees] pair for `clip`, or an empty array.
## Tolerant of a malformed table on purpose: this is hand-pasted from a debug
## tool, and a body standing in the wrong place is a better failure than a crash.
func clip_offset_for(clip: StringName) -> Array:
	if clip == Move.KEEP or not body_clip_offsets.has(clip):
		return []
	var entry = body_clip_offsets[clip]
	if entry is Array and entry.size() >= 2 and entry[0] is Vector3 and entry[1] is Vector3:
		return entry
	push_warning("clip_offsets['%s'] is not [Vector3, Vector3]" % clip)
	return []

## The hand-keyed offset for `clip` at normalised time `at`, as [pos, rot].
##
## Linear between keys and flat outside them, which is what a hand-keyed curve
## wants: the author sees exactly the shape they typed, with no interpolator
## inventing overshoot between their keys.
## How close to either end of a scripted move counts as being AT that end.
##
## 2% of a 1.3 s pull-up is 26 ms -- under two physics ticks, which is a snap and
## not a movement.
const CURVE_EDGE := 0.02

## The hand-keyed offset for `clip` at `at`, ALWAYS zero at t = 0 and t = 1.
##
## THE OWNER, making it a rule: "所有脚本驱动的动画首位帧默认都应该是0偏移，否则前后
## 衔接上肯定会出现闪现，这个得强制性."
##
## WHY IT HAS TO BE FORCED rather than left to whoever is keying. Outside a
## scripted move the offset is zero, because there is no curve to read. So a
## first key of, say, +12 cm does not START the move 12 cm off -- it TELEPORTS
## the body 12 cm on the tick the move begins, and back again on the tick it
## ends. The old code made this the DEFAULT failure: with no key at t = 0 it held
## the first key's value all the way back to zero, so any curve that did not
## happen to begin at zero popped at both joins. The ends are bookends this
## function supplies itself now.
##
## KEYS INSIDE THE EDGE BAND ARE IGNORED, not honoured-then-overridden. Left in,
## a stored key at t = 0.005 would sit half a millisecond from the zero bookend
## and the lerp between them would be the same instant jump under another name.
func clip_curve_at(clip: StringName, at: float) -> Array:
	var stored: Array = clip_keys_for(clip, active_obstacle, active_entry)
	if stored.is_empty():
		return []
	var keys: Array = [{"t": 0.0, "pos": Vector3.ZERO, "rot": Vector3.ZERO}]
	for key in stored:
		var edge: float = float(key.get("t", 0.0))
		if edge > CURVE_EDGE and edge < 1.0 - CURVE_EDGE:
			keys.append(key)
	keys.append({"t": 1.0, "pos": Vector3.ZERO, "rot": Vector3.ZERO})
	var previous: Dictionary = keys[0]
	if at <= float(previous.get("t", 0.0)):
		return [previous.get("pos", Vector3.ZERO), previous.get("rot", Vector3.ZERO)]
	for i in range(1, keys.size()):
		var key: Dictionary = keys[i]
		var t1: float = float(key.get("t", 0.0))
		if at > t1:
			previous = key
			continue
		var t0: float = float(previous.get("t", 0.0))
		var span: float = maxf(t1 - t0, 0.0001)
		var f: float = clampf((at - t0) / span, 0.0, 1.0)
		return [
			(previous.get("pos", Vector3.ZERO) as Vector3).lerp(key.get("pos", Vector3.ZERO), f),
			(previous.get("rot", Vector3.ZERO) as Vector3).lerp(key.get("rot", Vector3.ZERO), f),
		]
	var last: Dictionary = keys[keys.size() - 1]
	return [last.get("pos", Vector3.ZERO), last.get("rot", Vector3.ZERO)]

## The hand-keyed rows for `clip` whose obstacle is nearest `obstacle`, or an
## empty array when the clip has none.
##
## HEIGHT DOMINATES, and it has to. A metre of height is a different move --
## a step-up against a vault against a pull-up -- while a metre of width is the
## same move with the body a little further from the far edge. Weighting them
## equally would let a wide low sill borrow a tall thin one's curve, which is a
## different animation entirely.
const OBSTACLE_WIDTH_WEIGHT := 0.35

## How much the ENTRY counts, between the two.
##
## ABOVE WIDTH, BELOW HEIGHT, and the measurement is why. Width moves the far
## edge; the entry tilts the whole line the body travels along, which is the
## thing a hand-keyed offset is describing a position on. See
## ScriptedMove.entry_rise() for the numbers -- 0.69 m of spread on one obstacle,
## from nothing but when the jump was pressed.
const ENTRY_WEIGHT := 0.7

## How high the running scripted move started above where it will end. Written
## each tick a scripted move owns the body; the third axis of clip_keys_for().
var active_entry: float = 0.0

func clip_keys_for(clip: StringName, obstacle: Vector2, entry: float = 0.0) -> Array:
	if clip == Move.KEEP or not body_clip_curves.has(clip):
		return []
	var rows = body_clip_curves[clip]
	if not (rows is Array) or rows.is_empty():
		return []
	# THE OBSTACLE IS DECIDED FIRST, ON ITS OWN, and the entry only breaks ties
	# within what it picks. DO NOT fold the entry into the same sum: once a
	# hand-tuned frame exists for one height and width, a neighbouring row must
	# not be able to influence it, or keying one height makes another shake.
	#
	# One sum let a row for a DIFFERENT obstacle outrank an exact match: at
	# dh 0, dw 0 and an entry 0.68 out, the exact row scores 0.227, while a row
	# a quarter-metre taller with the entry spot on scores 0.063. The neighbour
	# won, so keying one height changed another. Two stages cannot do that -- no
	# entry, however good, can move the obstacle decision.
	var obstacle_best := INF
	for row in rows:
		if not _row_is_usable(row):
			continue
		var dh: float = float(row.get("h", 0.0)) - obstacle.x
		var dw: float = (float(row.get("w", 0.0)) - obstacle.y) * OBSTACLE_WIDTH_WEIGHT
		obstacle_best = minf(obstacle_best, dh * dh + dw * dw)
	if obstacle_best == INF:
		return []
	# SPECIFIC BEATS GENERIC. Among the rows that tie on the obstacle, one
	# carrying an entry is a refinement of one that does not, so the generic row
	# is the fallback rather than the default -- otherwise it would win every
	# time, being at distance zero from everything.
	var best: Array = []
	var best_distance := INF
	var generic: Array = []
	for row in rows:
		if not _row_is_usable(row):
			continue
		var dh: float = float(row.get("h", 0.0)) - obstacle.x
		var dw: float = (float(row.get("w", 0.0)) - obstacle.y) * OBSTACLE_WIDTH_WEIGHT
		if not is_equal_approx(dh * dh + dw * dw, obstacle_best):
			continue
		if not row.has("e"):
			if generic.is_empty():
				generic = row["keys"]
			continue
		var de: float = absf(float(row["e"]) - entry)
		if de < best_distance:
			best_distance = de
			best = row["keys"]
	return best if not best.is_empty() else generic

## Whether a row can be chosen at all.
##
## AN EMPTY ROW IS NOT A MATCH. One gets written the moment a combination is
## visited and then emptied again by dropping its last key, and left eligible it
## would win its own obstacle outright and shadow every neighbour with nothing
## at all -- which reads as the curve having been deleted everywhere.
func _row_is_usable(row) -> bool:
	return row is Dictionary and row.has("keys") \
		and (row["keys"] is Array) and not (row["keys"] as Array).is_empty()

## How far through its path the running scripted move is, or -1 when none is.
##
## The keyed curves are authored against the MOVE's clock rather than the
## AnimationPlayer's, because that is the clock the body's own path runs on --
## and matching the body is the entire job.
func scripted_progress() -> float:
	if move_manager == null:
		return -1.0
	var move = move_manager.move_for(move_manager.current_name)
	if move == null or not move.has_method("path_debug"):
		return -1.0
	var path: Dictionary = move.path_debug()
	return float(path.get("progress", -1.0)) if not path.is_empty() else -1.0

## The clip the animator last asked for, or KEEP if there is no body animating.
func _current_clip() -> StringName:
	var animator := get_node_or_null("BodyRoot/CharacterAnimator") as CharacterAnimator
	return animator.current_clip if animator != null else Move.KEEP

## Places the body at the cached mount plus wherever the offset has eased to.
##
## The rotation goes OUTSIDE the mount basis and the position is added in
## BodyRoot's space, so neither is scaled by mount_scale -- an offset of 0.1
## moves the body 0.1 m whatever size the model is, which is the only way the
## numbers mean anything while being tuned by hand.
func _apply_clip_offset() -> void:
	if body == null:
		return
	# THE HAND-KEYED CURVE RIDES ON TOP, unsmoothed -- see body_clip_curves.
	var curve_position := Vector3.ZERO
	var curve_rotation := Vector3.ZERO
	var at: float = scripted_progress()
	if at >= 0.0:
		var keyed: Array = clip_curve_at(_current_clip(), at)
		if not keyed.is_empty():
			curve_position = keyed[0]
			curve_rotation = keyed[1]
	var extra := Basis.from_euler((_clip_offset_rotation + curve_rotation) * (PI / 180.0))
	# The fold drop goes in HERE rather than through the clip offset, because
	# the two want opposite things from the camera: a clip offset is a
	# correction to the model alone and _camera_head_offset() subtracts it back
	# out, while a fold genuinely lowers the head and the eye must follow. It
	# does so for free -- the head bone moves with the model, and the head-follow
	# reads the bone.
	var lift: float = _cancelled_lift()
	body.transform = Transform3D(extra * _body_mount.basis,
			_body_mount.origin + _clip_offset_position + curve_position
			- Vector3(0.0, _fold_drop + lift, 0.0))

## Declares that a SCRIPTED move owns the body's height, so the clip's own
## vertical hip motion is cancelled rather than added to it.
##
## THE ACTUAL CAUSE of a model that sits above the capsule barely overlapping
## it, and it took measuring the clips to find. Non-root-motion
## guarantees the ROOT NODE does not translate. It says nothing about the HIPS,
## which are a bone like any other -- and an in-place vault clip lifts them
## exactly as much as the real one moved. Measured across the library:
##
##     Idle          0.009 m     flat, as expected
##     Sprint        0.151 m     an ordinary run's bob
##     StepUp        0.477 m
##     SafetyVault   0.825 m     hips from 0.904 up to 1.729
##     ClimbUp_2m    1.201 m
##
## During a scripted move the code already carries the body over the obstacle,
## so the clip's lift is the SAME METRE counted twice, and no amount of moving
## the root fixes it -- the root was never where the body was.
##
## NOT ALWAYS ON. A run's 0.151 m IS the bob and cancelling it would flatten
## the walk into a glide. This is only for the moves whose height is scripted.
func set_clip_lift_cancelled(cancelled: bool) -> void:
	set_clip_lift_kept(0.0 if cancelled else 1.0)

## How much of the running clip's OWN hip lift to keep, as a fraction.
##
## 1 is the clip untouched; 0 is the flat pin that was here before; anything
## between scales the animator's curve to the clearance this obstacle actually
## needs, which is the whole point -- see body_clip_hip_peaks.
##
## A FRACTION, NOT A HEIGHT, because the clip's own peak is the unit. Asking
## for "0.4 m of rise" would mean something different in every clip; asking for
## "a third of what this clip does" scales the shape it already has.
func set_clip_lift_kept(kept: float) -> void:
	_kept_clip_lift = clampf(kept, 0.0, 1.0)

## What set_clip_lift_kept() last stored, for tests and the debug HUD.
func debug_clip_lift_kept() -> float:
	return _kept_clip_lift

## The fraction of the running clip's hip lift that this obstacle wants to keep.
func clip_lift_kept_for(clip: StringName, wanted_rise: float) -> float:
	var peak: float = float(body_clip_hip_peaks.get(clip, 0.0))
	if peak <= 0.001:
		return 0.0
	return clampf(wanted_rise / peak, 0.0, 1.0)

## The lift the body placement actually subtracts: only the RISE, times the
## cancel amount.
##
## THE DIP IS DELIBERATELY KEPT. A hip position BELOW rest is the clip's own
## anticipation -- StepUp crouches 0.158 m before the push -- and the scripted
## path carries no downward leg for it to double-count against, so cancelling
## it does not pin anything: it LIFTS the whole root by the dip's depth the
## instant a trimmed clip cuts in, and the model visibly teleports. Clamped here,
## the switch tick is continuous and the crouch reads as a body gathering
## itself -- feet planted, hips sinking -- which is what the frames are.
func _cancelled_lift() -> float:
	return maxf(clip_lift(), 0.0) * _lift_cancel_amount

## How far the clip has lifted the hips above their rest height, in metres of
## world space -- scaled, because bone space is model space.
func clip_lift() -> float:
	if _skeleton == null or _hips_bone < 0:
		return 0.0
	var posed: float = _skeleton.get_bone_pose_position(_hips_bone).y
	var rest: float = _skeleton.get_bone_rest(_hips_bone).origin.y
	return (posed - rest) * body_mount_scale

## Declares that the body is FOLDED: the legs are tucked and the model should
## ride at the shortened capsule's top rather than standing at its bottom.
##
## The capsule shrinks hugging the FEET, and the model and the eye must come
## down with it. DO NOT shorten the capsule while leaving the model playing
## anchored at the soles -- the model's head is what rides the capsule's top.
##
## The COLLISION is not this function's business and never moves: shortening it
## from the head with the feet on the floor is what set_capsule_height() has
## always done, and is what keeps a landing body resting on its soles. This is
## the presentation half -- the model and, through it, the eye.
func set_body_folded(folded: bool) -> void:
	_body_folded = folded

## How far the model is riding below its standing placement, in metres, for the
## fold above. Exactly what the capsule lost, so the model's crown sits on the
## capsule's crown.
func body_fold_drop() -> float:
	return _fold_drop

## Whether a move has DECLARED the fold, as against how far the model has
## actually moved for it. The two can disagree -- the drop is derived from the
## capsule, so anything that restores the capsule while the fold is still
## declared silently takes the drop to zero -- and telling them apart is the
## whole reason both are on the debug readout.
func body_folded() -> bool:
	return _body_folded

## True while the level's death sequence is running. Read by CharacterAnimator,
## which routes the body to a death clip -- a fact about the LEVEL rather than
## about any Move, which is why it is a flag here and not a state.
var _dying: bool = false

## [ME:CONFIRMED] The original has exactly ONE death animation, and it is the
## non-fall one -- cut up, or shot. A fatal fall there is a bone-crack and an
## immediate cut to black, no performance at all. The topple sequence in this
## project is ours, added on top, which is why FALL is the exception below and
## everything else shares a clip.
enum DeathCause { FALL, VOLUME }

## Which death is being performed. Set where the death is DECLARED, and every
## declaring site must set it.
##
## DO NOT try to infer this from the move name instead. A fatal landing
## declares its death in FallUncontrolledMove.landing_destination(), which
## then returns WALKING -- so by the time DeathSequence runs, the state
## machine is in an ordinary walk and has nothing left to tell apart. Only the
## ragdoll branch stays put, so the move name answers correctly for one of the
## two fall deaths and wrongly for the other.
var death_cause: int = DeathCause.FALL

func set_dying(dying: bool) -> void:
	_dying = dying
	# WHICH VIEW changes here, and DeathSequence.play() reads it back inside
	# the same call -- to pick between the two death pitches -- so it cannot
	# wait for the next tick's push. death_cause is set before this at every
	# declaring site, which is what makes the answer available already.
	_push_forced_view()

## THE BODY IS WATCHED FROM OUTSIDE WHILE IT DIES, unless the death is a fall.
##
## Death02 collapses FACE DOWN. In first person that ends with the eye below
## the floor looking up through the model -- not a framing that can be tuned
## out, the head simply arrives where the camera is. The falling performance
## has its own camera and wants none of this.
##
## ONLY WITH A BODY. With nothing mounted there is no head to clip through,
## which is the entire reason this exists, and a forced third person would
## just pull the eye back off an invisible player.
##
## OUTRANKS A LEVEL'S FORCE_VIEW rather than yielding to it: a level that
## pinned the view is in no position to keep a death legible. The pin comes
## back the moment the body is released, because this is the only writer of
## the field and it re-derives the answer from scratch every tick.
func _push_forced_view() -> void:
	# statuses is built in setup(), and set_dying() below is reachable from a
	# bare Player.new() that skipped it -- the same case DeathSequence guards.
	if camera_rig == null or statuses == null:
		return
	if _dying and death_cause != DeathCause.FALL and body != null:
		camera_rig.forced_view = Status.View.THIRD
		return
	camera_rig.forced_view = statuses.forced_view()

func is_dying() -> bool:
	return _dying

## Where the model's ROOT actually sits under BodyRoot, and where the mount
## alone would have put it. The gap between them is every correction this
## project applies to the body: the fold drop and the per-clip offset.
##
## The number nobody could see without this, and the reason arguing from
## screenshots does not converge. The eye readout shows where the HEAD BONE
## ended up, which is the mount plus the corrections plus THE POSE -- and the
## pose can move the head half a metre on its own. Only this says which of the
## three moved.
func body_root_debug() -> Dictionary:
	return {
		"y": body.position.y if body != null else 0.0,
		"mount_y": _body_mount.origin.y,
		"drop": _fold_drop,
		"clip_y": _clip_offset_position.y,
		"lift": _cancelled_lift(),
		"fold_drop": _fold_drop,
		"lift_cancel": _lift_cancel_amount,
		"lift_kept": _kept_clip_lift,
	}

## Puts back the two eased terms that place the model, for a recording being
## scrubbed.
##
## THESE ARE STATE, NOT DERIVATIONS, and that is the whole reason this exists.
## _drive_clip_offset() eases both of them every tick, and a scrub has that tick
## switched off -- so they sit frozen at whatever the take ENDED on, which is a
## body standing still with nothing to cancel. The recorded pose meanwhile has
## the hips high in their own space, the pelvis leaves the reference line, and
## the model flies.
##
## The third instance of the same class in this scene -- the position, the
## capsule height, and now these. A scrub owns the body OUTRIGHT; anything the
## simulation would have been maintaining has to come out of the recording.
func set_body_shape_state(fold_drop: float, lift_cancel: float) -> void:
	_fold_drop = fold_drop
	_lift_cancel_amount = lift_cancel

## Sets the offset with no easing at all, for the debug tuner: while the tree is
## paused nothing calls _drive_clip_offset(), and a tuner you cannot see the
## result of is not a tuner.
##
## THE EYE MOVES WITH THE BODY, and DO NOT leave it out: the camera must follow
## the model's offset here. It does during play -- the head-follow
## reads the head bone's displacement every tick -- but that tick is paused too,
## so nudging the body left the view exactly where it was and the whole point of
## tuning in first person went with it. The rig is stepped by hand here for the
## same reason the transform is.
func set_clip_offset_immediately(position_offset: Vector3, rotation_offset: Vector3) -> void:
	_clip_offset_position = position_offset
	_clip_offset_rotation = rotation_offset
	_apply_clip_offset()
	refresh_head_follow()

## The head's displacement from rest, MINUS whatever the per-clip offset moved
## the whole body by.
##
## DO NOT let a clip offset move the eye: lowering one to fix third-person
## framing puts the first-person camera underground. In first person the eye is
## dragged along by the head bone, so a correction meant to plant the MODEL's
## hands on a ledge moves the VIEW by the same amount, and a few centimetres of
## down is the floor.
##
## So the eye follows the ANIMATION and ignores the correction. A clip offset is
## a statement about where the model should sit relative to the world; it is not
## a statement about where the player is looking from. Moving the eye
## deliberately already has its own knobs -- body_slide_eye_lift is one -- and
## they are per-model rather than per-clip for the same reason.
##
## The POSITION part only. A clip offset's rotation also moves the head a
## little, and that is left in: the head sits near the axis a yaw turns about,
## so the amount is small, and unpicking it would mean re-deriving the bone's
## position from a pose it is not in.
func _camera_head_offset() -> Vector3:
	var raw: Vector3 = to_local(head_node.global_position) - head_rest_local
	# EXCEPT DURING A SCRIPTED MOVE, where the first-person camera must take the
	# clip's own offset -- StepUp's -0.20 z otherwise leaves the camera inside
	# the neck. A scripted move's path owns the eye's whole journey and its clip
	# offset is part of the presentation, so the eye follows the model. Outside
	# one the subtraction below stands: WallRun's +-0.7 lateral corrections must
	# never swing the view, and an offset lowered for third-person framing must
	# never put the first-person camera underground.
	#
	# BLENDED, not switched: _scripted_eye_follow eases between the two
	# regimes (see _drive_clip_offset()), because the clip and its offset do
	# not start and end on the move's own boundaries.
	var body_root := get_node_or_null("BodyRoot") as Node3D
	var applied: Vector3 = _clip_offset_position
	if body_root != null:
		applied = body_root.transform.basis * _clip_offset_position
	return raw - applied * (1.0 - _scripted_eye_follow)

## What the camera does for a scripted move when there is no head to follow.
##
## In every scripted move the capsule travels a straight line, so a camera that
## simulates the arc is only ever needed when no model and skeleton are bound.
## That trajectory is reserved for this fallback offset and nothing else.
##
## ONLY WITHOUT A MODEL. With one, the eye follows the head bone and the head
## bone is wherever the animation puts it -- adding this on top would move the
## eye twice for the same journey.
##
## It goes through set_head_offset() because the effect wanted is exactly what
## that does: raise the eye by a displacement Player refreshes every tick. There
## is no head here, so nothing is stale.
func _head_follow_fallback() -> void:
	var lift: float = _scripted_camera_lift()
	if is_zero_approx(lift):
		camera_rig.clear_head_position()
		return
	camera_rig.set_head_offset(Vector3(0.0, lift, 0.0))

## The active scripted move's fallback camera rise, or 0 when none is running.
func _scripted_camera_lift() -> float:
	if move_manager == null:
		return 0.0
	var move = move_manager.move_for(move_manager.current_name)
	if move == null or not move.has_method("camera_lift"):
		return 0.0
	return float(move.camera_lift())

## Re-feeds the camera the head's current displacement from rest, out of band
## with the physics tick. Exists for the paused case above; during play
## _physics_process() does exactly this line every tick.
func refresh_head_follow() -> void:
	if camera_rig == null:
		return
	if head_node == null:
		_head_follow_fallback()
		return
	# force_update_transform(), because the skeleton's own pose is applied by a
	# deferred modifier pass that a paused tree never runs: without it the bone
	# still reports where it was before the body moved.
	head_node.force_update_transform()
	camera_rig.set_head_offset(_camera_head_offset())
	camera_rig.update_effects(0.0, 0.0, grounded)

## Builds the head look on the body's skeleton, if it has a neck to turn.
func _attach_head_look(body_node: Node3D) -> void:
	head_look = null
	var skeleton := _find_skeleton(body_node)
	if skeleton == null or skeleton.find_bone(&"Head") < 0:
		return
	skeleton.modifier_callback_mode_process = 		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	var look := HeadLook.new()
	look.name = "HeadLook"
	skeleton.add_child(look)
	head_look = look

## Feeds the head look the angle between where the MODEL faces and where the
## CAMERA points.
##
## That divergence already exists: _drive_body_yaw() holds the model's heading
## while there is no movement input, so turning the camera on the spot opens
## exactly this gap. Standing still used to swing the whole character round;
## then it stopped moving at all, which reads as a mannequin. Looking along the
## gap is the half in between.
func _drive_head_look() -> void:
	if head_look == null:
		return
	if camera_rig == null:
		head_look.request(0.0, 0.0, config.camera.pitch_limit_deg)
		return
	# The MODEL's heading, not the body's -- the body is always looking exactly
	# where the camera is, so measuring against it would always be zero.
	var yaw: float = wrapf(rotation.y - _visual_yaw, -PI, PI)
	var pitch: float = float(camera_rig.look_debug()["pitch"])
	# The active move decides whether the chest may join in -- see
	# MoveConfig.allows_spine_twist.
	var active: MoveConfig = move_manager.current_config() if move_manager != null else null
	var spine: float = HeadLook.SPINE_SHARE_DEG
	if active != null and not active.allows_spine_twist:
		spine = 0.0
	head_look.request(yaw, pitch, config.camera.pitch_limit_deg, spine)

## Turns the visible body toward where it is going, instead of welding it to
## the view.
##
## The BODY's real facing is untouched -- it follows the mouse instantly, as it
## always has, and every probe, move and camera clamp still reads that. What
## moves here is only how the attached model is DRAWN, by counter-rotating
## BodyRoot so the model keeps its own heading in world space.
##
## The owner's complaint: standing still and turning the camera swung the whole
## character round, which reads as a model welded to the mouse rather than as a
## person looking about. So the model holds while there is no movement input,
## and catches up once there is.
func set_swing_pitch_target(pitch: float) -> void:
	_swing_pitch_target = pitch

func _drive_body_yaw(delta: float, input: MoveInput) -> void:
	var body_root := get_node_or_null("BodyRoot") as Node3D
	if body_root == null:
		return
	# The swing's lean. HARD-TRACKED while swinging -- the body and the chain
	# are rigid geometry, and any smoothing here reads as the model trailing
	# the swing: a 0.08 s ease here puts the model about 16 degrees behind at
	# the omega cap, and it reads as visible lag. The ease is
	# only for AFTER letting go, standing the body back up over a beat.
	if move_manager != null and move_manager.current_name == Move.SWING:
		body_root.rotation.x = _swing_pitch_target
	else:
		var ease: float = 1.0 - exp(-delta / 0.08)
		body_root.rotation.x = lerpf(body_root.rotation.x, _swing_pitch_target, ease)
		# The swing's eye offsets ride the SAME ease home -- zeroed instantly
		# while the chest was still leaning, the eye clipped through it for a
		# few frames on every exit (the owner saw it).
		if camera_rig != null:
			camera_rig.extra_eye_forward = lerpf(camera_rig.extra_eye_forward, 0.0, ease)
			camera_rig.extra_eye_lift = lerpf(camera_rig.extra_eye_lift, 0.0, ease)
	# A MOVE CAN FREEZE THE MODEL IN EITHER VIEW. Slide and Grab do -- see
	# MoveConfig.freeze_visual_yaw -- and they are not subject to the
	# third-person rule below, because the reason for that rule does not apply:
	# there, holding the body still is a stylistic choice about watching a
	# character, while here it is a body that physically cannot turn. Legs
	# swinging round under a slide look ridiculous from inside the head too.
	var active: MoveConfig = move_manager.current_config() if move_manager != null else null
	var frozen: bool = active != null and active.freeze_visual_yaw
	# THIRD PERSON ONLY OTHERWISE, on the owner's correction: from inside the
	# head a body that does not turn with the view is worse than one that does,
	# because the shoulders swivel under a head that did not move. That effect
	# is about watching a character; there is no character to watch from in
	# here.
	if not frozen and (camera_rig == null or not camera_rig.in_third_person()):
		_visual_yaw = rotation.y
		body_root.rotation.y = 0.0
		return
	if not _visual_yaw_started:
		_visual_yaw = rotation.y
		_visual_yaw_started = true

	# Any deliberate movement is a decision to face that way. Read from the
	# INPUT rather than from velocity: a body still sliding to a halt has not
	# asked to turn, and one just starting to move has.
	# A frozen move holds the model where the move began, whatever the input
	# says: the point is that the body CANNOT turn, so asking it to is not a
	# reason for it to.
	if not frozen and input.move.length() > config.pawn.body_turn_input_threshold:
		var step: float = deg_to_rad(config.pawn.body_turn_speed_deg) * delta
		var remaining: float = wrapf(rotation.y - _visual_yaw, -PI, PI)
		_visual_yaw += clampf(remaining, -step, step)

	# Counter-rotated, so the model's WORLD yaw is _visual_yaw whatever the body
	# is doing. Wrapped, so a player who spins on the spot cannot wind this up.
	body_root.rotation.y = wrapf(_visual_yaw - rotation.y, -PI, PI)

## Where the visible model is facing, in world radians.
func visual_yaw() -> float:
	return _visual_yaw

## Points the visible model at `radians`, in world space.
##
## FOR MOVES THAT freeze_visual_yaw, WHICH IS THE WHOLE PROBLEM. Grab freezes
## it, and rightly: a hanging body cannot swivel its legs to follow the view, so
## _drive_body_yaw() counter-rotates BodyRoot to hold the model's WORLD yaw still
## however far the collision body turns.
##
## A corner is the one time that freeze is wrong: the body genuinely swings
## ninety degrees onto the next face, and an unconditional freeze cancels every
## degree of it, leaving the model facing the old wall.
##
## ABSOLUTE, NOT INCREMENTAL -- DO NOT add each tick's slice to the model. It
## looks equivalent and is not: the collision body's yaw is REBUILT every tick as
## reference-plus-relative, and apply_look eases `relative` whenever the fan
## moves out from under the view -- which is exactly what a corner does to it.
## So the two quantities were being maintained by different arithmetic, and the
## gap between them survives each corner and stacks with the next. A few
## corners of that and the model is facing backwards.
##
## Stating the answer instead of the increment cannot accumulate: the model
## faces the wall the hands are on, and every tick says so afresh.
func pin_visual_yaw(radians: float) -> void:
	_visual_yaw_started = true
	_visual_yaw = wrapf(radians, -PI, PI)

## The attached body's skeleton, or null. Resolved once at attach and handed out
## rather than re-searched: DeathSequence asks for it to build a ragdoll on.
func find_skeleton() -> Skeleton3D:
	return _skeleton

## Both walkers take a null root, because `body` legitimately IS null whenever
## no body_scene was attached -- _attach_body()'s own header promises that case
## "degrades to 'no body' rather than crashing startup". Without this guard the
## first loop pops the null straight into get_children() and takes the whole
## frame with it, which is exactly what every animation test was hitting: the
## null check inside _measure_scripted_hip_peaks() sits AFTER this call and so
## never got the chance to run.
func _find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is Skeleton3D:
			return node as Skeleton3D
		for child in node.get_children():
			queue.append(child)
	return null

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child in node.get_children():
			queue.append(child)
	return null

func _wire_body_animation(body_node: Node3D) -> void:
	var _wt := Time.get_ticks_msec()
	var _wm := func(what: String) -> void:
		print("[load]       _wire_body %-22s %6d ms elapsed" % [what, Time.get_ticks_msec() - _wt])
	var anim_player := body_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		return

	# Loop fix: verified directly against the real asset (not assumed) that
	# every imported clip -- idle, run, jump alike -- comes in with
	# Animation.loop_mode == LOOP_NONE. glTF itself carries no "this clip
	# loops" flag; in Godot 4.7 that is purely an IMPORT-TIME setting
	# (Advanced Import Settings' per-animation loop_mode override, written
	# into the asset's own .import file) with no equivalent on the
	# AnimationNodeStateMachine/AnimationTree side to compensate. That
	# import-time fix is unusable here: the .import file lives inside the
	# untracked, CC BY-NC-SA model's own directory (see JOB 1), so nothing
	# there can be part of a fix required to live in tracked project code
	# and to survive the model being entirely absent. Enforced here instead,
	# on whatever body actually attaches, every time, regardless of how (or
	# whether) it was imported. idle/run/sneak/sneaking/ladder_stillness are
	# all sustained, hold-or-repeat clips that must keep going for as long as
	# the state holds; jump is a discrete one-shot action and is deliberately
	# left alone.
	_ensure_clips_loop(anim_player, [&"idle", &"run", &"sneak", &"sneaking", &"ladder_stillness", 			&"Slide", &"Walk_Carry", &"NinjaJump_Idle", &"Idle_FoldArms", 			&"Idle", &"Walk", &"Sprint", &"Crouch_Idle", &"Crouch_Fwd", &"LiftAir_Fall_Air", &"Jog_Fwd", &"Jog_Fwd_L", &"Jog_Fwd_R", &"Jog_Left", &"Jog_Right", &"Jog_Bwd", &"Jog_Bwd_L", &"Jog_Bwd_R", &"Walk_Fwd", &"Walk_Fwd_L", &"Walk_Fwd_R", &"Walk_L", &"Walk_R", &"Walk_Bwd", &"Walk_Bwd_L", &"Walk_Bwd_R", &"Crouch_Fwd_L", &"Crouch_Fwd_R", &"Crouch_Left", &"Crouch_Right", &"Crouch_Bwd", &"Crouch_Bwd_L", &"Crouch_Bwd_R", &"WallRun_L", &"WallRun_R", &"Climb_Idle", &"Climb_Left", &"Climb_Right", &"Climb_Up", &"Climb_Down", &"GroundSit_Idle"])
	_wm.call("loop-mode fixups")
	_measure_scripted_hip_peaks(anim_player)
	_wm.call("_measure_scripted_hip_peaks")

	var state_machine := AnimationNodeStateMachine.new()
	for clip_name in _KNOWN_ANIMATION_CLIPS:
		if not _body_has_clip(anim_player, clip_name):
			continue
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = clip_name
		apply_clip_timing(clip_node, clip_name, anim_player)
		state_machine.add_node(String(clip_name), clip_node)
		# The reversed twin, for moving backwards. Same clip resource, played
		# the other way -- see _REVERSIBLE_CLIPS.
		if _REVERSIBLE_CLIPS.has(clip_name):
			var backward := AnimationNodeAnimation.new()
			backward.animation = clip_name
			backward.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
			apply_clip_timing(backward, clip_name, anim_player)
			state_machine.add_node(String(clip_name) + BACKWARD_SUFFIX, backward)

	_wm.call("state nodes")
	# EVERY ORDERED PAIR GETS AN EDGE, so travel() always has a path.
	#
	# The graph used to carry three transitions -- Start->idle, idle->run,
	# run->End -- and travel() reached everything else by TELEPORTING, which is
	# Godot's own word for it: "if the path does not connect from the current
	# state, the animation will play after the state teleports", with
	# reset_on_teleport defaulting to true so the incoming clip restarts from
	# frame zero as well. A limb mid-swing simply appears wherever the next
	# clip's first frame puts it. Only idle->run was ever a real transition, and
	# with xfade_time left at its 0.0 default even that was a cut.
	#
	# Generated rather than hand-listed because the node set is decided at
	# runtime from whatever clips the attached body actually has (see above), so
	# there is no fixed list to write down.
	#
	# advance_mode = ENABLED, not AUTO -- the same decision, and for the same
	# reason, that used to be documented on this exact block in
	# tools/build_player_scene.gd before it moved here: an unconditioned AUTO
	# transition fires the instant it is evaluated, not when its animation
	# finishes, racing the whole chain to End within a single physics frame
	# regardless of what CharacterAnimator asks for. ENABLED transitions never
	# fire on their own; travel() calls from CharacterAnimator are the only
	# thing that ever moves this graph.
	#
	# NO SELF-TRANSITIONS. CharacterAnimator re-issues travel() every tick (see
	# its own header for why it must), so an edge from a state to itself is an
	# invitation to restart the current clip sixty times a second.
	var present: Array[StringName] = []
	for clip_name in _KNOWN_ANIMATION_CLIPS:
		if state_machine.has_node(String(clip_name)):
			present.append(clip_name)
		# The reversed twins need edges too, or travel() teleports to them --
		# which for a locomotion clip means a visible snap every time the player
		# changes from forward to backward and back.
		var backward := StringName(String(clip_name) + BACKWARD_SUFFIX)
		if state_machine.has_node(String(backward)):
			present.append(backward)
	for to_name in present:
		# From Start as well, so the first travel() of a body's life is a real
		# transition rather than a teleport out of the entry node.
		state_machine.add_transition("Start", String(to_name),
				_blend_transition(body_animation_blend_time))
		for from_name in present:
			if from_name == to_name:
				continue
			state_machine.add_transition(String(from_name), String(to_name),
					_blend_transition(_exit_blend_time(from_name, to_name)))

	# WRAPPED IN A BLEND TREE, rather than used as the root directly.
	#
	# A bare AnimationNodeStateMachine at the root has nowhere to put an
	# AnimationNodeTimeScale, which leaves every clip pinned to its authored
	# cadence no matter how fast the body is actually travelling -- the thing
	# that reads as the feet sliding across the ground. The state machine keeps
	# doing exactly what it did; it just sits one level down, so travel() now
	# goes through parameters/<GRAPH_STATES>/playback instead of
	# parameters/playback. CharacterAnimator owns both names.
	#
	# AND THE SCRIPTED CLIPS DO NOT GO THROUGH IT AT ALL. They play on two bare
	# slots wired into an AnimationNodeTransition alongside it:
	#
	#     states ------.
	#     scripted_a ---+--> gate --> speed --> output
	#     scripted_b ---'
	#
	# The state machine cannot start a clip mid-transition without either waiting
	# out the fade (travel()) or throwing it away (start()), and both are visible
	# defects -- see CharacterAnimator._route() for the measurement.
	# AnimationNodeTransition has neither problem: it
	# switches inputs the moment it is asked, WITH its own xfade, and interrupts
	# a fade of its own gracefully (verified on a bare tree in 4.7.1 -- a request
	# issued at 0.117 s of a 0.15 s fade started a fresh full fade on the very
	# next tick).
	#
	# TWO slots rather than one, ping-ponged by the animator, so that CONSECUTIVE
	# scripted clips -- a mantle chain -- also cross-fade instead of cutting: an
	# input cannot fade into itself.
	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(CharacterAnimator.GRAPH_STATES, state_machine)
	for slot in CharacterAnimator.GRAPH_SCRIPTED_SLOTS:
		# BARE, with no clip. The animator loads one the moment a scripted move
		# asks for it, and applies the same trim the state machine's own node for
		# that clip carries.
		blend_tree.add_node(slot, AnimationNodeAnimation.new())
	blend_tree.add_node(CharacterAnimator.GRAPH_GATE,
		_scripted_gate(body_animation_blend_time))
	blend_tree.add_node(CharacterAnimator.GRAPH_TIME_SCALE, AnimationNodeTimeScale.new())
	# connect_node(input_node, input_index, output_node) reads backwards: it
	# feeds output_node's OUTPUT into input_node's input port. So these say
	# "{states, scripted_a, scripted_b} -> gate -> speed -> output". An
	# AnimationNodeOutput named `output` exists in every blend tree by default;
	# it is not added here.
	for index in CharacterAnimator.GRAPH_GATE_INPUTS.size():
		blend_tree.connect_node(CharacterAnimator.GRAPH_GATE, index,
			CharacterAnimator.GRAPH_GATE_INPUTS[index])
	blend_tree.connect_node(CharacterAnimator.GRAPH_TIME_SCALE, 0, CharacterAnimator.GRAPH_GATE)
	blend_tree.connect_node(&"output", 0, CharacterAnimator.GRAPH_TIME_SCALE)

	_wm.call("every ordered-pair transition")
	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.tree_root = blend_tree
	# PHYSICS, matching every other system in this project (movement, camera,
	# probes) and the tests/test_case.gd step() loop they run under -- an
	# AnimationTree left on its IDLE-process default never sees a frame in a
	# headless physics-only test loop.
	anim_tree.process_callback = AnimationTree.ANIMATION_PROCESS_PHYSICS
	anim_tree.active = true
	_body_root().add_child(anim_tree)
	# Computed, not hardcoded, so these NodePaths can never drift from the
	# actual hierarchy just built.
	anim_tree.root_node = anim_tree.get_path_to(body_node)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var animator := CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	# anim_tree/player set BEFORE add_child(), not after: unlike
	# tools/build_player_scene.gd's old copy of this block (which built its
	# whole player hierarchy OUT OF TREE and only ever wired properties
	# on nodes that would not fire _ready() until the SAVED scene was later
	# instanced, by which point the scene loader had already set every
	# exported property first), this code runs at real runtime on a Player
	# ALREADY inside the live SceneTree -- add_child() here fires
	# CharacterAnimator._ready() SYNCHRONOUSLY, which reads anim_tree to
	# cache _playback. Setting these after add_child() left anim_tree null
	# at exactly that moment, permanently disabling _playback and silently
	# freezing every attached body's animation at "Start" -- caught by
	# running a live repro (tools/_tmp_debug_stub_anim.gd, not committed),
	# not by inspection; see the JOB 1 report.
	animator.anim_tree = anim_tree
	animator.player = self
	_body_root().add_child(animator)

## Trims a clip to the part of it this project actually uses.
##
## Untrimmed, the vault and grab animations play far too late: the character has
## nearly landed on the other side before the frame where the hand plants. The
## clips are authored as WHOLE ACTIONS, run-up included, and this project starts
## them at the moment of contact, so the approach half plays while the body is
## already going over and the interesting half arrives after the move is done.
##
## DO NOT fix that by starting the animation early and predictively. Skipping the
## run-up does the same job without touching gameplay or guessing when the clip
## should have begun.
##
## Godot's own timeline controls do all of it. `start_offset` says where in the
## clip to begin; `timeline_length` with `stretch_time_scale` says how long the
## kept part should take, which is how a 1.5 s clip fits a 0.65 s move without
## a time scale anyone has to maintain.
##
## Read from BodyProfile.clip_timings as {clip: [start, length]} in SECONDS. A
## length of 0 means "to the end of the clip".
##
## BUILD TIME, not per tick. Changing the table needs the body re-attached,
## which is what the alignment scene is for.
## Pushes the whole of body_clip_timings into the graph that is already running.
##
## Without this, a configured `from` is ignored and the clip plays from its first
## frame. Confirmed by comparing
## the RECORDED POSE against the source clip at two times -- at a frame reporting
## a clip time of 0.1465 s with an offset of 0.2667 s set, the body matched the
## clip at 0.1465 (distance 0.002) and not at 0.4132 (distance 8.66). The trim
## was in the dictionary and nowhere else.
##
## THE GAME IS NOT AFFECTED, only the lab. adopt_body_profile() writes the
## timings and THEN re-attaches the body, so _wire_body_animation() sets them as
## it builds each node. The lab loads its own table from JSON after the body is
## already attached, which is a case the build-time-only path cannot serve.
##
## NO REBUILD NEEDED. Setting the properties on the live AnimationNodeAnimation
## resource is enough -- measured the same way, the pose then matched at 0.4132
## (distance 0.002) instead. DO NOT trust a probe that says otherwise without
## checking it is reading a real body rather than a stub.
func refresh_clip_timings() -> void:
	var root := get_node_or_null("BodyRoot")
	if root == null or body == null:
		return
	var anim_player := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player == null:
		return
	var tree: AnimationTree = null
	for child in root.get_children():
		if child is AnimationTree:
			tree = child
	if tree == null:
		return
	var graph := tree.tree_root as AnimationNodeBlendTree
	if graph == null or not graph.has_node(CharacterAnimator.GRAPH_STATES):
		return
	var states := graph.get_node(CharacterAnimator.GRAPH_STATES) as AnimationNodeStateMachine
	if states == null:
		return
	# EVERY NODE, not only the ones with an entry: a trim that has just been
	# REMOVED has to switch its custom timeline back off, and there is nothing
	# left in the table to drive that from.
	for clip in states.get_node_list():
		var node := states.get_node(clip) as AnimationNodeAnimation
		if node == null:
			continue
		apply_clip_timing(node, clip, anim_player)
	# THE SCRIPTED SLOTS TOO, and they are the ones that matter most: the trim
	# exists for the vault and the mantle, which are exactly the clips that no
	# longer play through the state machine at all. Keyed by whatever clip the
	# slot is currently carrying rather than by its own name.
	for slot in CharacterAnimator.GRAPH_SCRIPTED_SLOTS:
		if not graph.has_node(slot):
			continue
		var slot_node := graph.get_node(slot) as AnimationNodeAnimation
		if slot_node == null or slot_node.animation == &"":
			continue
		apply_clip_timing(slot_node, slot_node.animation, anim_player)

## Applies `clip_name`'s entry in body_clip_timings to `node`, or clears any trim
## already on it when the table has nothing to say.
##
## ONE HELPER, TWO CALLERS. _wire_body_animation() uses it on the state
## machine's per-clip nodes; CharacterAnimator uses it on a scripted slot the
## moment it loads a clip into one. A clip has to trim identically whichever of
## the two is playing it, and two copies of these five lines would not.
func apply_clip_timing(node: AnimationNodeAnimation, clip_name: StringName, 		anim_player: AnimationPlayer) -> void:
	if not body_clip_timings.has(clip_name):
		# CLEARED, not left alone. A slot carries whatever the last scripted move
		# put on it, so an untrimmed clip loaded onto a slot that was trimmed
		# would inherit the previous clip's start_offset.
		node.use_custom_timeline = false
		return
	var entry = body_clip_timings[clip_name]
	if not (entry is Array and entry.size() >= 2):
		push_warning("clip_timings['%s'] is not [start, length]" % clip_name)
		return
	var start: float = float(entry[0])
	var length: float = float(entry[1])
	var whole: float = 0.0
	if anim_player.has_animation(clip_name):
		whole = anim_player.get_animation(clip_name).length
	if length <= 0.0:
		length = maxf(whole - start, 0.0)
	if length <= 0.0:
		return
	node.use_custom_timeline = true
	node.start_offset = start
	node.timeline_length = length
	# STRETCH OFF. DO NOT turn stretch_time_scale on here: with a trim set, the
	# tail of the clip freezes -- a 39-frame animation trimmed to start at frame
	# 11 holds its last 11 frames.
	#
	# stretch_time_scale maps the animation's ORIGINAL length onto
	# timeline_length. With start_offset also set, the offset removes 11 frames
	# of CONTENT while the stretch's rate is still computed from all 39 -- so the
	# 28 kept frames run 39/28 = 1.39x too fast, finish early, and the rest of
	# the timeline is a held pose. Measured on a bare AnimationTree: 0.7 frames
	# per tick instead of 0.5, reaching the end and repeating it. The length of
	# the freeze is exactly start_offset.
	#
	# AND THE JOB IT WAS ADDED FOR IS ALREADY DONE ELSEWHERE.
	# CharacterAnimator._scripted_fit() divides the KEPT length by the move's
	# duration and drives GRAPH_TIME_SCALE with it, which stretches the node's
	# content and its custom timeline together. Two stretches fight, and this is
	# the one that reads the wrong length.
	node.stretch_time_scale = false

## True when `anim_player` actually carries `clip_name`, in the DEFAULT ("")
## library -- same lookup, and the same "only the default library, ever"
## reasoning, as _ensure_clip_loops() below, so a clip that exists but sits
## in some other, named library reads as absent here too, consistently.
## This is the single source of truth _wire_body_animation() uses to decide
## which nodes the AnimationTree's graph gets at all.
## One cross-fading transition, configured the same way every time. A fresh
## resource per edge, never a shared one: AnimationNodeStateMachineTransition is
## a Resource, and handing the same instance to every edge would make them one
## object wearing many hats.
## How long one particular edge should take. Three tiers, and the middle one is
## the owner's: leaving a slide for a crouch is continuous and does not need the
## stand-up's half second, but at the ordinary 0.15 s a change of pose that
## large reads as a cut.
func _exit_blend_time(from_name: StringName, to_name: StringName) -> float:
	if not _SLOW_EXIT_CLIPS.has(from_name):
		return body_animation_blend_time
	if _CROUCHED_CLIPS.has(to_name):
		return body_slide_to_crouch_blend_time
	return body_slide_exit_blend_time

## The three-input switch the scripted clips play behind. See
## _wire_body_animation() for the shape of the graph and why it exists.
##
## THE INPUT PROPERTY NAMES ARE PER-INDEX AND UNDOCUMENTED ON THE CLASS:
## AnimationNodeTransition exposes only `input_count`, `xfade_time`,
## `xfade_curve` and `allow_transition_to_self` to ClassDB, and grows
## `input_<i>/name`, `input_<i>/auto_advance`, `input_<i>/break_loop_at_end` and
## `input_<i>/reset` on the INSTANCE once set_input_count() has run. Verified by
## printing get_property_list() on a live 4.7.1 node rather than assumed.
##
## RESET IS ON FOR THE SLOTS AND OFF FOR THE STATE MACHINE, and it defaults to
## ON for all three. A slot is re-used with a different clip loaded into it, so
## entering it has to rewind, so that the action begins now. The state machine
## is the opposite case: coming
## back to a run that has been playing underneath all along must not restart it.
func _scripted_gate(seconds: float) -> AnimationNodeTransition:
	var gate := AnimationNodeTransition.new()
	gate.set_input_count(CharacterAnimator.GRAPH_GATE_INPUTS.size())
	gate.xfade_time = maxf(seconds, 0.0)
	for index in CharacterAnimator.GRAPH_GATE_INPUTS.size():
		var input: StringName = CharacterAnimator.GRAPH_GATE_INPUTS[index]
		gate.set("input_%d/name" % index, String(input))
		gate.set("input_%d/reset" % index, input != CharacterAnimator.GRAPH_STATES)
	return gate

func _blend_transition(seconds: float) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	transition.xfade_time = maxf(seconds, 0.0)
	return transition

func _body_has_clip(anim_player: AnimationPlayer, clip_name: StringName) -> bool:
	var library := anim_player.get_animation_library("")
	return library != null and library.has_animation(clip_name)

## Makes `clip_name` repeat by replacing this ONE AnimationPlayer's own
## DEFAULT ("") library with a deep-duplicated copy that has loop_mode
## forced to LOOP_LINEAR -- never by mutating the shared original in place.
## Required, not just cautious: verified directly that Godot shares both the
## AnimationLibrary AND the Animation resources inside it across every
## instantiate() of the same body_scene (an imported sub-resource is not
## "local to scene" by default) -- so editing either the clip's OWN
## loop_mode property, or even just the shared library's name->clip entries,
## in place would silently change every OTHER attached body's copy too,
## exactly the class of bug Player.setup() already guards against for the
## collision capsule, for the same underlying reason. A shallow
## duplicate(false) (the Resource default) would only copy the library's own
## Dictionary, not the Animation resources it points to, so this uses
## duplicate(true) specifically.
##
## remove_animation_library()/add_animation_library() are per-NODE calls --
## AnimationPlayer keeps its own library mapping independent of any other
## node's, even one that currently points at the exact same shared
## AnimationLibrary resource -- so swapping THIS player's mapping to the
## private copy cannot affect any other attached body's AnimationPlayer.
##
## Looks the clip up only in the DEFAULT ("") library, never a named one:
## every body this project builds -- the real asset (verified:
## AnimationPlayer.get_animation_list() returns bare clip names, no
## "library/" prefix) and every stub body tests/world_fixture.gd builds --
## registers its clips there. A clip that exists but sits in some other,
## named library is left exactly as imported rather than guessed at; a
## missing library or clip is a no-op, not an error -- both are supported,
## silent degradations, same as everywhere else a body's exact contents
## cannot be assumed.
## The clips played while a ScriptedMove is driving the capsule, and only those.
##
## DERIVED, NOT LISTED BY TASTE: ScriptedMove has exactly two subclasses,
## GrabMove and SpeedVaultMove, and these are the clips
## CharacterAnimator._target_animation() routes to while one of them owns the
## body. Shimmy and the hang are in because GrabMove drives the capsule through
## those too.
##
## Jump_Start IS DELIBERATELY ABSENT even though it is a fallback on several of
## those branches, because it is also the JUMP's own clip, where the capsule is
## ballistic and the hips' own +0.38 m rise is the jump. A clip is only pinnable
## when nothing else plays it.
## PUBLIC, and named for the PREDICATE rather than for the hips, because there
## are two consumers now: _measure_scripted_hip_peaks() below, and
## CharacterAnimator._route(), which plays a clip on this list on one of the
## gate's own slots instead of through the state machine. Both are asking the
## same question -- "is a scripted move playing this?" -- and two lists that
## answer it would drift.
const SCRIPTED_MOVE_CLIPS := [&"StepUp", &"ClimbUp_1m", &"ClimbUp_2m", &"ClimbLedge",
	&"SafetyVault", &"Climb_Left", &"Climb_Right", &"Climb_Idle"]

## How far each scripted clip lifts its own hips above rest, in metres.
##
## The clip's own hip peak is SCALED to the height this obstacle needs, with a
## little hand and foot IK on top.
##
## DO NOT reach for a fixed magnitude at either end -- both ends are the same
## mistake with different constants. Left alone, a clip lifts its hips by
## whatever the animator's own
## obstacle needed -- 1.20 m for ClimbUp_2m, 0.83 for SafetyVault, 0.48 for
## StepUp -- which is right for exactly one wall and, doubled with the capsule's
## own rise, put the hands 1.32 m off. Pinned flat it lifts them by 0, which is
## right only when the capsule provides all of the clearance and leaves the
## in-place animation visibly too low in most places. One is a fixed magnitude
## of 1.20 and the other a fixed magnitude of 0; both are guesses.
##
## So the SHAPE stays -- that is the animator's craft and it is worth keeping --
## and the MAGNITUDE is set per obstacle. This is the denominator of that: a
## clip's own peak, measured once at attach, so a wanted clearance can be
## expressed as a fraction of it. See set_clip_lift_kept().
var body_clip_hip_peaks: Dictionary = {}

## Measures, rather than flattens.
##
## MEASURED IN ONE PASS. Reading the Hips position track is
## a read-only walk: DO NOT write the peaks back into the animation. Nothing is
## written, so no library is duplicated and the clips stay exactly as imported.
func _measure_scripted_hip_peaks(anim_player: AnimationPlayer) -> void:
	body_clip_hip_peaks.clear()
	var skeleton := _find_skeleton(body)
	if skeleton == null:
		return
	var hips: int = skeleton.find_bone(&"Hips")
	if hips < 0:
		return
	var bone_name: String = skeleton.get_bone_name(hips)
	var rest: float = skeleton.get_bone_rest(hips).origin.y
	for clip_name in SCRIPTED_MOVE_CLIPS:
		if not anim_player.has_animation(clip_name):
			continue
		var animation := anim_player.get_animation(clip_name)
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
				continue
			if String(animation.track_get_path(track).get_concatenated_subnames()) != bone_name:
				continue
			var peak := 0.0
			for key in animation.track_get_key_count(track):
				var value: Vector3 = animation.track_get_key_value(track, key)
				peak = maxf(peak, value.y - rest)
			if peak > 0.001:
				body_clip_hip_peaks[clip_name] = peak

## ONE DEEP COPY FOR THE WHOLE LIST. DO NOT take a single clip name and do the
## duplicate-swap per call: the caller hands this forty-five names, and copying
## per name spends 2.25 SECONDS deep-copying the entire merged animation
## library, hundreds of clips, forty-five times over, to set forty-five
## booleans.
##
## That was 95% of the cost of loading a level and it hides perfectly: the
## loading progress bar covers main.tscn's dependency tree and finishes in
## 80 ms, while this runs inside Arena._ready() where no loader can see it,
## behind a white curtain that makes it look like loading. Only in-process
## logging finds it.
##
## The copy itself has to stay: the imported library is shared, and writing
## loop_mode straight into it would reach every other instance and the cached
## resource behind them. Copying once is the whole fix.
func _ensure_clips_loop(anim_player: AnimationPlayer, clip_names: Array) -> void:
	var original_library := anim_player.get_animation_library("")
	if original_library == null:
		return
	var wanted: Array[StringName] = []
	for clip_name in clip_names:
		if original_library.has_animation(clip_name):
			wanted.append(clip_name)
	if wanted.is_empty():
		return
	var library := original_library.duplicate(true) as AnimationLibrary
	for clip_name in wanted:
		library.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	anim_player.remove_animation_library("")
	anim_player.add_animation_library("", library)

## Small helper so _wire_body_animation() does not repeat the
## get_node("BodyRoot") lookup -- BodyRoot is guaranteed present here, since
## _attach_body() already returned early if it were not.
func _body_root() -> Node3D:
	return get_node("BodyRoot") as Node3D

## Locates the node the head-follow camera should track: the SHALLOWEST
## descendant of `body_node` whose name contains "neck", or failing that
## "head" (case-insensitive substring, not an exact match -- this project's
## own body wrapper names its actual head mount "MHead" rather than "Head"
## outright; verified against the real asset's node tree and animation
## tracks, see the JOB 2 report). A breadth-first search, not a depth-first
## one, so "shallowest" is genuinely global across the whole tree rather
## than an accident of which sibling subtree happens to be walked first.
##
## Hidden branches are skipped ENTIRELY, not merely deprioritised: this
## project's own body wrapper ships a second, alternate-form hierarchy
## (visible = false) with its own head-shaped node, and a camera should
## never track a bone the player cannot currently see. Returns null -- a
## fully supported outcome, see CameraRig.update_effects() -- if nothing
## visible matches.
## body_head_path if it points at something, otherwise the name search.
##
## A path that resolves to nothing WARNS and falls back rather than failing:
## this whole subsystem is presentational, and _attach_body() above already
## takes the same line -- a body that cannot be attached degrades to "no body"
## instead of taking startup down with it. A silent fallback would be worse
## than either, since the symptom is a camera that tracks slightly the wrong
## place, which reads as a feel problem rather than a broken path.
func _resolve_head_node(body_node: Node3D) -> Node3D:
	if not body_head_path.is_empty():
		var explicit := body_node.get_node_or_null(body_head_path)
		if explicit is Node3D:
			return explicit as Node3D
		push_warning("body_head_path '%s' resolved to nothing under %s -- " 			% [body_head_path, body_node.name] 			+ "falling back to the head/neck name search")
	return _find_head_node(body_node)

func _find_head_node(body_node: Node3D) -> Node3D:
	for needle in ["neck", "head"]:
		var found := _bfs_find_by_name(body_node, needle)
		if found != null:
			return found
	return null

func _bfs_find_by_name(root: Node3D, needle: String) -> Node3D:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is Node3D and not (node as Node3D).visible:
			continue
		if String(node.name).to_lower().contains(needle):
			return node as Node3D
		for child in node.get_children():
			queue.append(child)
	return null

func _physics_process(delta: float) -> void:
	if move_manager == null:
		return
	# Sampled at the START of the tick, not carried over from the end of the
	# previous one, so a teleport made from outside this function (the arena's
	# respawn, a test placing the body) is never measured as travel.
	var tick_start_position := global_position
	# Poll unconditionally even when locked: KeyboardInputSource tracks
	# press-edges across ticks, and skipping the poll would make a key held
	# through the lock read as freshly pressed on the tick input resumes.
	var polled := input_source.poll()
	var input := MoveInput.new() if _input_locked else polled
	last_input = input
	_tick_timers(delta, input)
	# Aged alongside the other timers and BEFORE the moves run, so a status
	# that expires this tick is already gone by the time anything reads it.
	statuses.tick(delta)
	_blend_speed_scale(delta)
	# AHEAD OF EVERY READER OF in_third_person(), and immediately after the
	# ageing above so it answers for this tick rather than the last one. Both
	# _drive_body_yaw() below and the moves consult the rig for which view is
	# being rendered; pushed after them, the tick a FORCE_VIEW arrives or
	# lapses is answered with the previous tick's view.
	# FallUncontrolledMove.enter() is why that matters: it latches its eye lift
	# once, for the whole death, so a stale read there is wrong until the body
	# stops falling. _drive_body_yaw() would merely be wrong for a frame.
	if camera_rig != null:
		_push_forced_view()
		# Pushed HERE, before the moves run, so anything that owns the blur
		# for its own reasons -- FallUncontrolledMove does, every tick of a
		# death -- writes after this and wins. At rest the curve is zero, so
		# this costs the channel nothing when no view is changing.
		if screen_effects != null:
			screen_effects.set_blur(camera_rig.view_blur())
	# Before the moves run, so the body moves this tick at whatever size it is
	# now entitled to. A restore owed from an exit under a ceiling comes back
	# on the first tick there is room for it.
	_service_pending_capsule_restore()

	if hand_ik != null:
		hand_ik.update(delta)
	_drive_body_yaw(delta, input)
	_drive_clip_offset(delta)
	_drive_head_look()

	if camera_rig != null:
		camera_rig.apply_look(input.look, self, delta)

	if noclip:
		_fly_noclip(delta, input)
		return

	# Before the moves run, so a move that lands this tick reads a counter
	# that already includes this tick's descent.
	fall_tracker.update(delta, velocity.y, global_position.y)

	move_manager.physics_update(delta, input)

	# After the moves run, so grounded and horizontal_speed() both read this
	# tick's own result rather than last tick's.
	_update_speed_energy(delta, input)

	var travelled := global_position - tick_start_position
	_travel_speed = Vector2(travelled.x, travelled.z).length() / maxf(delta, 0.0001)

	# Always drained, camera_rig or not, so a landing can only ever be acted
	# on once regardless of whether anything is listening this tick.
	var landing_impact := consume_landing()
	if camera_rig != null:
		if landing_impact >= 0.0:
			camera_rig.punch_landing(landing_impact)
		# Read from the CAPSULE, not the state name: naming SLIDE and CROUCH
		# here explicitly used to work only as long as those were the only two
		# states that ever crouched the body, and silently stopped covering the
		# camera the moment a slide decayed into Crouch while the two states
		# disagreed about it (a bug in this exact spot -- see the JOB 2 report).
		# The capsule height is the one thing both states ALREADY have to keep
		# correct for collision to work at all, so reading it here instead makes
		# the camera agree with whichever state is actually responsible by
		# construction, and gets any FUTURE low state's camera cue right for
		# free the moment it calls set_capsule_height(), with no matching edit
		# needed here.
		#
		# LANDING is excluded from this read: it never resizes the capsule
		# (there is nothing to crouch INTO -- the body just holds its
		# standing height through the lockout) and drives the camera's own
		# sink continuously from lockout severity instead of this binary
		# in/out read -- see LandingMove.physics_update(), which already
		# called set_crouch_amount() a few lines up this same tick
		# (move_manager.physics_update() runs before this block). Without
		# this exclusion that call would be silently overwritten back to
		# 0.0 immediately after, every tick, and the camera would never
		# visibly sink at all.
		if move_manager.current_name != Move.LANDING:
			var crouched := current_capsule_height() < standing_height() - 0.01
			# The capsule stands up the instant the slide ends, but the EYE
			# rises over the stand-up window -- otherwise the view snaps a
			# half-metre upward on a frame where nothing else happens.
			var crouch_amount: float = 1.0 if crouched else slide_recovery_fraction()
			camera_rig.set_crouch_amount(crouch_amount)
		# Only while the slide is what is happening. The rig scales it by its
		# own crouch amount, so this only has to say whether it applies at all.
		camera_rig.set_eye_lift( 			body_slide_eye_lift if move_manager.current_name == Move.SLIDE else 0.0)
		camera_rig.set_wall_side(wall_side)
		# Fed as a plain local-space Vector3, not a Node3D reference —
		# CameraRig stays decoupled from the scene-tree/body-search concerns
		# that produced it, matching how every other per-tick input here
		# (speed, grounded, wall_side) is already a value, not an object.
		if head_node != null:
			camera_rig.set_head_offset(_camera_head_offset())
		else:
			_head_follow_fallback()
		# travel_speed(), NOT horizontal_speed() — see travel_speed()'s note on
		# why velocity lies through a vault or a mantle.
		camera_rig.update_effects(delta, travel_speed(), grounded)
		_log_grab_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_source is KeyboardInputSource:
		# Only steer the view while the mouse is actually captured. With the
		# cursor released (F1 panel open, or right after Esc) this motion is
		# the human aiming at a slider or a LineEdit, not a look input.
		if _framing_drag:
			# Framing the third-person camera, not aiming. Both would move at
			# once otherwise, and the view would swing away from whatever the
			# drag was trying to line up.
			_framing_travel += event.relative.length()
			if camera_rig != null:
				camera_rig.nudge_third_person(event.relative)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			(input_source as KeyboardInputSource).accumulate_look(event.relative)

## Mouse BUTTONS and the debug keys live HERE, behind the GUI, not in _input().
## _input() runs before the Controls get to consume anything, so with the F1
## panel open a click aimed at a slider was ALSO "click back into the game"
## and a wheel notch over the panel ALSO zoomed the third-person camera --
## THE OWNER: "在面板点击鼠标会被透传到「重新控制镜头」，第三人称下滚轮滚动面板
## 会透传到「调整相机距离」，感觉特别像前端里忘记停止冒泡." In _unhandled_input the
## game receives only what the GUI left over -- which also stops T/V from
## firing while the preset LineEdit has focus. Mouse MOTION stays in _input():
## with the cursor captured there is no GUI to compete with, and look input
## must never queue behind it.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and _handle_third_person_button(event as InputEventMouseButton):
		return
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# Click back into the game. Esc releases the cursor for the tuning
		# panel; without this the only way back in was F11, which nobody
		# guesses.
		if owns_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Esc now belongs to PauseUi._unhandled_input (autoload, consumes it globally).
		if event.physical_keycode == KEY_F11 and owns_mouse:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.physical_keycode == KEY_T:
			toggle_noclip()
		elif event.physical_keycode == KEY_V:
			# V for view. Not a debug peek -- CameraRig saves the choice and
			# keeps it across deaths (see its third_person note). One movement
			# stack and one animation set behind both views, so this switches
			# the camera and nothing else.
			if camera_rig != null:
				camera_rig.toggle_third_person()

## Straight-line flight along the view, position written directly so no
## collision or gravity applies. Deliberately does NOT run the move manager:
## the state stays Walking (see `noclip`), the timers keep ticking above, and
## the fall tracker is re-baselined every frame so that dropping out of noclip
## in mid-air is a fall from HERE rather than from wherever the flight began.
## True while the middle button is held for framing rather than aiming.
var _framing_drag: bool = false
## How far the pointer has travelled since that press, in pixels. A press that
## barely moves is a CLICK and cycles the shoulder instead.
var _framing_travel: float = 0.0

## Wheel and middle button, for the third-person view only.
##
## Returns true when the event was consumed, so the caller leaves it alone.
## Everything here is framing: none of it touches the body, the look or any
## move, and none of it does anything in first person -- where a wheel notch
## would otherwise silently change a distance nobody can see.
func _handle_third_person_button(event: InputEventMouseButton) -> bool:
	if camera_rig == null or not camera_rig.in_third_person():
		return false
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				camera_rig.zoom_third_person(-1.0)
			return true
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				camera_rig.zoom_third_person(1.0)
			return true
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_framing_drag = true
				_framing_travel = 0.0
			else:
				# A press that went nowhere is a click. The slack matters: a
				# middle button is stiff and almost always moves a pixel or two
				# on the way down, so an exact-zero test would make the cycle
				# feel broken rather than precise.
				if _framing_travel <= config.camera.third_person_click_slack:
					camera_rig.cycle_third_person_shoulder()
				_framing_drag = false
			return true
	return false


func _fly_noclip(delta: float, input: MoveInput) -> void:
	var wish := Vector3.ZERO
	if camera_rig != null:
		var view := camera_rig.global_transform.basis
		# The camera's own basis, so pitch steers the climb -- look down and
		# you descend, which is the whole point of flying to a spot.
		wish = -view.z * input.move.y + view.x * input.move.x
	# Straight up and down on jump/crouch, independent of where the view is
	# pointing: getting onto a specific rooftop is much easier when altitude
	# and heading are separate controls rather than one aimed vector.
	if input.jump_held:
		wish += Vector3.UP
	if input.crouch_held:
		wish += Vector3.DOWN
	if wish.length_squared() > 0.0001:
		wish = wish.normalized()
	velocity = wish * NOCLIP_SPEED
	global_position += velocity * delta
	set_grounded(true)
	if fall_tracker != null:
		fall_tracker.reset(global_position.y)

## Flips the cheat, leaving the body in a state the ordinary rules can take
## back over from: velocity cleared so the first real tick does not inherit
## flight speed, the fall counter re-baselined so a mid-air exit is not scored
## as a fatal drop from the ceiling, and the move manager restarted on Walking.
func toggle_noclip() -> void:
	noclip = not noclip
	velocity = Vector3.ZERO
	if fall_tracker != null:
		fall_tracker.reset(global_position.y)
	if move_manager != null:
		move_manager.start(Move.WALKING)
	# Noclip must reset the model and the camera too, or the view ends up
	# misaligned.
	#
	# Everything a death leaves behind that the ordinary rules do not take back
	# on their own. The move manager above already stops the ragdoll and clears
	# the death flag -- these are the PRESENTATION channels a death borrowed and
	# would otherwise still be holding: the eye lifted out of a floor it is no
	# longer lying on, and a screen part-way into a blackout that is not coming.
	if camera_rig != null:
		camera_rig.set_death_lift(0.0)
	if screen_effects != null:
		screen_effects.set_tint(screen_effects.tint_color(), 0.0)
		screen_effects.set_desaturation(0.0)
		screen_effects.set_blur(0.0)

# --- what the wall you just left will not let you do -------------------------
#
# A wall run leaves the body travelling AWAY from the wall, because that is what
# kicking off a wall means. For roughly a second afterwards, everything that
# would require moving back TOWARD that wall is impossible -- not as a rule
# imposed on the player, but as arithmetic. The owner put it plainly: "your legs
# are pushing off the wall, you cannot send your body to the same side."
#
# Two consequences, both reported from play:
#
#   * you cannot immediately start another run on the SAME side of a wall
#     facing the same way -- chaining up a single flat wall, which the owner
#     drew a cross through. Two walls facing EACH OTHER are a different matter
#     and stay legal, which is the zig-zag corridor; so is a wall angled away
#     from the one just left.
#
#   * you cannot mantle or vault onto the top of the wall you are running on.
#     Same reasoning, and it explains a long-standing complaint about a wall
#     run ending in a grab onto the very wall it just left.
#
# Held on Player rather than inside WallRunMove because the moves that have to
# consult it -- the grab and vault probes in AirborneMove -- run AFTER the run
# has ended and the move instance has been left behind.

## The outward normal of the wall most recently run on, and which side of the
## body it was on (-1 left, +1 right). Meaningless once recent_wall_timer
## reaches zero.
var recent_wall_normal: Vector3 = Vector3.ZERO
var recent_wall_side: int = 0
var _recent_wall_timer: float = 0.0

## Called every tick of a wall run. Refreshing rather than stamping once means
## the lockout is measured from when the wall was LEFT, which is what the rule
## is about, without WallRunMove having to notice its own ending.
func note_wall_contact(normal: Vector3, side: int) -> void:
	recent_wall_normal = normal
	recent_wall_side = side
	_recent_wall_timer = config.wall_run.same_wall_lockout

func has_recent_wall() -> bool:
	return _recent_wall_timer > 0.0 and recent_wall_normal != Vector3.ZERO

## True if starting a wall run on `normal`/`side` would mean going back to the
## wall just left.
##
## ONLY THE SAME SIDE IS CONSTRAINED. A wall on the other side is one you are
## travelling toward, which is exactly the facing-walls corridor.
##
## And on the same side, only a wall FACING THE SAME WAY is refused. The owner
## reasoned about this with a sign -- a left-hand run cannot pick up a wall
## angled one way, a right-hand run cannot pick up the other -- and the
## magnitude test below is equivalent in practice for a reason worth writing
## down: the wall angled the OTHER way recedes from a body already travelling
## away, so no probe of any reach ever finds it. Only the near-parallel case
## needs refusing, and refusing it by angle rather than by sign means not having
## to guess a convention.
func recent_wall_refuses_run(normal: Vector3, side: int) -> bool:
	if not has_recent_wall() or side != recent_wall_side:
		return false
	var facing_alike: float = normal.normalized().dot(recent_wall_normal.normalized())
	return facing_alike > cos(config.wall_run.same_wall_angle)

## True if `point` sits beyond the wall just left -- i.e. on the far side of its
## face, which is where its own top is.
##
## The normal points back toward the body, so anything on the wall's side of the
## body has a negative component along it.
func recent_wall_refuses_climb_onto(point: Vector3) -> bool:
	if not has_recent_wall():
		return false
	return (point - global_position).dot(recent_wall_normal) < 0.0

func takeoff_ground_speed() -> float:
	return _takeoff_ground_speed

## Lines released while the body was still INSIDE their volume: they stay
## unready until the body actually leaves and comes back, however long that
## takes. DO NOT re-catch on a timer alone: dismounting at the foot of a ladder
## then re-grabs the player the moment it runs out, while they are still
## standing in the volume doing nothing.
var _lines_awaiting_exit: Dictionary = {}

## Horizontal speed TOWARD a latched line that counts as meaning it, m/s.
## [ME:CONFIRMED] in the original a ladder re-catches about a second later if
## the body carries horizontal speed toward it -- holding W at it is enough --
## and the speedrun trick of sliding down a ladder and grabbing it again just
## before a fatal landing is built on exactly that.
const LINE_RELATCH_SPEED := 0.5

## True when `line` is off its own re-catch cooldown, AND -- for a line
## released without leaving its volume (the ladder's latch, see
## note_line_left) -- the body is actively pushing toward it. Standing
## still inside the volume never re-grabs; holding W at the ladder does.
func line_ready(line: InterestLine) -> bool:
	var id: int = line.get_instance_id()
	if _line_cooldowns.has(id):
		return false
	if not _lines_awaiting_exit.has(id):
		return true
	var at: Vector3 = line.sample(line.closest_offset(global_position))["position"]
	var toward := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	if toward.length_squared() < 0.0001:
		return true
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	return horizontal.dot(toward.normalized()) > LINE_RELATCH_SPEED

## Spends `line`'s one passive chance: the volume will not catch this body
## again until it leaves and returns -- or pushes toward the line (the same
## bypass line_ready() already grants the release latch). A first failed check
## -- walked in backwards, ladder outside the view's 180 degrees -- must NOT be
## retried by turning on the spot: entering the volume facing away and then
## turning round does not mount the ladder.
func latch_line(line: InterestLine) -> void:
	if interest_lines.has(line):
		_lines_awaiting_exit[line.get_instance_id()] = true

## Arms `line`'s own re-catch cooldown -- called by every line move's exit.
## The timer guards the flight OUT of the volume; the awaiting-exit latch
## (opt-in via `until_exit`) guards standing still inside it. Only the
## LADDER asks for the latch: it is the one ground-enterable line, so only
## there can a body released inside the volume just STAND in it. An
## air-entry line (zipline under a low cable) latched this way could never
## be re-taken at all -- the body cannot leave the volume by jumping at it.
func note_line_left(line: InterestLine, seconds: float, until_exit: bool = false) -> void:
	if seconds > 0.0:
		_line_cooldowns[line.get_instance_id()] = seconds
	if until_exit and interest_lines.has(line):
		_lines_awaiting_exit[line.get_instance_id()] = true

func _tick_line_cooldowns(delta: float) -> void:
	for key in _line_cooldowns.keys():
		var remaining: float = _line_cooldowns[key] - delta
		if remaining <= 0.0:
			_line_cooldowns.erase(key)
		else:
			_line_cooldowns[key] = remaining

func _tick_timers(delta: float, input: MoveInput) -> void:
	_tick_gravity_window(delta)
	_stagger_immunity = maxf(_stagger_immunity - delta, 0.0)
	_tick_line_cooldowns(delta)
	if grounded:
		_coyote_timer = config.pawn.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	_step_grace_timer = maxf(_step_grace_timer - delta, 0.0)
	_slide_recovery_timer = maxf(_slide_recovery_timer - delta, 0.0)
	_recent_wall_timer = maxf(_recent_wall_timer - delta, 0.0)
	_was_grounded = grounded

	if input.jump_pressed:
		_jump_buffer_timer = config.pawn.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if input.turn_pressed:
		_turn_buffer_timer = config.pawn.jump_buffer_time
	else:
		_turn_buffer_timer = maxf(_turn_buffer_timer - delta, 0.0)

	# Deliberately keyed on crouch_PRESSED, not crouch_held: this buffer stores
	# presses, so holding the key down refills it exactly once. A held-state
	# version would re-arm every tick and let a slide re-enter the instant the
	# previous one ended, which is the strobing this gate exists to prevent.
	if input.crouch_pressed:
		_roll_buffer_timer = config.pawn.roll_trigger_time
	else:
		_roll_buffer_timer = maxf(_roll_buffer_timer - delta, 0.0)

## Spends a buffered jump if one is pending and the player is still within
## coyote time. Returns true at most once per press.
func consume_jump() -> bool:
	# REFUSED HERE, not in MoveManager.can_enter(). WalkingMove writes the
	# launch velocity and calls move_and_slide() BEFORE it returns JUMP, so a
	# refusal at the transition would leave the body in the air and the state
	# on the ground. Refusing the spend keeps the whole branch unentered.
	#
	# Returns false WITHOUT clearing the buffer: the player pressed, and the
	# press must still be there the moment the block lifts.
	if statuses.is_move_blocked(Move.JUMP):
		return false
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return true
	return false

## Spends a buffered jump if one is pending, WITHOUT requiring coyote time.
## For moves that are legitimately, truthfully airborne the whole time they
## run -- a wall run declares grounded=false every tick (see WallRunMove),
## so the coyote timer consume_jump() requires never refills there, and
## consume_jump() would be permanently dead on the wall. But a press is not
## only relevant on the exact tick a move starts reading it: FallingMove hands
## off to WallRunMove the moment it detects a wall, before WallRunMove's
## own first physics_update() ever runs, so a press made on the attach tick
## itself -- or up to jump_buffer_time earlier, same as any other buffered
## jump -- must not be silently dropped on what is otherwise the most
## timing-sensitive move in the game. Still spends (clears) the buffer, same
## as consume_jump(), so a consumed press cannot also fire a second jump
## later.
func consume_buffered_jump() -> bool:
	if statuses.is_move_blocked(Move.JUMP):
		return false
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		return true
	return false

## Arms the jump buffer directly. FOR TESTS: the keyboard path fills this from
## a press edge, which a headless test has no way to produce.
func arm_jump_buffer_for_test() -> void:
	_jump_buffer_timer = config.pawn.jump_buffer_time
	_coyote_timer = config.pawn.coyote_time

## The same, for Q. See _turn_buffer_timer.
func consume_buffered_turn() -> bool:
	if _turn_buffer_timer > 0.0:
		_turn_buffer_timer = 0.0
		return true
	return false

## Lifts the body over an obstacle no taller than `max_step_height`, so the
## ankle-high clutter a rooftop is covered in -- planks, bricks, litter -- does
## not stop a run dead.
##
## Godot 4's CharacterBody3D has NO built-in step-up. `floor_snap_length` only
## keeps a body attached on the way DOWN, so without this a 5 cm plank blocks
## the capsule outright. (pawn_config's own note used to claim move_and_slide
## handled this; it does not, and that assumption is why the value sat unread.)
##
## Classic up/forward/down probe, run only once the intended motion is actually
## blocked, so it costs nothing on open ground. Deliberately free: no speed
## cost, no state change, no animation -- matching Mirror's Edge, where
## MaxStepHeight is engine-level and the player never perceives it.
##
## Returns how far the body rose so the camera can smooth it out; 0.0 when no
## step was taken.
func try_step_up(delta: float) -> float:
	if config == null:
		return 0.0
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 1e-8:
		return 0.0
	# The blocker is captured, not just detected: naming what stopped the player
	# is most of the value of the trace below.
	var blocker := KinematicCollision3D.new()
	if not test_move(global_transform, motion, blocker):
		return 0.0                        # open ground, the overwhelmingly common case

	var what := _collider_name(blocker)

	# NO ramp bail on the contact normal, and the reason is geometric rather
	# than a matter of picking a better threshold.
	#
	# The capsule is 0.4 m in radius with a rounded bottom. Against a 0.32 m
	# parapet it makes contact near its widest point, square on the parapet's
	# VERTICAL face, and reads a normal of about 0. Against a board a few
	# centimetres thick there is no vertical face tall enough to meet: the
	# lower hemisphere scuffs the board's TOP EDGE instead, and Godot reports
	# the top FACE's normal -- measured 0.802, 0.891, 0.976, 0.982, 0.995 as
	# the body closed on one. So the shorter the obstacle, the more certain the
	# ramp verdict, which is exactly backwards.
	#
	# In play that read as: parapets slid over without a hitch, thin boards
	# caught the feet every time, and the step probe logged a wall of "是斜坡"
	# without ever once logging 抬升.
	#
	# Rejecting on the measured RISE instead was tried and reverted: a walkable
	# slope yields up to motion * tan(45 deg) = 0.12 m per tick at running
	# speed, overlapping the very board thicknesses it would need to separate.
	#
	# What the bail actually protected was the CAMERA -- a long ramp firing this
	# probe every tick pushed an offset per tick and read as a shaking screen.
	# That is handled where it belongs now, by the callers' own step_offset
	# threshold, so the probe is free to answer the only question it is good at:
	# is there something here I can stand on top of.
	var normal_y: float = blocker.get_normal().y
	var max_rise: float = config.pawn.max_step_height

	# Up to the blocking face, then rise -- no further than a ceiling allows, so
	# a low roof shortens the step rather than cancelling it.
	var probe := global_transform.translated(blocker.get_travel())
	var up_hit := KinematicCollision3D.new()
	var risen := Vector3.UP * max_rise
	if test_move(probe, risen, up_hit):
		risen = up_hit.get_travel()
	if risen.length() <= 0.01:
		return _step_log(what, "头顶无空间", 0.0)
	var lifted := probe.translated(risen)
	if test_move(lifted, motion):
		return _step_log(what, "太高，是墙不是台阶 (n.y=%.3f)" % normal_y, 0.0)

	# RAMP OR STEP, asked as a question about SHAPE rather than about size or
	# about the contact normal -- both of which were tried and both of which
	# failed, for reasons worth keeping:
	#
	#   The contact normal cannot tell them apart. The capsule is 0.4 m in
	#   radius with a rounded bottom, so against anything shorter than that it
	#   scuffs the TOP EDGE rather than meeting a vertical face, and Godot
	#   reports the top face's normal. Measured against thin boards: 0.802,
	#   0.891, 0.976, 0.995 -- all "ramp", none of them ramps. The shorter the
	#   obstacle the more certain the wrong answer, which is why a 0.32 m
	#   parapet was slid over cleanly while a plank caught the feet every time.
	#
	#   Size cannot tell them apart either. A walkable slope yields up to
	#   motion * tan(45 deg) = 0.12 m per tick at running speed, which overlaps
	#   the thickness of the boards this needs to step onto.
	#
	# What DOES separate them is what happens further along: a board's top face
	# is flat, so probing further finds the same height, while a ramp keeps
	# climbing. So probe twice and compare.
	var direction := motion.normalized()
	var near: float = _probe_landing(lifted, direction, current_capsule_radius() + 0.05, risen.length())
	var far: float = _probe_landing(lifted, direction, current_capsule_radius() + 0.25, risen.length())
	if near == INF:
		return _step_log(what, "对面探空，是坑不是台阶", 0.0)
	# Nothing 0.2 m further on either: the near probe found a RIDGE, not a
	# surface -- a pipe, a railing, the lip of something thin. Measured against
	# a steeply angled pipe, which the body climbed a few centimetres at a time
	# because the far probe sailed past it and the ramp test therefore never
	# ran. A step has to have somewhere to stand on the far side of its edge;
	# anything narrower belongs to vault or grab, not to step-up.
	if far == INF:
		return _step_log(what, "顶面太窄，站不住", 0.0)
	# SYMMETRIC. The far probe must agree with the near one in BOTH directions:
	#
	#   far HIGHER  -- the surface keeps climbing, so it is a ramp and
	#                  move_and_slide() owns it.
	#   far LOWER   -- the near probe found an edge, not a floor: the ground
	#                  drops away again within 0.2 m, so there is nothing to
	#                  stand on up there.
	#
	# Only checking the first case left a leaning billboard climbable: its far
	# probe cleared the panel and landed on the ground BEHIND it, which is
	# neither "still climbing" nor "empty", so the step was allowed. With the
	# body pinned against the panel and unable to advance, every tick reported
	# the same 0.156 m step and it walked up the face of it.
	if absf(far - near) > STEP_RAMP_TOLERANCE:
		# Still climbing 0.2 m further on: a slope, which move_and_slide()
		# already handles. Stepping it instead would climb at the reach's rate
		# rather than the body's -- 0.45 m of reach on a 27-degree slope reads
		# 0.23 m of "step" while the body travels 0.12 m, so the player ascends
		# at twice their own speed and leaves the surface.
		return _step_log(what, "顶面不平 n.y=%.3f 落差 %.3f" % [normal_y, far - near], 0.0)

	# NO walkable-normal test on the landing, and this project has paid for that
	# lesson twice. A capsule settling beside a step contacts its EDGE first,
	# not its top face, and an edge reports an in-between normal (measured 0.36
	# and 0.57 against a parapet the player could plainly stand on).
	# move_and_slide() applies Godot's own floor_max_angle immediately after, so
	# a genuinely unstandable surface is caught there.
	var rise: float = near
	if rise <= 0.01:
		return _step_log(what, "落差过小 %.3f m" % rise, 0.0)
	global_position.y += rise
	# Opens the window described on _step_grace_timer. Armed here rather than
	# by each caller so no move can forget it, and so the two ticks the
	# manoeuvre actually takes are covered rather than only the first.
	_step_grace_timer = config.pawn.step_up_grace_time
	return _step_log(what, "抬升 %.3f m" % rise, rise)


## How much higher than the body the ground is, `distance` ahead of a lifted
## probe. INF when there is nothing under it at all.
##
## Returns a RISE relative to the body's current height, so the two calls in
## try_step_up() can be compared directly.
func _probe_landing(lifted: Transform3D, direction: Vector3, distance: float, \
		drop: float) -> float:
	# The probe has to be able to REACH its sampling point. Blocked on the way
	# there means the point is inside geometry, and a sample taken from inside
	# a solid is meaningless: the downward sweep collides immediately, travels
	# nothing, and hands back the probe's own height.
	#
	# That is how a steep panel got climbed. At 57 degrees the surface is 0.69 m
	# up at the near sample and 1.0 m up at the far one, so BOTH probes sat
	# buried in it and both returned the same number -- and a symmetric test
	# comparing two identical readings sees a perfectly flat surface. Measured
	# in play as a steady 0.293 m step, every tick, up the face of a ramp well
	# past the walkable angle. Steeper panels were fine, because there the
	# forward carry above is blocked too and the whole thing is called a wall.
	if test_move(lifted, direction * distance):
		return INF
	var at := lifted.translated(direction * distance)
	var landing := KinematicCollision3D.new()
	if not test_move(at, Vector3.DOWN * drop, landing):
		return INF
	return (at.origin.y - landing.get_travel().length()) - global_position.y

## PROJECT-DEFINED. How far the two landing probes may disagree, in EITHER
## direction, and still be called one flat surface.
##
## TIGHT ON PURPOSE. Over the probes' 0.2 m of separation a slope gains
## 0.2 * tan(angle), so this value decides the shallowest ramp still
## recognised as one: 0.02 catches everything past about 6 degrees, while 0.05
## let 14-degree slopes through. A slope that gets past this is STEPPED rather
## than walked, which pushes a camera offset every tick -- in play that read as
## the view sinking to the floor while climbing a gentle ramp, and recovering
## the moment the player stopped moving.
const STEP_RAMP_TOLERANCE := 0.02

## Sets the body back down when travelling has lifted it clear of the floor by
## less than one step, and snaps it there. Called AFTER move_and_slide().
##
## WHAT THIS IS FOR, measured in play. Ankle-high clutter with a SLOPED face --
## the rooftop litter meshes, reading normals of 0.89 to 0.99 -- is correctly
## refused by try_step_up() as a ramp and handed to move_and_slide(), which
## climbs it. But riding up and off a small ramp throws the body clear of the
## floor for a tick or two, and every move that reads leaving the floor as a
## ledge exit cancels itself on it:
##
##     Walking -> Slide -> Falling -> Grab -> Falling -> Walking
##
## The slide was neither blocked nor mis-stepped; it was thrown. The step-up
## grace window does not cover this, because no step-up ever fired.
##
## The same call also removes the little hop from walking DOWN a shallow step.
##
## Borrowed from the Godot community's standard stair-stepping shape (see
## Andicraft/stairs-character, MIT), which pairs a step-up sweep with exactly
## this descent half. Only the descent half is taken here: this project's own
## step-up probe is measured and documented, and replacing it is a separate
## question (docs/feel-backlog.md).
func try_step_down() -> bool:
	if config == null or is_on_floor():
		return false
	# Airborne when the tick STARTED means falling or jumping, not thrown by
	# geometry -- leave it alone, or a fall gets caught by every ledge it
	# passes within a step of.
	if not _was_grounded:
		return false
	# NO test on velocity.y, deliberately. Rising looks like a jump, but a jump
	# cannot reach this function: every jump branch returns JUMP from inside its
	# own move, before the move_and_slide() this is called after. So an upward
	# velocity here was given by GEOMETRY -- which is exactly the case this
	# exists to catch. Riding up and off a low sloped obstacle leaves the body
	# rising as it parts company with the floor, and an early-out here refused
	# every one of them (measured: ten consecutive "是斜坡" verdicts against the
	# litter meshes, with the slide cancelled each time and the grace window
	# never opening).
	# Hand-rolled rather than apply_floor_snap(): measured in a descending
	# flight of 0.3 m steps, that call left the body exactly where it was and
	# is_on_floor() still false, whatever floor_snap_length was set to.
	#
	# Returns whether it caught anything, because is_on_floor() is NOT updated
	# by moving the body directly -- the caller has to declare grounded-ness
	# from this instead. That is fine here: `grounded` is the authority every
	# move reads, and it is a DECLARATION rather than a query for exactly this
	# kind of reason.
	var landing := KinematicCollision3D.new()
	if not test_move(global_transform, Vector3.DOWN * config.pawn.max_step_height, landing):
		return false                      # nothing within a step below: a real fall
	global_position += landing.get_travel()
	return true

## Traces every step-up decision, naming the geometry involved. Off by default;
## turn it on in the inspector when a spot in a level catches the player and you
## want to know what it is and why the probe refused it.
##
## Kept rather than deleted after the bug it was written for: the probe fires
## against real level geometry, so "which mesh, and what did we decide" is the
## only view into it that exists. Silent on open ground -- nothing prints until
## something actually obstructs the player -- so leaving it on costs one line
## per obstacle encountered, not one per frame.
##
## Against a blockout imported from another game's level data, the collider name
## carries that game's own mesh name (e.g. S_R_05_03_F_1234), which makes a
## report like "caught on the parapets" answerable directly from the log.
@export var debug_step_up: bool = false
var _step_log_last: String = ""

## Recent step-up decisions, oldest first, as "<seconds> <collider> <outcome>".
##
## A HISTORY rather than a single value: the interesting decision is the one
## made at the moment the player caught on something, and by the time they can
## look at the HUD the probe has usually logged several ordinary "是斜坡"
## results on top of it. Consecutive identical decisions collapse, so leaning
## on one obstacle produces one line rather than sixty a second.
var step_decisions: PackedStringArray = PackedStringArray()

const STEP_DECISION_LINES := 5


func _collider_name(collision: KinematicCollision3D) -> String:
	var collider: Object = collision.get_collider()
	return (collider as Node).name if collider is Node else "<unknown>"


func _record_step_decision(key: String, what: String, outcome: String) -> void:
	if key == _last_recorded_step_key:
		return
	_last_recorded_step_key = key
	step_decisions.append("%6.2f %s %s" 		% [Time.get_ticks_msec() / 1000.0, what, outcome])
	while step_decisions.size() > STEP_DECISION_LINES:
		step_decisions.remove_at(0)

var _last_recorded_step_key: String = ""

func _step_log(what: String, outcome: String, value: float) -> float:
	# Deduplicated on (collider, outcome): the probe re-runs every tick while the
	# player leans on the same obstacle, and 60 identical lines a second buries
	# the transition that actually matters.
	var key := what + "|" + outcome
	_record_step_decision(key, what, outcome)
	if debug_step_up and key != _step_log_last:
		_step_log_last = key
		print("[step] %-28s %-24s speed=%.2f pos=(%.2f, %.2f, %.2f)"
				% [what, outcome, Vector3(velocity.x, 0.0, velocity.z).length(),
				global_position.x, global_position.y, global_position.z])
	return value


## Spends a buffered crouch press if one is pending. Returns true at most once
## per press — this is what keeps the roll-into-slide chain reachable without
## reopening the held-key strobe. Renamed from consume_crouch(): the single
## buffered press resolves into Roll, Slide or Crouch by CONTEXT (touchdown
## and fall height, or grounded speed) -- see walking_move.gd's table comment
## and falling_move.gd's landing branch, the two places that read it.
func consume_roll() -> bool:
	if _roll_buffer_timer > 0.0:
		_roll_buffer_timer = 0.0
		return true
	return false

## World-space horizontal direction the player is asking to move in.
func wish_direction(input: MoveInput) -> Vector3:
	var dir := global_transform.basis * Vector3(input.move.x, 0.0, -input.move.y)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()

## Which way the body is going AT something, as a unit vector, or ZERO if it is
## going nowhere and asking for nothing.
##
## Horizontal velocity when there is any, and the player's own wish direction
## when there is not. That fallback is the whole point: the owner reports that
## in the original you can stand pressed against a wall, motionless, hold W and
## jump, and climb it. Measured from velocity alone that approach is a right
## angle to every wall in the world, so no head-on test can ever pass.
##
## Not merely defaulting to the FACING, which would be the obvious third
## option: a player standing near a wall and jumping straight up while happening
## to look at it has asked for nothing, and would get a climb anyway.
func approach_direction() -> Vector3:
	var travelling := Vector3(velocity.x, 0.0, velocity.z)
	if travelling.length_squared() > 0.0001:
		return travelling.normalized()
	return wish_direction(last_input) if last_input != null else Vector3.ZERO

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

## How fast the body ACTUALLY moved horizontally last physics tick, measured
## from its displacement rather than from `velocity`.
##
## This exists because `velocity` lies during a scripted move: SpeedVaultMove and
## GrabMove drive global_position directly and deliberately zero velocity
## for the duration (see ScriptedMove), so horizontal_speed() reads 0 through
## the whole vault or mantle. Feeding that to the camera collapsed the FOV back
## toward fov_base at precisely the moment the player is moving fastest — a
## visible slow-down cue on the one action that is supposed to read as a burst.
##
## Displacement never lies, in any state, so the camera gets this instead of
## horizontal_speed(). Note what it honestly DOES report: ScriptedMove's arc is
## ease-out, so the last few ticks of a vault or mantle really are slow and the
## FOV really does ease back over them. That is the manoeuvre ending, not a
## false slow-down at its peak — measured on a fast vault, the FOV now rides
## 92.6 -> 93.7 -> 85.4 across the move where feeding velocity took it to 77.2.
##
## The physics states are unaffected: their speed gates
## (slide entry, vault_min_speed, slide decay) are all questions about
## VELOCITY — what the body is carrying and will keep carrying — not about
## distance covered, and a scripted move's 0 velocity is the correct answer for
## those.
func travel_speed() -> float:
	return _travel_speed

## The current ground speed ceiling. Every move that wants "top speed" asks
## here rather than reading pawn.ground_speed, which is now only the curve's
## own upper bound rather than a target anything reaches directly.
## The small forward nudge a take-off adds, or zero for a standing jump.
##
## [ME:CONFIRMED 02 §2.4] JumpAddXY = 100 uu/s as a value, and the CONDITION is
## measured in the original too: a jump taken while running picks up about
## 4 km/h, and a jump from a standstill picks up nothing at all. DO NOT add it
## unconditionally -- that gives a standing jump 1 m/s of drift the original
## never has.
##
## Gated on the movement KEYS rather than on current speed: the question the
## original appears to ask is whether the player is asking to travel, and
## speed alone cannot distinguish a standing start from a body still sliding
## to a halt.
func jump_add_velocity(input: MoveInput) -> Vector3:
	if input.move == Vector2.ZERO:
		return Vector3.ZERO
	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return Vector3.ZERO
	return facing.normalized() * config.pawn.jump_add_xy

## True while the body is mid-step-up: raised, but not yet set down on the
## step. Callers use it to tell "climbing a kerb" apart from "walked off a
## ledge", which are otherwise the same reading.
func in_step_grace() -> bool:
	return _step_grace_timer > 0.0

## True while a stagger cannot land. Read by MoveManager, armed by
## LandingMove.exit() -- the lockout is the thing that knows when it is over.
func is_stagger_immune() -> bool:
	return _stagger_immunity > 0.0

## Starts the window. Called from LandingMove.exit(), so ANY landing lockout
## grants it, not only one a stagger caused: a body that has just picked
## itself up off the floor is exactly as unable to absorb another stumble.
func arm_stagger_immunity() -> void:
	_stagger_immunity = config.pawn.stagger_immunity_time

func speed_cap() -> float:
	# Scaled HERE rather than at each caller: this is the one function every
	# move asks "how fast may I go", so a status applied to it reaches all of
	# them and none of them needs to know statuses exist. Same shape as
	# MoveConfig.speed_modifier, which the crouch already rides.
	#
	# The scale is the EASED one, not statuses.speed_scale(). See
	# _blend_speed_scale(): the ceiling slides, the body chases it.
	return speed_energy.cap() * _speed_scale

## Slides the ceiling's scale toward whatever the status list currently says.
##
## DO NOT ease this by lowering accel_rate instead: that is the body's own
## responsiveness and it belongs to every move, not to the one region that
## happens to be capping the player.
##
## move_toward on a 0..1 scale, so the dial is a time for the full range and a
## half-range change takes half of it -- which is what "a cap change should
## feel proportional to how big it is" wants.
func _blend_speed_scale(delta: float) -> void:
	var wanted: float = statuses.speed_scale()
	var seconds: float = maxf(config.pawn.speed_cap_blend_time, 0.001)
	_speed_scale = move_toward(_speed_scale, wanted, delta / seconds)

## Which accumulation factor this tick's input asks for. The original
## declares three (02 §2.1) and this is the reading that makes all three
## usable: ordinary running is the sprint factor (there is no sprint key --
## the curve IS the sprint), the walk modifier drops to the walk factor, and
## a mostly-lateral input takes the strafe factor.
func _energy_mode(input: MoveInput) -> int:
	if input.walk_held:
		return SpeedEnergy.WALK
	if absf(input.move.x) > absf(input.move.y):
		return SpeedEnergy.STRAFE
	return SpeedEnergy.SPRINT

## Energy accrues only while GROUNDED, actually asking to move, and actually
## travelling near the ceiling that energy has already bought. Held (neither
## banked, bled, nor charged for turning) while airborne: 10.1 mechanic 2 is
## explicit that speed earned before take-off is carried across the jump
## intact, and bleeding the energy that BOUGHT that speed mid-flight would
## contradict it. Turning while airborne is likewise free -- air_control is
## 0.025, so there is barely any turning to charge for, and charging for it
## would double-punish a jump the player is already committed to.
func _update_speed_energy(delta: float, input: MoveInput) -> void:
	var wish := wish_direction(input)
	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO
	if not grounded:
		# Nothing is banked or bled in mid-air, and turning is not billed tick
		# by tick either -- there is no traction to lose speed through. The
		# heading at take-off is remembered instead, and the whole rotation is
		# settled on landing.
		if _takeoff_dir == Vector3.ZERO:
			_takeoff_dir = facing
			_takeoff_ground_speed = horizontal_speed()
			_airborne_time = 0.0
		_airborne_time += delta
		_last_wish_dir = wish
		return
	# Just landed with a heading owed. Billed as ONE turn through the angle
	# between take-off and touchdown, at the rate it was actually swung
	# (the airborne time), so a lazy mid-air adjustment costs little and a
	# hard 180 costs what a hard 180 costs. Without this a player could turn
	# the corner in the air and arrive owing nothing at all.
	if _takeoff_dir != Vector3.ZERO:
		if facing != Vector3.ZERO:
			var swung: float = absf(_takeoff_dir.signed_angle_to(facing, Vector3.UP))
			# Guarded against float noise, not against small turns: a body that
			# took off and landed on the same heading still differs in the last
			# few bits, and billing that charged a hop for turning.
			if swung > 0.001:
				speed_energy.spend_turn(swung, maxf(_airborne_time, delta))
		_takeoff_dir = Vector3.ZERO
		_airborne_time = 0.0
	_charge_turn(wish, delta)
	if wish == Vector3.ZERO:
		speed_energy.decay(delta)
		return
	# Scaled by the active move's own ceiling. Without this the threshold is
	# measured against the STANDING cap while a crouch is held to 40% of it,
	# so crouching can never bank -- and since turning still charges, a
	# crouched turn drains energy on a one-way ratchet that only standing up
	# releases. That bottomed out at speed_min_base_velocity * crouched_pct =
	# 0.04 m/s, with no way back up.
	# Nothing banks during the stand-up after a slide: the ceiling stays pinned
	# at whatever the slide left it at, so a slide preserves the speed it was
	# entered with but cannot be used to keep climbing.
	var reachable: float = speed_cap() * move_manager.current_move_speed_modifier()
	if _slide_recovery_timer > 0.0:
		pass
	elif horizontal_speed() >= reachable * config.pawn.energy_accumulate_speed_ratio:
		speed_energy.accumulate(delta, _energy_mode(input))
	else:
		# Asking to move but not actually getting anywhere -- shoved into
		# geometry, or still climbing toward a ceiling already paid for.
		# Neither banks anything; neither is a reason to bleed, either.
		pass

## Resynchronises the turn tax to wherever the body is facing NOW, so the swing
## that just happened costs nothing.
##
## For SCRIPTED turns only. The tax is charged on the change in wish direction
## (see _charge_turn below), which models a player swinging the view and the
## body fighting to follow. A move that rotates the body itself is not that: it
## is an animation the player asked for by name. Without this, pressing Q while
## holding W flips the wish direction through half a circle in one tick and the
## tax bills the whole thing -- which would make Q the most expensive key on
## the board and the turn a move nobody would ever use.
##
## Deliberately a RESYNC and not a suppression flag: whatever the player does
## on the tick after the turn is charged normally, measured from the facing the
## turn actually left them with.
func forgive_turn() -> void:
	_last_wish_dir = wish_direction(last_input) if last_input != null else Vector3.ZERO

## Turning is a continuous tax with no free allowance (10.1 mechanic 3): the
## research searched for a "costs nothing below N degrees" parameter and
## found none anywhere in the game, which is what forces players to plan a
## line instead of improvising one.
##
## Charged on the WISH direction, not the camera yaw and not the velocity
## direction. Not the camera, because turning your head to read the route
## ahead should be free -- it is turning the RUN that costs. Not the velocity
## either, because accel_rate 61.44 makes the velocity lag the intent, which
## would smear the charge across the frames after the decision instead of
## billing the decision itself.
func _charge_turn(wish: Vector3, delta: float) -> void:
	if wish == Vector3.ZERO or _last_wish_dir == Vector3.ZERO:
		# Nothing to compare against. A momentary key release passes through
		# zero, and billing that transition would charge for letting go.
		_last_wish_dir = wish
		return
	var radians: float = absf(_last_wish_dir.signed_angle_to(wish, Vector3.UP))
	if radians > 0.0:
		speed_energy.spend_turn(radians, delta)
	_last_wish_dir = wish

## The downhill component of `direction`, projected onto the current floor,
## in Friction's convention (+1 straight down the fall line, -1 straight up,
## 0 flat). Same projection SlideMove._slope_direction() uses, generalised to
## an arbitrary direction since Player has no persisted heading of its own --
## callers pass the residual horizontal velocity, which is what a braking
## ground_accelerate() call is actually decelerating. 0 with no floor or no
## direction, so an airborne or motionless call resolves cleanly.
func ground_grade(direction: Vector3) -> float:
	if not grounded or direction == Vector3.ZERO:
		return 0.0
	var normal: Vector3 = get_floor_normal()
	if normal.length_squared() < 0.0001:
		return 0.0
	var projected := direction - normal * direction.dot(normal)
	if projected.length_squared() < 0.0001:
		return 0.0
	return -projected.normalized().y

## Ground movement: converge on the target velocity, and brake when idle.
## `grade` is the downhill component of the current heading (+1 straight
## down the fall line, -1 straight up, 0 flat); see Friction.
func ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float, grade: float = 0.0) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		var braking: float = Friction.walk_friction(config.pawn, \
			move_manager.current_move_friction_modifier(), grade)
		horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)
	else:
		horizontal = horizontal.move_toward(wish_dir * target_speed, config.pawn.accel_rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

## Air movement, the original's way: a Quake-style projection scaled by
## air_control.
##
## An earlier version of this project forbade the projection from ever
## reducing horizontal speed, so holding the opposite key in mid-air did
## nothing at all. That guard is gone: the original uses ordinary low air
## control, and "commit to the jump you made" comes from air_control being
## 0.025 -- half the engine's own default -- not from a special rule. At
## 1.536 m/s^2 a full 1.40 s hang time can shed at most ~2.1 m/s even if the
## player holds backward the whole way, which is a correction, not a brake.
##
## Only ever adds speed along wish_dir, and only up to a ceiling measured
## along that direction. The ceiling is NOT a flat air_speed: it is
## min(air_speed, max(speed_cap(), speed_along_wish)). air_speed
## itself (see its own comment in pawn_config.gd -- ME's AirSpeed,
## essentially uncapped) is deliberately too high to ever bind in practice;
## it exists so momentum carried in from elsewhere (a wall-run or slide boost
## exceeding speed_cap()) is never reduced by air control. speed_cap() is the
## floor UNDER that: with air_accel tiny (see above), a long fall or a chain
## of jumps has plenty of TIME to slowly climb toward air_speed even without
## any exploit-like input, which would let mere airtime manufacture speed no
## ground state could reach on its own -- exactly the invariant
## tests/legacy/test_landing.gd's test_a_landing_can_never_add_speed_however_the_
## keep_ratio_is_tuned and tests/legacy/test_slide_state.gd's
## test_chained_slide_then_jump_cannot_stack_the_entry_boost used to pin --
## both ARCHIVED by Task 1 and NOT in the running suite, so nothing enforces
## this today; restore the pins when the behavioural suite is rewritten. Taking
## the max with the CURRENT speed_along_wish (not a flat speed_cap()) is what
## keeps carried-in momentum from being reduced here: a player already faster
## than the cap gets zero headroom (the ceiling sits at their own current
## speed), never a forced slowdown.
func air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed_along_wish := horizontal.dot(wish_dir)
	var ceiling := minf(config.pawn.air_speed, maxf(speed_cap(), speed_along_wish))
	var headroom := ceiling - speed_along_wish
	if headroom <= 0.0:
		return
	# AirControl is a MULTIPLIER on ground acceleration (09 §9.1), not an
	# acceleration in its own right: 61.44 * 0.025 = 1.536 m/s^2.
	var air_accel: float = config.pawn.accel_rate * config.pawn.air_control
	var candidate := horizontal + wish_dir * minf(air_accel * delta, headroom)
	velocity.x = candidate.x
	velocity.z = candidate.z

## DEBUG. Reports the EYE's real pose in the world, and how far it moved since
## the previous frame, for every frame of a reach or a hang IN WHICH IT MOVED.
##
## A camera cut IS a large single-frame delta, so this measures the thing being
## complained about directly. The breakdown beside it says which component
## produced it: the body's yaw, the view's own pitch against the floor
## currently in force, or the rig's trailing lag. A report can only say "it
## jumped"; this says which of the three jumped, and by how much.
@export var debug_grab_camera: bool = false
var _grab_cam_last_origin: Vector3 = Vector3.ZERO
var _grab_cam_last_forward: Vector3 = Vector3.ZERO
var _grab_cam_has_last: bool = false

## Printed for these only. The eye's pose is REMEMBERED every frame regardless,
## so the first line of a reach still measures against the frame before it --
## which is the one the owner reports cutting, and would otherwise be the one
## frame no comparison exists for.
const _GRAB_CAM_STATES: Array[StringName] = [&"IntoGrab", &"Grab"]

func _log_grab_camera() -> void:
	if camera_rig == null or camera_rig.camera == null or move_manager == null:
		return
	var eye: Transform3D = camera_rig.camera.global_transform
	var forward: Vector3 = -eye.basis.z
	var moved: float = 0.0
	var turned: float = 0.0
	if _grab_cam_has_last:
		moved = eye.origin.distance_to(_grab_cam_last_origin)
		turned = rad_to_deg(forward.angle_to(_grab_cam_last_forward))
	_grab_cam_last_origin = eye.origin
	_grab_cam_last_forward = forward
	_grab_cam_has_last = true
	if not debug_grab_camera or not _GRAB_CAM_STATES.has(move_manager.current_name):
		return
	# Silent while the eye is holding still. A hang lasts as long as the player
	# leaves it alone, and sixty identical lines a second buries the handful of
	# frames the manoeuvre actually moves in -- which are the only ones this
	# exists to show. Thresholds sit just above the float noise a stationary
	# eye produces, so an eye that IS moving still reports every frame of it.
	if moved < 0.001 and turned < 0.05:
		return
	var look: Dictionary = camera_rig.look_debug()
	print("[grabcam] %-9s eye=(%7.3f,%7.3f,%7.3f) moved=%.3f turned=%5.1f body_yaw=%7.1f pitch=%6.1f floor=%6.1f lag=%5.1f"
			% [move_manager.current_name, eye.origin.x, eye.origin.y, eye.origin.z,
			moved, turned, rad_to_deg(rotation.y), rad_to_deg(float(look["pitch"])),
			rad_to_deg(float(look["pitch_floor"])), rad_to_deg(camera_rig.rotation.y)])

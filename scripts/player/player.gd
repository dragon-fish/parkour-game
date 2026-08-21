class_name Player
extends CharacterBody3D

# Owns the shared movement data and the movement primitives. It deliberately
# contains no transition logic — that belongs to the moves.
#
# Move names live on Move, not here: Player references the move classes, so
# the moves must not reference Player back.

var config: MovementConfig
var input_source: InputSource
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

## Emitted on the touchdown that ends an uncontrolled fall. The fall itself is
## already lost by then -- this only tells whoever owns respawning that the
## body has finished arriving.
signal died_from_fall

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

## The heading the body left the ground with, and how long it has been away.
## Turning is not billed in mid-air -- there is no traction to lose it through
## -- but a body that takes off facing one way and lands facing another HAS
## turned, and used to arrive owing nothing. Settled once, on touchdown.
## Time left in the stand-up after a slide.
##
## ⚠️ PROJECT-DEFINED, from play: a slide that ends with the player instantly
## back at full running speed makes sliding free, and the original visibly
## spends a moment getting back up. Two things happen while it runs -- the
## speed budget stops growing, so the ceiling is pinned at whatever the slide
## left it at, and the eye rises from crouch height over the whole window
## rather than snapping up with the capsule.
##
## Re-entering the slide is blocked over the same window, but by
## SlideConfig.redo_move_time through MoveManager's own gate rather than here.
var _slide_recovery_timer: float = 0.0

var _takeoff_dir: Vector3 = Vector3.ZERO
var _airborne_time: float = 0.0

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
## BINARY, not a ramp. ✅ Measured in the original (03 §3.1): a 4.95 m drop
## taken WITHOUT rolling costs nothing at all -- speed keeps climbing after
## touchdown -- while ~7 m unrolled zeroes it outright and plays the knee-clutch
## animation. There is no partial band anywhere in between.
##
## This replaced a modelled ramp that charged a little at 2.5 m and more at
## 4.0 m, with a roll acting as a 35% discount above the soft band. That model
## was plausible and wrong on both counts: below the threshold nothing is
## charged, and above it a roll is not a discount but a full cancellation.
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

## Per-model facing/orientation correction for the mount point, in degrees
## about each local axis (same convention as Node3D.rotation_degrees).
## Defaults to zero: most models are authored already facing -Z, matching
## this project's own forward. A model exported facing the wrong way (or
## lying on its side) can be corrected here rather than by re-exporting the
## asset. Same per-model reasoning as body_mount_offset above -- lives on
## Player, not MovementConfig.
@export var body_mount_rotation_degrees: Vector3 = Vector3.ZERO

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
@export var body_run_reference_speed: float = 7.2

## The instance of body_scene actually attached under BodyRoot, or null if
## none. Exposed as a plain var (not just a BodyRoot child lookup) so tests
## and other systems can inspect what got attached without reaching into
## BodyRoot's children by name.
var body: Node3D = null

## The head- or neck-shaped node found in `body` for the head-follow camera
## to track, or null if there is no body or nothing in it matched. Resolved
## once, in _attach_body(), by _find_head_node() -- see its own comment for
## the search. Read every physics tick by _physics_process() to feed
## CameraRig.set_head_position()/clear_head_position().
var head_node: Node3D = null

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

## ⚠️ DEBUG. Fast enough to cross the arena without waiting, slow enough to
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
## ✅ The owner asked for this after finding that pressing Q as a wall run
## begins does almost nothing -- the press arrives before the run has a fan to
## sweep across, and is simply dropped. Same shape as the jump buffer above, and
## the same reason: the player pressed at the moment that FELT right, and the
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
static func compute_mount_transform(capsule_height: float, mount_offset: Vector3, mount_rotation_degrees: Vector3) -> Transform3D:
	var origin := Vector3(0.0, -capsule_height * 0.5, 0.0) + mount_offset
	var basis := Basis.from_euler(mount_rotation_degrees * (PI / 180.0))
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
	return compute_mount_transform(current_capsule_height(), body_mount_offset, body_mount_rotation_degrees)

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
	shape_node.position.y = -(_standing_height - height) * 0.5

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
	input_source = src
	fall_tracker = FallTracker.new()
	speed_energy = SpeedEnergy.new(config.pawn)

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
	_last_wish_dir = Vector3.ZERO
	_takeoff_dir = Vector3.ZERO
	_airborne_time = 0.0
	_slide_recovery_timer = 0.0
	wall_side = 0
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
	add_child(move_manager)

	# name -> [move instance, its own config]. One table instead of the
	# seven near-identical blocks this used to be, so a new move is one row.
	var table := [
		[Move.WALKING, WalkingMove.new(), config.walking],
		[Move.JUMP, JumpMove.new(), config.jump],
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
	if body_scene != null:
		_attach_body(body_scene)

## Instances `scene` under BodyRoot and wires up everything that depends on
## having a real body: the idle/run/jump AnimationTree (see
## _wire_body_animation()) and the head-follow camera's target node (see
## _find_head_node()). Does nothing -- not even instancing -- if BodyRoot is
## missing or `scene` fails to instance as a Node3D, so a malformed
## body_scene degrades to "no body" rather than crashing startup.
func _attach_body(scene: PackedScene) -> void:
	var body_root := get_node_or_null("BodyRoot") as Node3D
	if body_root == null:
		return
	var instance := scene.instantiate()
	if not (instance is Node3D):
		return
	body = instance as Node3D
	body_root.add_child(body)
	body.transform = body_mount_transform()
	_wire_body_animation(body)
	head_node = _resolve_head_node(body)

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
func _wire_body_animation(body_node: Node3D) -> void:
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
	for looping_clip in [&"idle", &"run", &"sneak", &"sneaking", &"ladder_stillness"]:
		_ensure_clip_loops(anim_player, looping_clip)

	var state_machine := AnimationNodeStateMachine.new()
	for clip_name in _KNOWN_ANIMATION_CLIPS:
		if not _body_has_clip(anim_player, clip_name):
			continue
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = clip_name
		state_machine.add_node(String(clip_name), clip_node)

	# advance_mode = ENABLED, not AUTO -- the same decision, and for the same
	# reason, that used to be documented on this exact block in
	# tools/build_player_scene.gd before it moved here: an unconditioned AUTO
	# transition fires the instant it is evaluated, not when its animation
	# finishes, racing the whole idle->run->End chain to End within a single
	# physics frame regardless of what CharacterAnimator asks for. ENABLED
	# transitions never fire on their own; travel() calls from
	# CharacterAnimator are the only thing that ever moves this graph.
	#
	# Only idle/run get a transition edge at all, same as before this
	# function started conditioning on clip availability -- and, same as
	# before, none of the OTHER nodes (jump included) ever got one either:
	# travel() does not require a transition edge to reach a node directly
	# (verified: jump has never had one, on either side, and has always been
	# reachable), so the newer clips (sneak/sneaking/ladder_stillness) need
	# none for the same reason. Both edges are individually guarded on the
	# node they touch actually existing -- add_transition() to a name that
	# was never add_node()'d is exactly the kind of engine error this whole
	# clip-availability scheme exists to avoid.
	if state_machine.has_node("idle"):
		var start_to_idle := AnimationNodeStateMachineTransition.new()
		start_to_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		state_machine.add_transition("Start", "idle", start_to_idle)
		if state_machine.has_node("run"):
			var idle_to_run := AnimationNodeStateMachineTransition.new()
			idle_to_run.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			state_machine.add_transition("idle", "run", idle_to_run)
	if state_machine.has_node("run"):
		var run_to_end := AnimationNodeStateMachineTransition.new()
		run_to_end.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		state_machine.add_transition("run", "End", run_to_end)

	# WRAPPED IN A BLEND TREE, rather than used as the root directly.
	#
	# A bare AnimationNodeStateMachine at the root has nowhere to put an
	# AnimationNodeTimeScale, which leaves every clip pinned to its authored
	# cadence no matter how fast the body is actually travelling -- the thing
	# that reads as the feet sliding across the ground. The state machine keeps
	# doing exactly what it did; it just sits one level down, so travel() now
	# goes through parameters/<GRAPH_STATES>/playback instead of
	# parameters/playback. CharacterAnimator owns both names.
	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(CharacterAnimator.GRAPH_STATES, state_machine)
	blend_tree.add_node(CharacterAnimator.GRAPH_TIME_SCALE, AnimationNodeTimeScale.new())
	# connect_node(input_node, input_index, output_node) reads backwards: it
	# feeds output_node's OUTPUT into input_node's input port. So these two say
	# "states -> speed -> output". An AnimationNodeOutput named `output` exists
	# in every blend tree by default; it is not added here.
	blend_tree.connect_node(CharacterAnimator.GRAPH_TIME_SCALE, 0, CharacterAnimator.GRAPH_STATES)
	blend_tree.connect_node(&"output", 0, CharacterAnimator.GRAPH_TIME_SCALE)

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

## True when `anim_player` actually carries `clip_name`, in the DEFAULT ("")
## library -- same lookup, and the same "only the default library, ever"
## reasoning, as _ensure_clip_loops() below, so a clip that exists but sits
## in some other, named library reads as absent here too, consistently.
## This is the single source of truth _wire_body_animation() uses to decide
## which nodes the AnimationTree's graph gets at all.
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
func _ensure_clip_loops(anim_player: AnimationPlayer, clip_name: StringName) -> void:
	var original_library := anim_player.get_animation_library("")
	if original_library == null or not original_library.has_animation(clip_name):
		return
	var library := original_library.duplicate(true) as AnimationLibrary
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
	# Before the moves run, so the body moves this tick at whatever size it is
	# now entitled to. A restore owed from an exit under a ceiling comes back
	# on the first tick there is room for it.
	_service_pending_capsule_restore()

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
		camera_rig.set_wall_side(wall_side)
		# Fed as a plain local-space Vector3, not a Node3D reference —
		# CameraRig stays decoupled from the scene-tree/body-search concerns
		# that produced it, matching how every other per-tick input here
		# (speed, grounded, wall_side) is already a value, not an object.
		if head_node != null:
			camera_rig.set_head_position(to_local(head_node.global_position))
		else:
			camera_rig.clear_head_position()
		# travel_speed(), NOT horizontal_speed() — see travel_speed()'s note on
		# why velocity lies through a vault or a mantle.
		camera_rig.update_effects(delta, travel_speed(), grounded)
		_log_grab_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_source is KeyboardInputSource:
		# Only steer the view while the mouse is actually captured. With the
		# cursor released (F1 panel open, or right after Esc) this motion is
		# the human aiming at a slider or a LineEdit, not a look input.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			(input_source as KeyboardInputSource).accumulate_look(event.relative)
	elif event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		# Click back into the game. Esc releases the cursor for the tuning
		# panel; without this the only way back in was F11, which nobody
		# guesses.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_F11:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.physical_keycode == KEY_T:
			toggle_noclip()

## Straight-line flight along the view, position written directly so no
## collision or gravity applies. Deliberately does NOT run the move manager:
## the state stays Walking (see `noclip`), the timers keep ticking above, and
## the fall tracker is re-baselined every frame so that dropping out of noclip
## in mid-air is a fall from HERE rather than from wherever the flight began.
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

func _tick_timers(delta: float, input: MoveInput) -> void:
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
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		return true
	return false

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

## ⚠️ PROJECT-DEFINED. How far the two landing probes may disagree, in EITHER
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
## Source: 02 §2.4 `JumpAddXY = 100` uu/s. ✅ as a value; the CONDITION is
## ✅ measured in the original: a jump taken while running picks up about
## 4 km/h, and a jump from a standstill picks up nothing at all. Adding it
## unconditionally -- which is what the three take-off sites used to do --
## gave a standing jump 1 m/s of drift the original never has.
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

func speed_cap() -> float:
	return speed_energy.cap()

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

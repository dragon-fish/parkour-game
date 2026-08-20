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
var _jump_buffer_timer: float = 0.0
## Buffers a crouch-key press for roll_trigger_time (05 §5.2's confirmed
## TdPawn.RollTriggerTime, extremely forgiving next to the genre's usual
## 0.1-0.2 s). Renamed from _crouch_buffer_timer: GBA_Crouch is one key with
## five outlets and only three discriminators -- airborne/grounded, speed,
## accumulated fall height -- so the buffer itself is not "about crouching",
## it is the single press every one of those outlets reads. See
## walking_move.gd's own table comment for the full resolution.
var _roll_buffer_timer: float = 0.0
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
		[Move.SLIDE, SlideMove.new(), config.slide],
		[Move.CROUCH, CrouchMove.new(), config.crouch],
		[Move.SPEED_VAULT, SpeedVaultMove.new(), config.speed_vault],
		[Move.GRAB, GrabMove.new(), config.grab],
		[Move.WALL_RUN, WallRunMove.new(), config.wall_run],
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
	head_node = _find_head_node(body)

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

	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.tree_root = state_machine
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
		camera_rig.apply_look(input.look, self)

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
			camera_rig.set_crouch_amount(1.0 if crouched else 0.0)
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

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_source is KeyboardInputSource:
		# Only steer the view while the mouse is actually captured. With the
		# cursor released (F1 panel open, or right after Esc) this motion is
		# the human aiming at a slider or a LineEdit, not a look input.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			(input_source as KeyboardInputSource).accumulate_look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_F11:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _tick_timers(delta: float, input: MoveInput) -> void:
	if grounded:
		_coyote_timer = config.pawn.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	_step_grace_timer = maxf(_step_grace_timer - delta, 0.0)
	_was_grounded = grounded

	if input.jump_pressed:
		_jump_buffer_timer = config.pawn.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

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

	# A walkable face is handed to move_and_slide(), which climbs it. Stepping
	# it instead fires this probe every tick of an ascent, each one pushing
	# another offset into the camera -- a long slope reads as a shaking screen.
	#
	# KNOWN IMPRECISE, and left this way deliberately. Measured against the
	# rooftop litter meshes -- flat boards lying on the floor -- this reads
	# 0.890, 0.972, 0.992 as the body closes on one and calls them ramps: the
	# capsule's ROUND BOTTOM reaches the board's TOP FACE before its vertical
	# edge, so the normal describes what the body is about to stand on rather
	# than what is blocking it.
	#
	# Rejecting on the measured RISE instead was tried and reverted: a walkable
	# slope yields up to motion * tan(45 deg) = 0.12 m per tick at running
	# speed, which overlaps the thickness of the very boards this would need to
	# tell apart. The two cases are not separable by size. See
	# docs/feel-backlog.md for what would actually separate them.
	var normal_y: float = blocker.get_normal().y
	if normal_y >= config.pawn.walkable_floor_z:
		return _step_log(what, "是斜坡 n.y=%.3f，交给 move_and_slide" % normal_y, 0.0)

	var max_rise: float = config.pawn.max_step_height
	var up := Vector3.UP * max_rise
	if test_move(global_transform, up):
		return _step_log(what, "头顶无空间", 0.0)

	var lifted := global_transform.translated(up)
	if test_move(lifted, motion):
		return _step_log(what, "太高，是墙不是台阶 (n.y=%.3f)" % normal_y, 0.0)

	# The landing probe reaches at least one capsule radius ahead, NOT just this
	# tick's motion. Blocked by a face, the capsule's centre sits a full radius
	# behind it, so a probe that advances only the tick's motion drops with its
	# centre still outside the obstacle -- the hemisphere catches the top EDGE
	# and reports a fraction of the real step. Measured against a 0.32 m parapet:
	# 0.05 m. The body then rose 0.05, floor snap pulled it back, and it did that
	# every tick, which is the twitching-at-the-corner report.
	#
	# Worse, it is self-reinforcing: being blocked drops the speed, which
	# shortens the probe, which measures even less (at 1 m/s the tick's motion is
	# 1.7 cm). A floor of one radius makes the measurement independent of how
	# fast the player happens to be going when they arrive.
	#
	# This distance measures the surface only -- the body is still merely raised
	# in place, and move_and_slide() carries it forward as usual.
	var reach: float = maxf(motion.length(), current_capsule_radius() + 0.05)
	var advanced := lifted.translated(motion.normalized() * reach)
	var landing := KinematicCollision3D.new()
	if not test_move(advanced, Vector3.DOWN * (max_rise + 0.05), landing):
		return _step_log(what, "对面探空，是坑不是台阶", 0.0)

	# No walkable-normal test on the landing. A capsule dropping next to a step
	# contacts the step's EDGE first, not its top face, and an edge reports an
	# in-between normal (measured 0.36 and 0.57 against a 0.32 m parapet the
	# player could plainly stand on) -- so the test rejected exactly the cases it
	# existed to allow. The rise is still capped at max_step_height, and
	# move_and_slide() applies Godot's own floor_max_angle immediately after, so
	# a genuinely unstandable surface is caught there instead. All this probe
	# needs to know is that the space below is not empty.
	var rise: float = max_rise - landing.get_travel().length()
	if rise <= 0.01:
		return _step_log(what, "落差过小 %.3f m" % rise, 0.0)
	global_position.y += rise
	# Opens the window described on _step_grace_timer. Armed here rather than
	# by each caller so no move can forget it, and so the two ticks the
	# manoeuvre actually takes are covered rather than only the first.
	_step_grace_timer = config.pawn.step_up_grace_time
	return _step_log(what, "抬升 %.3f m" % rise, rise)


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
func try_step_down() -> void:
	if true: return  # TEMP
	if config == null or is_on_floor():
		return
	# Airborne when the tick STARTED means falling or jumping, not thrown by
	# geometry -- leave it alone, or a fall gets caught by every ledge it
	# passes within a step of.
	if not _was_grounded:
		return
	# Rising is a jump, and a jump must not be pulled back to the floor it just
	# left.
	if velocity.y > 0.0:
		return
	var landing := KinematicCollision3D.new()
	if not test_move(global_transform, Vector3.DOWN * config.pawn.max_step_height, landing):
		return                            # nothing within a step below: a real fall
	global_position += landing.get_travel()
	apply_floor_snap()

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

const STEP_DECISION_LINES := 10


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
	if not grounded:
		# Neither banked, bled, nor charged for turning while airborne.
		_last_wish_dir = wish
		return
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
	var reachable: float = speed_cap() * move_manager.current_move_speed_modifier()
	if horizontal_speed() >= reachable * config.pawn.energy_accumulate_speed_ratio:
		speed_energy.accumulate(delta, _energy_mode(input))
	else:
		# Asking to move but not actually getting anywhere -- shoved into
		# geometry, or still climbing toward a ceiling already paid for.
		# Neither banks anything; neither is a reason to bleed, either.
		pass

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

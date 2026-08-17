class_name Player
extends CharacterBody3D

# Owns the shared movement data and the movement primitives. It deliberately
# contains no transition logic — that belongs to the states.
#
# State names live on PlayerState, not here: Player references the state
# classes, so the states must not reference Player back.

var config: MovementConfig
var input_source: InputSource
var state_machine: StateMachine

## Downward speed at the moment of the most recent landing. Read by CameraRig.
var last_landing_speed: float = 0.0
## True when the most recent landing was a roll. Read by the camera and HUD.
var last_landing_rolled: bool = false
## Last polled input, exposed for the debug HUD.
var last_input: MoveInput = MoveInput.new()

## Whether the player is standing on something. DECLARED by the active state
## rather than read from is_on_floor(), because scripted-move states drive the
## body's position directly and never call move_and_slide() — is_on_floor()
## would report whatever was true before the move began.
var grounded: bool = false

## World-space Y the player was last known to be resting on solid ground,
## refreshed every tick set_grounded(true) is declared (so it tracks a sloped
## or stepped floor, not just the very first tick of a Ground stint). Read by
## WallRunState to bound how much height a chain of wall-jumps can add above
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

## Number of set_grounded() calls made so far, ever. Read ONLY by StateMachine,
## which snapshots it when a state is entered and checks it has moved by the end
## of that state's first physics_update — that is how "a state DECLARES its
## grounded-ness" is enforced structurally instead of by convention. The
## absolute value is meaningless; only differences between snapshots are.
var grounded_declarations: int = 0

func set_grounded(value: bool) -> void:
	grounded = value
	grounded_declarations += 1
	if value:
		ground_reference_y = global_position.y

## Clears `grounded` WITHOUT counting as a declaration. Called only by
## StateMachine, as the fail-safe half of the invariant above: a state that
## never declared must not go on inheriting the previous state's value — a
## WallRun that forgot the call would inherit Ground's `true` and refill coyote
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

## Assigned in player.tscn. Optional so headless tests can run without one.
@export var camera_rig: CameraRig

## Assigned in player.tscn. Optional so hand-built test players still work.
@export var probes: Probes

## The visible character body to attach under BodyRoot at runtime, or null
## for none. Deliberately NOT wired by tools/build_player_scene.gd -- see
## BodyRoot's own comment there: a committed player.tscn can never reference
## a specific model, licensed or otherwise, so this is left for a LOCAL,
## untracked override to set (e.g. an inherited scene of player.tscn that
## points body_scene at an owner's own model) rather than for generator
## output to carry. Instanced once, in _ready(), by _attach_body(). A body
## is entirely optional: everything downstream (CharacterAnimator, the
## head-follow camera) is built to no-op cleanly with none attached, not
## merely "usually work" -- see tests/test_body_attachment.gd.
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
var _jump_buffer_timer: float = 0.0
var _crouch_buffer_timer: float = 0.0
## Counts down after releasing a ledge; while positive, can_grab_ledge()
## refuses a re-grab. Without this, dropping off a ledge (e.g. via crouch)
## would immediately re-grab the very same ledge on the next tick.
var _ledge_cooldown: float = 0.0
## True when a state has asked for the standing capsule back but a ceiling was
## in the way. See request_standing_capsule().
var _standing_restore_pending: bool = false

## Recently-left walls still cooling down, each {"normal": Vector3,
## "cooldown": float}. A SET, not a single slot: a single {normal, cooldown}
## pair was found to be bypassable in any corner -- leave wall A, touch
## perpendicular wall B for even one tick, and note_wall_detach(B) would
## overwrite A's entry wholesale, making A immediately re-attachable and
## letting the player climb the corner forever. A bounded array lets several
## walls cool down independently. Capped at MAX_RECENT_WALLS (oldest evicted
## first) since this is walked on every airborne tick; in practice expired
## entries are pruned in _tick_timers() well before the cap would ever bind.
var _recent_walls: Array = []
const MAX_RECENT_WALLS := 4
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
## correction is still needed on top of that automatic placement. Shared by
## _attach_body() (the real runtime attach) and BodyRoot's editor-only
## preview (see body_root.gd), so what the owner eyeballs in the editor is
## exactly what shows up at runtime.
func body_mount_transform() -> Transform3D:
	var origin := Vector3(0.0, -current_capsule_height() * 0.5, 0.0) + body_mount_offset
	var basis := Basis.from_euler(body_mount_rotation_degrees * (PI / 180.0))
	return Transform3D(basis, origin)

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

func _service_pending_capsule_restore() -> void:
	if _standing_restore_pending and has_headroom():
		set_capsule_height(_standing_height)

func setup(cfg: MovementConfig, src: InputSource) -> void:
	config = cfg
	input_source = src

	# The capsule resource is shared by every instance of player.tscn, so
	# resizing it in place would let one player's slide shrink every other
	# player in the scene — including, in tests, worlds from previous cases.
	var shape_node := $CollisionShape3D as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule != null:
		var owned := capsule.duplicate() as CapsuleShape3D
		shape_node.shape = owned
		_standing_height = owned.height

	_build_state_machine()

	if probes != null:
		probes.setup(config, _standing_height * 0.5)

## Clears per-life transient state that outlives a single frame: the coyote,
## jump-buffer, and ledge-regrab-cooldown timers, and the last landing speed
## CameraRig reads for its dip. Called on a manual reset (Arena's R key) so a
## leftover buffered jump from just before the reset cannot fire the instant
## the player respawns grounded, so a landing dip from the old life cannot
## appear after a fresh spawn, and so a ledge cooldown from the old life
## cannot withhold a grab the new one should be free to make. Does not touch
## the state machine itself — callers restart that separately.
##
## grounded is also cleared here rather than left to whatever the previous
## life last declared: Arena.reset_player() teleports to spawn and then skips
## exactly one physics tick before the state machine resumes (see its own
## comment), and _tick_timers() runs on the very first re-enabled tick —
## before GroundState has had a chance to declare anything. Without this, that
## one tick reads last life's grounded value and can wrongly refill coyote
## time (if the old life ended airborne, a resting spawn would start with
## none) or wrongly withhold it (the reverse).
func reset_state() -> void:
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_crouch_buffer_timer = 0.0
	_ledge_cooldown = 0.0
	# Same reasoning as the ledge cooldown above: wall cooldowns left over
	# from the previous life must not withhold a fresh life's first attach.
	_recent_walls.clear()
	wall_side = 0
	# A respawn teleport is not travel: leave the camera's speed cue at rest
	# rather than letting the first tick after the reset read the old life's.
	_travel_speed = 0.0
	last_landing_speed = 0.0
	grounded = false
	# Set directly rather than through set_grounded(true) (which would also
	# flip `grounded` back on, contradicting the line above): global_position
	# has already been moved to the spawn point by the time Arena.reset_player()
	# calls this (see its own comment on ordering), so this is the correct
	# fresh reference immediately, without waiting for GroundState's first
	# declaration a tick or two after the reset.
	ground_reference_y = global_position.y
	_pending_landing = -1.0
	# A reset teleports the player to a known-clear spawn, so a restore owed
	# from a slide under some ceiling is both stale and satisfiable right now.
	# request_standing_capsule() clears the flag on the way through, and
	# re-arms it in the impossible case that the spawn is itself blocked.
	_standing_restore_pending = false
	request_standing_capsule()

func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	add_child(state_machine)

	var ground := GroundState.new()
	var air := AirState.new()
	for s in [ground, air]:
		s.player = self
		s.config = config
		state_machine.add_child(s)

	state_machine.register(PlayerState.GROUND, ground)
	state_machine.register(PlayerState.AIR, air)

	var slide := SlideState.new()
	slide.player = self
	slide.config = config
	state_machine.add_child(slide)
	state_machine.register(PlayerState.SLIDE, slide)

	var crouch := CrouchState.new()
	crouch.player = self
	crouch.config = config
	state_machine.add_child(crouch)
	state_machine.register(PlayerState.CROUCH, crouch)

	var vault := VaultState.new()
	vault.player = self
	vault.config = config
	state_machine.add_child(vault)
	state_machine.register(PlayerState.VAULT, vault)

	var ledge := LedgeHangState.new()
	ledge.player = self
	ledge.config = config
	state_machine.add_child(ledge)
	state_machine.register(PlayerState.LEDGE, ledge)

	var wall := WallRunState.new()
	wall.player = self
	wall.config = config
	state_machine.add_child(wall)
	state_machine.register(PlayerState.WALL, wall)

	state_machine.start(PlayerState.GROUND)

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
	if state_machine == null:
		return
	# Sampled at the START of the tick, not carried over from the end of the
	# previous one, so a teleport made from outside this function (the arena's
	# respawn, a test placing the body) is never measured as travel.
	var tick_start_position := global_position
	var input := input_source.poll()
	last_input = input
	_tick_timers(delta, input)
	# Before the states run, so the body moves this tick at whatever size it is
	# now entitled to. A restore owed from an exit under a ceiling comes back
	# on the first tick there is room for it.
	_service_pending_capsule_restore()

	if camera_rig != null:
		camera_rig.apply_look(input.look, self)

	state_machine.physics_update(delta, input)

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
		_coyote_timer = config.coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if input.jump_pressed:
		_jump_buffer_timer = config.jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Deliberately keyed on crouch_PRESSED, not crouch_held: this buffer stores
	# presses, so holding the key down refills it exactly once. A held-state
	# version would re-arm every tick and let a slide re-enter the instant the
	# previous one ended, which is the strobing this gate exists to prevent.
	if input.crouch_pressed:
		_crouch_buffer_timer = config.crouch_buffer_time
	else:
		_crouch_buffer_timer = maxf(_crouch_buffer_timer - delta, 0.0)

	_ledge_cooldown = maxf(_ledge_cooldown - delta, 0.0)

	# Walked backwards so remove_at() during the loop cannot skip an entry.
	# Pruning expired entries here (rather than only checking their cooldown
	# inside can_attach_wall()) is what keeps _recent_walls small in the
	# common case: it rarely holds more than the one or two walls actually
	# touched in the last wall_reattach_cooldown seconds, so MAX_RECENT_WALLS
	# below only matters as a backstop against an adversarial burst of
	# touches.
	for i in range(_recent_walls.size() - 1, -1, -1):
		var entry: Dictionary = _recent_walls[i]
		entry["cooldown"] -= delta
		if entry["cooldown"] <= 0.0:
			_recent_walls.remove_at(i)

## Spends a buffered jump if one is pending and the player is still within
## coyote time. Returns true at most once per press.
func consume_jump() -> bool:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return true
	return false

## Spends a buffered jump if one is pending, WITHOUT requiring coyote time.
## For states that are legitimately, truthfully airborne the whole time they
## run -- a wall run declares grounded=false every tick (see WallRunState),
## so the coyote timer consume_jump() requires never refills there, and
## consume_jump() would be permanently dead on the wall. But a press is not
## only relevant on the exact tick a state starts reading it: AirState hands
## off to WallRunState the moment it detects a wall, before WallRunState's
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

## Spends a buffered crouch press if one is pending. Returns true at most once
## per press — this is what keeps the roll-into-slide chain reachable without
## reopening the held-key strobe.
func consume_crouch() -> bool:
	if _crouch_buffer_timer > 0.0:
		_crouch_buffer_timer = 0.0
		return true
	return false

## Called by LedgeHangState when the player drops off a ledge (crouch), so
## can_grab_ledge() refuses to re-grab the very same ledge on the next tick.
func start_ledge_cooldown() -> void:
	_ledge_cooldown = config.ledge_regrab_cooldown

## True once the post-release cooldown started by start_ledge_cooldown() has
## expired. AirState gates its ledge-grab check on this.
func can_grab_ledge() -> bool:
	return _ledge_cooldown <= 0.0

## Called by WallRunState when it exits, so a wall facing roughly the same way
## as the one just left cannot be re-attached until its own cooldown runs out.
## Appends rather than overwrites: a single {normal, cooldown} slot was found
## to be bypassable in any corner -- leaving wall A, briefly touching
## perpendicular wall B, and then rekeying to B on exit would erase A's still-
## running cooldown outright, making A immediately re-attachable one tick
## later. Each wall gets its own independent entry instead.
func note_wall_detach(normal: Vector3) -> void:
	if _recent_walls.size() >= MAX_RECENT_WALLS:
		_recent_walls.pop_front()
	_recent_walls.append({"normal": normal, "cooldown": config.wall_reattach_cooldown})

## False while ANY recently-left wall is both still cooling down AND faces
## roughly the same way as the candidate. A genuinely different wall is always
## allowed, which is what makes zig-zag wall chaining work while blocking
## same-face climbing -- in a corner, checking every remembered wall (not just
## the most recent) is what stops a brief touch on a perpendicular wall from
## clearing the cooldown on the one actually being exploited.
func can_attach_wall(normal: Vector3) -> bool:
	for entry in _recent_walls:
		if normal.dot(entry["normal"]) >= config.wall_same_normal_dot:
			return false
	return true

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
## This exists because `velocity` lies during a scripted move: VaultState and
## LedgeHangState drive global_position directly and deliberately zero velocity
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

## Ground movement: converge on the target velocity, and brake when idle.
func ground_accelerate(wish_dir: Vector3, target_speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir == Vector3.ZERO:
		horizontal = horizontal.move_toward(Vector3.ZERO, config.ground_friction * delta)
	else:
		horizontal = horizontal.move_toward(wish_dir * target_speed, config.ground_accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

## Air movement: only ever adds speed along wish_dir, and only up to a
## ceiling measured along that direction. It never brakes, so momentum
## carried in from another state survives — P1's slide depends on this.
##
## The ceiling is NOT a flat air_max_speed: it is
## min(air_max_speed, max(ground_speed, speed_along_wish)). air_max_speed
## itself (see its own comment in movement_config.gd -- ME's AirSpeed,
## essentially uncapped) is deliberately too high to ever bind in practice;
## it exists so momentum carried in from elsewhere (a wall-run or slide boost
## exceeding ground_speed) is never reduced by air control, matching this
## function's own "never brakes" rule. ground_speed is the floor UNDER that:
## with air_accel now tiny (see its own comment), a long fall or a chain of
## jumps has plenty of TIME to slowly climb toward air_max_speed even without
## any exploit-like input, which would let mere airtime manufacture speed no
## ground state could reach on its own -- exactly the invariant
## tests/test_landing.gd's test_a_landing_can_never_add_speed_however_the_
## keep_ratio_is_tuned and tests/test_slide_state.gd's
## test_chained_slide_then_jump_cannot_stack_the_entry_boost both pin. Taking
## the max with the CURRENT speed_along_wish (not a flat ground_speed cap) is
## what keeps the "never reduces carried-in momentum" half of the contract
## intact: a player already faster than ground_speed gets zero headroom here
## (the ceiling sits at their own current speed), never a forced slowdown.
func air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed_along_wish := horizontal.dot(wish_dir)
	var ceiling := minf(config.air_max_speed, maxf(config.ground_speed, speed_along_wish))
	var headroom := ceiling - speed_along_wish
	if headroom <= 0.0:
		return
	var candidate := horizontal + wish_dir * minf(config.air_accel * delta, headroom)
	# INVARIANT: air control must never brake — only redirect/add speed.
	# The Quake-style projection above adds speed along wish_dir, but when
	# wish_dir opposes the existing velocity that addition can still shrink
	# the resultant horizontal SPEED even though it grows along wish_dir
	# (e.g. horizontal (0,0,-5), wish_dir (0,0,1): adding a small amount
	# along +z takes the resultant length from 5.0 down to 4.8). This guard
	# is what actually enforces the invariant: only commit the candidate
	# when it does not shrink horizontal speed, otherwise leave velocity
	# untouched for this tick. Do not remove this check as a "simplification"
	# — without it, holding the opposite key can brake a jump or erase a
	# slide boost carried into the air.
	if candidate.length() < horizontal.length():
		return
	velocity.x = candidate.x
	velocity.z = candidate.z

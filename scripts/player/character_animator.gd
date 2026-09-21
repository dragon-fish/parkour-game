class_name CharacterAnimator
extends Node

# Small REFERENCE driver: reads the player's movement state every physics
# tick and puts the matching clip on screen. See the per-move comments in
# _target_animation() below for what maps to what, and _first_available()'s own
# comment for why every one of those mappings is really a PRIORITY LIST, not a
# single name.
#
# TWO WAYS OF PUTTING A CLIP ON SCREEN, and _route() owns the choice: an
# ordinary clip travel()s through the AnimationTree's state machine, while a
# clip a SCRIPTED MOVE plays goes onto one of two bare slots that sit alongside
# that machine behind an AnimationNodeTransition. _route()'s own comment
# explains why.
#
# WHY a priority list rather than one fixed name per move: the AnimationTree
# this class drives is built at runtime by player.gd's _wire_body_animation(),
# from whatever clips the ATTACHED body's AnimationPlayer actually has (see
# its own comment) -- and body_scene is optional and per-model, so nothing
# here may assume any particular clip, including idle/run/jump, exists.
# travel()ing to a name with no matching node in the graph is not a graceful
# no-op, it is a real engine error (verified directly -- see _has_clip()'s
# comment), which the test gate treats as a hard failure. _first_available()
# is what keeps every case below safe against that: it walks each move's
# candidates in priority order and returns the first one the attached body
# actually has, falling all the way through to Move.KEEP -- "do
# nothing this tick" -- if the body has none of them at all.
#
# WHY travel() has to be called every tick rather than once on a move
# change: player.gd's _wire_body_animation() wires the state machine's
# Start/idle/run/End transitions with advance_mode = ENABLED, not AUTO. That
# is a deliberate fix, not a preserved default -- see that function's own
# comment for why AUTO cannot hold a state at all here. With ENABLED, nothing
# about the graph ever moves on its own, so re-issuing travel() every tick is
# what keeps the animation following the player instead of freezing at
# whatever it last was.

## Names of the nodes inside the AnimationTree's blend-tree root, which
## player.gd's _wire_body_animation() builds. Constants rather than literals on
## both sides because the parameter paths this class pokes every tick are
## STRINGS ("parameters/<name>/..."): renaming one side and not the other
## produces no error whatsoever, just a body that silently stops animating.
const GRAPH_STATES := &"states"
const GRAPH_GATE := &"gate"
const GRAPH_SCRIPTED_A := &"scripted_a"
const GRAPH_SCRIPTED_B := &"scripted_b"
const GRAPH_TIME_SCALE := &"speed"

## The arm overlay: a filtered Blend2 sitting BETWEEN the gate and the time
## scale, so it can put one clip's arms on top of whatever the gate is playing
## without the routing knowing anything about it. Adding a gate input instead
## would have meant teaching _route() a fourth path, and that function's
## comments are a list of measured pitfalls -- the sandwich, the promotion, the
## hold -- none of which this needs to disturb.
const GRAPH_ARM_OVERLAY := &"arm_overlay"
const GRAPH_ARM_OVERLAY_CLIP := &"arm_overlay_clip"
## Between the overlay's clip and the blend, so the arms can be SCRUBBED to the
## climb's own progress instead of running a loop of their own.
const GRAPH_ARM_OVERLAY_SEEK := &"arm_overlay_seek"

## The two bare AnimationNodeAnimation slots the scripted clips play on, in
## ping-pong order. See _route().
const GRAPH_SCRIPTED_SLOTS: Array[StringName] = [GRAPH_SCRIPTED_A, GRAPH_SCRIPTED_B]

## The gate's inputs, IN INDEX ORDER. One list, so the index the blend tree
## connects a node to and the name transition_request has to be given can never
## disagree -- AnimationNodeTransition addresses its inputs by index when it is
## wired and by name when it is switched.
const GRAPH_GATE_INPUTS: Array[StringName] = [GRAPH_STATES, GRAPH_SCRIPTED_A, GRAPH_SCRIPTED_B]

## The clips whose playback rate follows how fast the body is actually
## travelling. Locomotion only, by definition: these are the clips whose feet
## are on the ground and are supposed to be carrying it, so a mismatch between
## their authored cadence and the real speed is what reads as the feet sliding.
##
## idle and jump are deliberately absent. Slowing an idle down because the body
## is standing still is exactly backwards, and a jump's timing belongs to the
## arc, not to the ground.
const SPEED_MATCHED_CLIPS: Array[StringName] = [
	&"run", &"sneak",
	# The merged packs' own names. Omitting them is why the owner reported the
	# run "not using the current speed as a multiplier" -- the routing had moved
	# on from `run` while this list still only knew about `run`, so the scaling
	# silently stopped applying to the clip actually playing. A list of names
	# that has to be kept in step with another list of names, and it was not.
	&"Walk", &"Sprint", &"Walk_Carry", &"Crouch_Fwd",
]

## Bounds on that scaling. Outside them the cadence stops reading as a pace and
## starts reading as a defect -- slow-motion at the bottom, blurred limbs at the
## top. A body slower than the lower bound has already crossed
## run_animation_speed_threshold into idle anyway.
## The clips played while CROUCHED, which travel against a lower ceiling and so
## need a lower reference to scale against.
##
## The owner: a crouch tops out at 2.88 m/s, so measuring its cadence against
## the standing 7.2 pins the scale to the floor and the crouch-walk plays in
## permanent slow motion. 2.88 is not a new constant -- it is
## pawn.ground_speed times pawn.crouched_pct, which is where _drive_speed()
## takes it from, so neither number can drift away from the other.
const CROUCHED_CLIPS: Array[StringName] = [
	&"sneak", &"sneaking", &"Crouch_Idle", &"Crouch_Fwd",
]

const SPEED_SCALE_MIN := 0.5
const SPEED_SCALE_MAX := 2.0

## Bounds on fitting a clip to a scripted move's clock. Wider than the
## locomotion bounds above, because this is not a cadence being nudged to match
## a pace -- it is a fixed action being made to fit a window the move chose, and
## the windows genuinely differ by more than a factor of two: ClimbUp_2m is
## 1.3 s and a mantle is not.
const SCRIPTED_FIT_MIN := 0.25
const SCRIPTED_FIT_MAX := 4.0

## The WALK clips, which are authored at a stroll and cannot be scaled up to a
## run -- the same shape as CROUCHED_CLIPS below, and for the same reason.
const WALK_CLIPS: Array[StringName] = [&"Walk", &"Walk_Carry"]

## What a walk clip's 1.0 means, as a fraction of body_run_reference_speed.
##
## DERIVED, not picked. The two scale bounds above already define how far any
## clip can be stretched, so the walk's reference is set so that its CEILING
## lands exactly on the run's FLOOR:
##
##   walk at SPEED_SCALE_MAX = 7.2 * 0.25 * 2.0 = 3.6 m/s
##   run  at SPEED_SCALE_MIN = 7.2 * 0.5       = 3.6 m/s
##
## which is also where _run_band_speed() hands one clip over to the other. At
## the seam both clips are at the exact edge of their usable range, so neither
## is ever asked to do the other's job. 0.25 of 7.2 is 1.8 m/s, a brisk walk
## and a plausible authored speed for the pack's Walk_Loop.
##
## THE ONE KNOB HERE. If the walk looks like it is hurrying or dawdling,
## this is the number -- and moving it moves the handover with it, which is
## the point.
const WALK_REFERENCE_PCT := 0.25

## What a JOG clip's 1.0 means, as a fraction of body_run_reference_speed.
##
## Derived the same way the walk's is, and set at the bottom of the run band
## so the walk hands over to it at 1.0 (see _run_band_speed()).
##
## The jog only ever plays OUTSIDE THE FORWARD ARC here (see Move.WALKING), and
## that is also where PawnConfig's arc limit drops the ground ceiling to
## speed_max_base_velocity, 4.0 m/s. So the range it actually covers is 3.6 to
## 4.0 -- 1.0 to 1.11 -- and it comes nowhere near SPEED_SCALE_MAX.
##
## DO NOT raise this to stop a jog running away with itself. A jog pinned at
## SPEED_SCALE_MAX means the clip is being played at a speed the arc says it
## can never reach, so the ROUTING has sent an in-arc diagonal to the jog and
## this number is not the fault.
##
## DO NOT measure the jog against the same 7.2 reference the run uses either: a
## jog covering 7.2 m/s would then play at 1.0, and the stride has to be
## enormous to cover that much ground at a jogging cadence.
const JOG_REFERENCE_PCT := 0.5

## The packs' EIGHT-WAY sets, as suffixes clockwise from straight ahead.
##
## THE TWO PACKS DO NOT AGREE ON THE SIDE NAMES. UAL1 spells them Left and
## Right (Jog_Left, Crouch_Right); UAL2 spells them L and R (Walk_L, Walk_R).
## Nothing derives one from the other -- each family carries its own table, and
## a family added later has to be read off the gallery rather than guessed.
##
## There is NO eight-way Sprint in either pack, which is why Move.WALKING sends
## travel from OUTSIDE the forward arc to the jog and keeps the sprint for
## everything inside it, the diagonals included.
const DIRECTION_SETS := {
	&"Jog": ["_Fwd", "_Fwd_R", "_Right", "_Bwd_R", "_Bwd", "_Bwd_L", "_Left", "_Fwd_L"],
	&"Walk": ["_Fwd", "_Fwd_R", "_R", "_Bwd_R", "_Bwd", "_Bwd_L", "_L", "_Fwd_L"],
	&"Crouch": ["_Fwd", "_Fwd_R", "_Right", "_Bwd_R", "_Bwd", "_Bwd_L", "_Left", "_Fwd_L"],
}

## Assigned in player.gd's _wire_body_animation().
@export var anim_tree: AnimationTree
## Assigned in player.gd's _wire_body_animation().
@export var player: Player

var _playback: AnimationNodeStateMachinePlayback
## The graph itself, cached alongside _playback so _has_clip() below never
## has to re-fetch anim_tree.tree_root every tick for every candidate.
var _graph: AnimationNodeStateMachine
## The blend tree the state machine and the two scripted slots sit in.
var _blend_tree: AnimationNodeBlendTree

## Which of the gate's inputs this class last ASKED for, by name.
##
## Tracked here rather than read back off parameters/<gate>/current_state,
## which only catches up once the tree has processed the request -- a tick
## later. Re-issuing a request the gate has not acted on yet would be a second
## entry into the same input, and the slots reset on entry.
var _gate_input: StringName = &""
## The scripted slot most recently claimed, as an index into
## GRAPH_SCRIPTED_SLOTS, or -1 before the first one. The ping-pong.
var _slot: int = -1
## Seconds an ordinary clip must still keep asking before the gate is allowed to
## leave a scripted slot. See _route()'s hysteresis note -- this is what stops a
## scripted -> ordinary -> scripted sandwich from popping.
var _hold_left: float = 0.0
## The ordinary clip hard-cut into the HIDDEN state machine during a hold,
## so the hand-back lands on a clip already in motion. See _route().
var _hidden_start: StringName = &""

## The move the previous tick was in, so a CHANGE of move can be noticed. Every
## routing decision above this line is stateless -- it asks what the body is
## doing now -- and the one-shots below are the exception that needs to know
## what it stopped doing.
var _previous_move: StringName = Move.KEEP
## The one-shot currently playing, or KEEP. See _arm_oneshot().
var _oneshot: StringName = Move.KEEP

## Set by a routing case that wants the scripted clip already on the body
## started again from its first frame; _route() spends it. The step round is
## the case: one Turn90 after another, all with the same name.
var _replay: bool = false
var _turn_serial_seen: int = 0
## Seconds of it left to play. Real seconds, and that is only true because a
## one-shot is never in SPEED_MATCHED_CLIPS: the graph time scale is pinned to
## 1.0 while one plays, so the clock here and the clip agree.
var _oneshot_left: float = 0.0

## The clip travel()ed to on the most recent tick, or KEEP if none was. Read by
## Player._drive_clip_offset() and by the debug tuner: a per-clip offset needs
## to know which clip, and the answer already exists here rather than being
## worth recomputing.
var current_clip: StringName = Move.KEEP

func _ready() -> void:
	if anim_tree == null:
		return
	# The state machine sits one level inside a blend tree so the whole graph
	# can be time-scaled. See player.gd's _wire_body_animation() for why, and
	# _drive_speed() below for what drives it.
	_playback = anim_tree.get("parameters/%s/playback" % GRAPH_STATES)
	_blend_tree = anim_tree.tree_root as AnimationNodeBlendTree
	if _blend_tree != null:
		_graph = _blend_tree.get_node(GRAPH_STATES) as AnimationNodeStateMachine

func _physics_process(delta: float) -> void:
	if player == null or player.move_manager == null or _playback == null:
		return
	var move: StringName = player.move_manager.current_name
	if move != _previous_move:
		_arm_oneshot(_previous_move, move)
		_previous_move = move
	# A one-shot OUTRANKS the move's own clip while it lasts -- that is the
	# whole point of it. _oneshot_target() returns KEEP the moment there is
	# none, which is almost every tick.
	var target := _oneshot_target(delta)
	if target == Move.KEEP:
		target = _target_animation()
	# Move.KEEP (the same empty-StringName sentinel Move itself
	# uses for "stay put, nothing to do") means every candidate for this tick's
	# move came back missing from the attached body -- see _first_available().
	# There is nothing safe to travel() to, so skip the call entirely rather
	# than ask the graph for a name it does not have.
	if target == Move.KEEP:
		return
	current_clip = target
	_route(target, delta)
	_drive_speed(target)

## Re-baselines the router after an external direct-animation cutscene. No
## transition happened from the player's point of view, so none may arm a
## landing/slide/dodge one-shot when the AnimationTree wakes up again.
func synchronize_to_current_move() -> void:
	if player == null or player.move_manager == null:
		return
	_previous_move = player.move_manager.current_name
	_oneshot = Move.KEEP
	_oneshot_left = 0.0
	_hold_left = 0.0
	_hidden_start = &""
	_replay = false
	var target := _target_animation()
	if target == Move.KEEP:
		current_clip = Move.KEEP
		return
	current_clip = target
	_route(target, 0.0)
	_drive_speed(target)

## Puts `target` on screen: a scripted move's clip onto one of the gate's own
## slots, anything else through the state machine as before.
##
## FIRST, WITH travel(): a scripted phase chained right after a very short
## move can lose almost all of its frames to a state machine that is still
## finishing the PREVIOUS transition. travel() is a REQUEST: the state
## machine finishes the transition it is in before honouring it. Measured on
## a 2 m obstacle, frames from one recording:
##
##     78   move=Jump       wants Jump_Start    graph on Sprint
##     79   move=IntoGrab   wants Climb_Enter   graph on Jump_Start, fading
##     85   move=Grab       wants Climb_Idle    graph on Jump_Start, fading
##     86   move=Grab       wants ClimbUp_2m    graph on Jump_Start, fading
##     89   move=Grab       wants ClimbUp_2m    graph on ClimbUp_2m
##
## Jump was the current move for ONE tick and held the graph for ELEVEN -- a
## whole body_animation_blend_time -- while the body played a jump start through
## the reach and the grab. Climb_Enter never played at all. THE DELAYS DO NOT
## STACK: the graph paid one blend and then went straight to whatever was
## current, skipping the clips requested in between, so the cost is one blend per
## chain and it hurts in proportion to how SHORT the move is. The vault lost 10
## of its 27 frames; the pull-up lost 3 of 78.
##
## The same mechanism shows up on a 1 m StepUp vault: the move asks for StepUp
## on frame 79, but travel() does not put it on screen until frame 89 -- 10 of
## the move's 29 frames lost to a Jump_Start still blending in, for a Jump
## state that had been the current move for exactly one tick. (The two
## obstacles lose a different frame count, 10 of 27 vs 10 of 29, because they
## are different obstacles and the fit stretches the clip differently -- the
## frame count is not a constant, only the mechanism is.)
##
## THEN, WITH start(target, true): arriving at once, by discarding the whole
## cross-fade -- including the fade OUT of the clip before it, which was doing
## real work, so the cut between the two clips reads as unconnected.
##
## AnimationNodeStateMachinePlayback IN 4.7 HAS NO THIRD OPTION. Verified
## against the engine's own ClassDB: travel(), start(), stop(), and nothing that
## interrupts a fade while keeping one. godotengine/godot#66495 is the standing
## request for it. So the scripted clips are not in the state machine any more.
## AnimationNodeTransition is: it switches inputs at any moment WITH its xfade,
## and interrupts a fade of its own gracefully.
##
## TWO SLOTS, PING-PONGED. An input cannot fade into itself, so a mantle chain
## on one slot would be a cut between its clips. Alternating means the second
## scripted clip fades out of the first exactly as it would out of a run.
##
## THE STATE MACHINE IS LEFT ALONE while a slot is on screen. It may still be
## settling from before the scripted move started; that is fine, because the
## gate's own fade is what covers the seam and the machine is at zero weight
## while it does.
##
## AND THE ONE RULE THE OLD preempts() ENCODED SURVIVES, AS HYSTERESIS: a
## scripted clip may cut in front of an ordinary one; an ordinary one may
## never cut in front of a scripted one. The gate needs this for a reason of
## its own, below.
##
## THE SANDWICH POPS. AnimationNodeTransition tracks ONE level of `prev`, so
## requesting "states" and then a slot inside a single blend window makes it
## promote the half-faded "states" to full weight and DROP the outgoing slot in
## one tick. Reproduced on a skeleton: a marker driven by the slot's own clip
## went 1.5556 -> 0.0000 between two consecutive physics frames. The ping-pong
## does not help, because it is "states" that gets sandwiched in, not a slot.
##
## So an ordinary target does NOT take the gate back immediately. It has to keep
## asking for a whole body_animation_blend_time first -- unless the gate has
## already settled, in which case there is no half-faded input to promote and the
## hand-back is free, which is the ordinary end of every scripted move. A
## scripted target arriving during the hold goes straight to the other slot: two
## real inputs, a genuine fade, no promotion.
##
## THE COST IS A SLOT HOLDING ITS LAST FRAME for up to body_gate_hold_time past
## the end of its move -- a dial, 0.05 s by default, sized to the 1-3 tick
## transients: much longer and the held pose reads as a freeze on its last
## frame, not a hold.
##
## THE MACHINE DOES NOT ADVANCE UNDER THE HOLD -- measured, not assumed: an
## input the gate is not showing is not processed, so get_current_node() sat on
## its old node for every tick of the hold and moved on the FIRST tick after the
## hand-back. So travel() is still issued every held tick (the request is latched
## and honoured the moment the input goes live again), but what the machine does
## meanwhile is hold its last pose -- which is the right thing to fade back into
## anyway.
## How much of the arm overlay is showing, 0..1, eased so it cannot pop.
##
## ONLY A LOW CLIMB ASKS FOR IT. A pull-up into a duct plays a crouch for the
## body -- see the clip choice for why -- and this puts the climb's arms back
## on top of it, so the hands still reach for the lip while the body stays
## folded. Everything else runs at zero and pays a lerp per tick.
func _drive_arm_overlay(delta: float) -> void:
	if anim_tree == null or player == null or player.move_manager == null:
		return
	var grab = player.move_manager.move_for(Move.GRAB)
	var wanted: float = 1.0 if grab != null and grab.is_climbing_low() else 0.0
	var path := "parameters/%s/blend_amount" % GRAPH_ARM_OVERLAY
	var current: float = float(anim_tree.get(path))
	var rate: float = 1.0 - exp(-delta / maxf(_blend_time(), 0.001))
	anim_tree.set(path, lerpf(current, wanted, rate))
	if wanted <= 0.0:
		return
	# SCRUBBED, NOT PLAYED. Left to run, the overlay keeps its own clock and
	# swings the arms several times across one climb -- the clip is 0.63 s and
	# the pull-up 1.3. Seeking it to the move's own progress every tick makes
	# the arms a function of how far up the wall the body is, which is the only
	# clock that means anything here.
	var progress: float = player.scripted_progress()
	if progress < 0.0:
		return
	var length: float = _clip_length(player.arm_overlay_clip)
	if length <= 0.0:
		return
	anim_tree.set("parameters/%s/seek_request" % GRAPH_ARM_OVERLAY_SEEK,
		clampf(progress, 0.0, 1.0) * length)

func _route(target: StringName, delta: float) -> void:
	_drive_arm_overlay(delta)
	if Player.SCRIPTED_MOVE_CLIPS.has(target):
		# ARMED FOR THE NEXT ORDINARY CLIP, every tick a scripted one is wanted,
		# so the hold measures how long the ORDINARY target has persisted rather
		# than how long ago the slot was claimed.
		_hold_left = _hold_time()
		_hidden_start = &""
		# ALREADY ON SCREEN -- and this is the common case, since the drive runs
		# every tick for the whole of a move. Re-requesting the input the gate is
		# showing would re-enter it, and the slots reset on entry.
		if _gate_input == _slot_name() and _slot_clip() == target and not _replay:
			return
		_replay = false
		_slot = 0 if _slot < 0 else (_slot + 1) % GRAPH_SCRIPTED_SLOTS.size()
		_load_slot(target)
		_request(_slot_name())
		return
	if _gate_input != GRAPH_STATES:
		_hold_left -= delta
		# BOTH CONDITIONS, not either. The ordinary target has to have persisted a
		# whole blend window AND the gate has to have stopped fading. Releasing on
		# whichever came first was tried and measured: an ordinary clip arriving
		# at a SETTLED slot -- which is how every scripted move ends -- handed the
		# gate straight back, and the sandwich popped exactly as before
		# (1.5556 -> 0.0000 in one tick, unchanged). The dwell is the fix; the
		# settle check only stops it releasing into a fade that is still running.
		if _hold_left > 0.0 or _gate_fading():
			# HELD -- and the machine is PRE-SWITCHED while nobody can see it.
			# start() on a zero-weight input is a FREE hard cut: measured, the
			# switch latches (get_current_node() stays put while hidden) and
			# materialises AT the target, frame 0, with no fading_from, on the
			# first live tick. A travel() latched here instead -- the previous
			# shape -- queued a crossfade FROM the stale pre-move node, so the
			# gate's fade landed on a blend of two poses neither of which was
			# moving -- a visible tail even at a short, 0.05 s hold, which is
			# why start() latches here instead of travel().
			if _hidden_start != target:
				_hidden_start = target
				_playback.start(target, true)
			return
		_request(GRAPH_STATES)
	_hold_left = 0.0
	if _hidden_start == target:
		# The latched hidden start() materialises on this first live tick; a
		# travel() on top would queue a second transition against it.
		_hidden_start = &""
		return
	_hidden_start = &""
	_playback.travel(target)

## True while the gate is still cross-fading one input into another.
##
## TWO 4.7.1 QUIRKS, BOTH MEASURED, AND EITHER ONE ALONE GIVES A WRONG ANSWER.
##
##   `> 0.0`, not `!= 0.0`: prev_xfading counts down through 0.0 and then RESTS
##   at one tick's worth of NEGATIVE (-0.016667 at 60 Hz), so a settled gate
##   never reports exactly zero.
##
##   prev_index >= 0: on the gate's very FIRST switch there is no previous input
##   to fade from, and prev_xfading is left PINNED at xfade_time forever rather
##   than counting down. Without this clause the hold below never releases -- a
##   body would enter its first scripted clip and never route an ordinary one
##   again. Caught by a test, not by inspection.
func _gate_fading() -> bool:
	if anim_tree == null:
		return false
	if int(anim_tree.get("parameters/%s/prev_index" % GRAPH_GATE)) < 0:
		return false
	return float(anim_tree.get("parameters/%s/prev_xfading" % GRAPH_GATE)) > 0.0

## The gate's own cross-fade length, which player.gd built it with.
func _blend_time() -> float:
	return player.body_animation_blend_time if player != null else 0.0

## The hold's own window -- deliberately NOT _blend_time(); see
## Player.body_gate_hold_time.
func _hold_time() -> float:
	return player.body_gate_hold_time if player != null else 0.0

## The name of the scripted slot most recently claimed, or an empty name before
## the first one.
func _slot_name() -> StringName:
	return GRAPH_SCRIPTED_SLOTS[_slot] if _slot >= 0 else &""

## The clip that slot is carrying, or an empty name.
func _slot_clip() -> StringName:
	var node := _slot_node()
	return node.animation if node != null else &""

func _slot_node() -> AnimationNodeAnimation:
	if _blend_tree == null or _slot < 0:
		return null
	return _blend_tree.get_node(_slot_name()) as AnimationNodeAnimation

## Loads `clip` onto the slot the ping-pong just moved to, TRIMMED EXACTLY AS THE
## STATE MACHINE'S OWN NODE FOR IT IS -- Player.apply_clip_timing() is the one
## helper both call sites go through, so a clip cannot play one way here and
## another way there.
func _load_slot(clip: StringName) -> void:
	var node := _slot_node()
	if node == null:
		return
	node.animation = clip
	if player == null or anim_tree == null:
		return
	var anim_player := anim_tree.get_node_or_null(anim_tree.anim_player) as AnimationPlayer
	if anim_player == null:
		return
	player.apply_clip_timing(node, clip, anim_player)

## Asks the gate for one of its inputs, by name.
func _request(input: StringName) -> void:
	_gate_input = input
	if anim_tree != null:
		anim_tree.set("parameters/%s/transition_request" % GRAPH_GATE, String(input))

## True while the player is holding the walk modifier AND asking to go
## somewhere. The same question the landing one-shot asks, deliberately -- one
## definition of "asking to move", used by both.
func _creeping() -> bool:
	if player.last_input == null or not player.last_input.walk_held:
		return false
	return player.wish_direction(player.last_input).length_squared() > 0.0001

## Where the walk hands over to the run: the speed at which the run clip would
## be scaled to SPEED_SCALE_MIN, i.e. the slowest it can honestly go.
##
## Not a new tuning value -- it falls out of bounds that already existed, and
## WALK_REFERENCE_PCT is set so the walk's ceiling lands on the same number.
func _run_band_speed() -> float:
	return player.body_run_reference_speed * SPEED_SCALE_MIN

## Moves whose end is a LANDING. Leaving one of these for WALKING is the moment
## the feet arrive, which is what Jump_Land is a clip of.
##
## Move.LANDING is deliberately absent: that is the hard landing nobody rolled
## out of, and it already routes to Jump_Land as its own clip for the whole of
## its two-second lockout.
const _AIRBORNE_MOVES: Array[StringName] = [
	Move.FALLING, Move.JUMP, Move.FALL_UNCONTROLLED, Move.COIL, Move.DODGE_JUMP,
]

## Decides whether the move that just started owes a one-shot -- a clip played
## ONCE at a transition rather than for as long as a state lasts.
##
## The packs ship three-part actions (Slide_Start / Slide / Slide_Exit) where
## this project has one state, and the ends are where a body reads as being
## driven by physics rather than by a person: a slide that begins at full speed
## with no push-off, a landing with no absorb. Neither end can be a move,
## because neither costs the player any time -- they are presentation, in
## exactly the sense docs/camera-authority.md means it, and they live here
## rather than in MoveManager for that reason.
##
## Clears any previous one-shot when nothing matches, so a second transition
## during one cuts it off rather than letting it outlive its moment.
func _arm_oneshot(from: StringName, to: StringName) -> void:
	# A DODGE HANDING OFF TO FALLING IS NOT A SECOND MOMENT. It is one airborne
	# arc that changes state halfway through, because DodgeJump ends the tick
	# the rise crosses enter_to_falling_z_speed rather than at touchdown. Left
	# to clear below, the armed clip dies about a quarter of the way in and the
	# airborne loop takes the body back in mid-sidestep -- which is the twitch,
	# not the clip's own pacing. Nothing here changes how FAST it plays: the
	# dodge is in neither SPEED_MATCHED_CLIPS nor DIRECTION_SETS and exposes no
	# scripted_duration(), so _drive_speed() leaves it at 1.0x either way.
	if from == Move.DODGE_JUMP and to == Move.FALLING:
		return
	_oneshot = Move.KEEP
	_oneshot_left = 0.0
	if to == Move.DODGE_JUMP:
		# Its own authored length, like every other one-shot. The landing
		# clears it through the ordinary path above, so what it actually owns
		# is the airborne arc rather than the whole 1.3 s -- a dodge clip still
		# running while the body sprints away would be a worse lie than the
		# handoff it replaces.
		_start_oneshot(_dodge_clip())
		return
	if to == Move.SLIDE:
		_start_oneshot(&"Slide_Start")
		return
	if from == Move.SLIDE:
		# NOT INTO A CROUCH: a slide into a crouch is continuous, the body
		# simply stays down, while a slide into a run is the player picking
		# themself back up. Slide_Exit is a stand-up, so it belongs only to
		# the second.
		if to != Move.CROUCH:
			_start_oneshot(&"Slide_Exit")
		return
	if _AIRBORNE_MOVES.has(from) and to == Move.WALKING:
		# NOT WHILE DYING: playing Jump_Land on touchdown after death is wrong
		# -- the character is already dead by then, so it must not land like
		# anyone else.
		#
		# The gate below asks whether a direction is held, and a dying player's
		# input is LOCKED -- so it reads as nothing held, which is exactly the
		# case that arms the absorb. The death is the earlier answer.
		if player.is_dying():
			return
		# ONLY WHEN NOTHING IS HELD, on the owner's call: land into the absorb
		# when the player has stopped asking to go anywhere, and straight into
		# the run when they have not. Holding a direction through a landing is
		# the player saying they are still moving, and a stand-up-from-a-crouch
		# in the middle of that would be the animation contradicting them.
		if player.wish_direction(player.last_input).length_squared() < 0.0001:
			_start_oneshot(&"Jump_Land")

## Which of the dodge pair the live dodge wants, named for the side the body
## goes. Read off the move rather than off velocity, which air control has
## already had a tick at by the time anything asks -- the same job
## JumpMove.kick_side() does for the wall-kick clips.
func _dodge_clip() -> StringName:
	var move = player.move_manager.move_for(Move.DODGE_JUMP) 		if player != null and player.move_manager != null else null
	var side: int = move.side() if move != null and move.has_method("side") else 0
	return &"Dodge_Right" if side > 0 else &"Dodge_Left"

## The one-shot on screen right now, or KEEP. Read from outside by anything
## that has to last exactly as long as a transition CLIP does rather than as
## long as some state or cooldown -- the stand-up out of a slide is the case
## this exists for.
func active_oneshot() -> StringName:
	return _oneshot

## Arms `clip` for its own natural length, if the attached body has it at all.
func _start_oneshot(clip: StringName) -> void:
	if not _has_clip(clip):
		return
	var length := _clip_length(clip)
	if length <= 0.0:
		return
	_oneshot = clip
	_oneshot_left = length

## The armed one-shot, or KEEP. Counts the clock down, and cancels early when
## the moment it belongs to has passed.
func _oneshot_target(delta: float) -> StringName:
	if _oneshot == Move.KEEP:
		return Move.KEEP
	# A landing absorb is answerable to the player: the instant they ask to move
	# again it stops, mid-clip, and the ordinary routing takes over. Waiting out
	# the rest of it would be a fraction of a second of ignored input, which is
	# the one thing this project will not spend on presentation.
	if _oneshot == &"Jump_Land" and player.wish_direction(player.last_input).length_squared() > 0.0001:
		_oneshot = Move.KEEP
		_oneshot_left = 0.0
		return Move.KEEP
	_oneshot_left -= delta
	if _oneshot_left <= 0.0:
		_oneshot = Move.KEEP
		_oneshot_left = 0.0
		return Move.KEEP
	return _oneshot

## A clip's authored duration, read off the AnimationPlayer the AnimationTree is
## already pointed at. Read rather than configured so a one-shot's window can
## never drift from the clip it is a window for -- swapping in a longer
## Slide_Exit needs no number changed anywhere.
## How long `clip` plays for at 1.0x -- its kept length, see _clip_length().
## For a caller outside this file that paces something on the clip rather
## than the clip on it (Player's step round turns the heading over the
## Turn90 clip's own length).
func clip_play_length(clip: StringName) -> float:
	return _clip_length(clip)

func _clip_length(clip: StringName) -> float:
	if anim_tree == null:
		return 0.0
	var anim_player := anim_tree.get_node_or_null(anim_tree.anim_player) as AnimationPlayer
	if anim_player == null or not anim_player.has_animation(clip):
		return 0.0
	var whole: float = anim_player.get_animation(clip).length
	# THE KEPT PART, NOT THE WHOLE CLIP. A trimmed clip is shorter, and every
	# caller here is asking "how long is the thing that will actually play" --
	# the speed match, and the scripted fit that stretches it into a move.
	#
	# DO NOT return the untrimmed length for a clip that has an entry in
	# body_clip_timings: if a 20-frame clip has its first 6 frames skipped and
	# is meant to play its remaining 14 within 1 s, fitting against the full
	# 20-frame length makes the fit too slow for what is actually left, so the
	# trimmed clip finishes early and the move runs on for the rest of its
	# duration on a held pose -- 0.70 s of animation inside a 1.00 s move.
	if player == null or not player.body_clip_timings.has(clip):
		return whole
	var entry = player.body_clip_timings[clip]
	if not (entry is Array and entry.size() >= 2):
		return whole
	var length: float = float(entry[1])
	if length > 0.0:
		return length
	return maxf(whole - float(entry[0]), 0.0)

## Scales the clip's playback to the speed the body is actually travelling, so
## a cycle authored at one pace does not slide its feet across the ground at
## every other pace.
##
## POSITIVE ONLY, deliberately. AnimationNodeTimeScale documents reversal too --
## "allows to scale the speed of the animation (or reverse it)" -- but a
## NEGATIVE scale has a long tail of reported trouble around LOOPING clips, and
## every clip here is looping (see _ensure_clip_loops in player.gd).
## godotengine/godot#27215 is exactly the shape that would bite: "plays
## backwards, then rewinds to the beginning and stops there". It was closed as
## `archived` during the 3.x-to-4.x issue cleanup rather than fixed, so its
## absence in 4.7 is not something to assume.
##
## Backward locomotion, if it is ever wanted, belongs in a second
## AnimationNodeAnimation carrying the same clip with
## play_mode = PLAY_MODE_BACKWARD. That reaches the same result without a
## negative scale ever existing.
func _drive_speed(clip: StringName) -> void:
	if anim_tree == null:
		return
	var scale := 1.0
	var reference: float = player.body_run_reference_speed
	# Stripped, so a reversed twin scales exactly like the clip it reverses.
	var base_clip: StringName = clip
	if String(clip).ends_with(Player.BACKWARD_SUFFIX):
		base_clip = StringName(String(clip).trim_suffix(Player.BACKWARD_SUFFIX))
	# A STRAFE IS THE SAME GAIT AS ITS FORWARD TWIN, so it scales against the
	# same reference. Walk_L measured against the run would sit on the scale
	# floor for its entire range.
	var family := _family_of(base_clip)
	if CROUCHED_CLIPS.has(base_clip) or family == &"Crouch":
		reference *= player.config.pawn.crouched_pct
	elif WALK_CLIPS.has(base_clip) or family == &"Walk":
		reference *= WALK_REFERENCE_PCT
	elif family == &"Jog":
		reference *= JOG_REFERENCE_PCT
	# A SCRIPTED MOVE FITS ITS CLIP TO ITSELF, and takes priority over any
	# speed matching: the body is being carried along a path on a clock the move
	# owns, so the only cadence that can look right is the one that finishes
	# when the move does.
	var fitted := _scripted_fit(base_clip)
	if fitted > 0.0:
		anim_tree.set("parameters/%s/scale" % GRAPH_TIME_SCALE, fitted)
		return
	# A MOVE MAY NAME ITS OWN RATE OUTRIGHT, the same way it may fit a clip to
	# its own clock above. LedgeWalkMove does: its sidestep is a shuffle, not a
	# walk, and a walk cycle matched to shuffle speed lands near 0.4x. Duck-
	# typed like every other optional per-move contribution here.
	var move = player.move_manager.move_for(player.move_manager.current_name) \
		if player.move_manager != null else null
	if move != null and move.has_method("clip_time_scale"):
		var named: float = move.clip_time_scale()
		if named > 0.0:
			anim_tree.set("parameters/%s/scale" % GRAPH_TIME_SCALE, named)
			return
	if reference > 0.0 and (SPEED_MATCHED_CLIPS.has(base_clip) or family != &""):
		# travel_speed(), NOT horizontal_speed() -- see travel_speed()'s own
		# note on why velocity lies through a vault or a mantle. The eye already
		# reads it for the same reason.
		# A LOWER FLOOR FOR THE WALK, and it is derived rather than picked: the
		# creep is 0.5 m/s against a walk authored near 1.8, so the honest scale
		# there is 0.28 and the ordinary 0.5 floor would run the feet at 0.9 m/s
		# under a body doing 0.5. SPEED_SCALE_MIN exists to stop ONE clip being
		# stretched across everything; a walk asked to walk slowly is not that.
		var scale_min := SPEED_SCALE_MIN
		if WALK_CLIPS.has(base_clip) or family == &"Walk":
			scale_min = minf(SPEED_SCALE_MIN, player.config.pawn.walk_velocity / reference)
		scale = clampf(player.travel_speed() / reference, scale_min, SPEED_SCALE_MAX)
	anim_tree.set("parameters/%s/scale" % GRAPH_TIME_SCALE, scale)

## The time scale that makes `clip` finish exactly when the scripted move
## playing it does, or 0 when the current move is not scripted.
##
## DO NOT let a scripted clip play at its authored length regardless of the
## move's own duration: SpeedVaultMove shortens its own arc for a fast
## approach, floored by SpeedVaultConfig.duration_floor_pct, and without this
## fit the clip would keep going at full length and read as running at the
## wrong speed for the move driving it. Fitted into a 0.325 s window, a
## 0.733 s SafetyVault has to run at 2.26x to finish with the move (see
## test_scripted_clip_fit.gd).
##
## This makes the ANIMATION agree with the move. It does not make the move
## right: whether a vault should get faster the faster you approach is a
## separate question, and the floor SpeedVaultMove applies is this project's
## own invention rather than anything measured. Recorded here because fitting
## the clip to it hides the symptom that would otherwise keep asking.
func _scripted_fit(clip: StringName) -> float:
	if player.move_manager == null:
		return 0.0
	var move := player.move_manager.move_for(player.move_manager.current_name)
	# Duck-typed rather than `is ScriptedMove`: a move that COMPOSES a
	# scripted phase (LadderMove's top exit -- GDScript has no multiple
	# inheritance) exposes the same scripted_duration(), returning 0 outside
	# the phase. The clip is stretched to fill the move's hitstun window when
	# the authored animation is shorter than it.
	if move == null or not move.has_method("scripted_duration"):
		return 0.0
	var duration: float = move.scripted_duration()
	if duration <= 0.0:
		return 0.0
	var length := _clip_length(clip)
	if length <= 0.0:
		return 0.0
	return clampf(length / duration, SCRIPTED_FIT_MIN, SCRIPTED_FIT_MAX)

## True when `clip_name` has an actual node in the AnimationTree's graph --
## i.e., travel() can reach it without error. player.gd's
## _wire_body_animation() only ever adds a node for a clip the attached
## body's AnimationPlayer actually has, so this is really asking "does the
## ATTACHED BODY have this clip", one level removed.
func _has_clip(clip_name: StringName) -> bool:
	return _graph != null and _graph.has_node(clip_name)

## Returns the first of `candidates` that _has_clip(), in priority order --
## the highest-priority entry is the genuine, semantically-correct match for
## the calling move; every entry after it is a progressively less accurate
## but still-better-than-nothing fallback. Returns Move.KEEP if the
## attached body (or the lack of one) has none of them.
## The airborne loop, in preference order. `Jump` is the pack's AIRBORNE LOOP
## (Jump_Loop, with the suffix stripped on merge), which is what a fall is. It
## led with the fox's `jump` before, which is a whole take-off-to-landing clip.
const AIRBORNE_LOOP: Array[StringName] = [&"Jump", &"NinjaJump_Idle", &"jump",
	&"Idle", &"idle"]

## TWO DEATHS, and the fall is the odd one out.
##
## [ME:CONFIRMED] The original has a single death clip and it is the non-fall
## one -- cut up, or shot. Dying to a fall there is a bone-crack and an
## immediate cut to black; the falling performance is this project's own
## addition, so it is the branch that needs the special clip while everything
## else gets the one death the library has.
##
## UAL2's long fall family, not a generic Death02: this is a body still
## falling, not a body giving way. DO NOT use LiftAir_Fall_Impact -- it reads
## as a violent full-body convulsion, the arrival rather than the fall, and
## played as a whole death it thrashes instead of settling. The clip offset
## and the death eye lift were both tuned against Impact (0.1 m on the model,
## 0.4 m on the eye) and neither transfers; they are the owner's to re-dial,
## F9 for the model and F1 for the eye.
const FALL_DEATH_CLIPS: Array[StringName] = [&"LiftAir_Fall", &"Death02",
	&"Death01", &"sneaking", &"Crouch_Idle", &"idle"]

## Death02 is UAL1's full library, i.e. PRIVATE. Death01 ships with the repo,
## so a clone without the private submodule still dies properly. Each clip
## puts the hips somewhere different, so they want their own offsets in
## scenes/player/tuning/.
const DEATH_CLIPS: Array[StringName] = [&"Death02", &"Death01",
	&"LiftAir_Fall", &"sneaking", &"Crouch_Idle", &"idle"]

## Death02 collapses FACE DOWN AND FORWARD, which puts the model straight
## through any wall the body was facing. Death01 does not, so it is the one
## that fits where there is no room in front to fall into.
const WALL_DEATH_CLIPS: Array[StringName] = [&"Death01", &"Death02",
	&"LiftAir_Fall", &"sneaking", &"Crouch_Idle", &"idle"]

## Roughly a body length. The clip needs somewhere to put the MODEL, not
## somewhere to put the capsule, so no config dial is offered: the reach is a
## property of the animation, not of the level.
const DEATH_WALL_CLEARANCE := 1.5

## Which clips this death picked, chosen once and held for its duration.
## Empty between deaths -- see the reset below for why that is an assignment
## rather than a clear().
##
## LATCHED, because the choice asks about the WORLD. Re-asked every frame, the
## collapse itself carries the body away from the wall it was facing and the
## clip swaps halfway through going down.
var _death_clips: Array[StringName] = []

func _death_clip_list() -> Array[StringName]:
	if player.health != null and player.health.last_cause == Health.Cause.FALL:
		return FALL_DEATH_CLIPS
	return WALL_DEATH_CLIPS if _facing_a_wall() else DEATH_CLIPS

func _facing_a_wall() -> bool:
	if player.probes == null:
		return false
	var ahead: Vector3 = -player.global_transform.basis.z
	return not player.probes.side_hit(player.global_position, ahead,
		DEATH_WALL_CLEARANCE).is_empty()

func _first_available(candidates: Array[StringName]) -> StringName:
	for candidate in candidates:
		if _has_clip(candidate):
			return candidate
	return Move.KEEP

## True when the body is travelling BEHIND itself -- backpedalling rather than
## running. Compared against the facing rather than read off the input, so a
## body carried backwards by a slide or a wall kick reads correctly too.
##
## The dead zone matters: strafing is neither forward nor backward, and a body
## sidestepping must not flicker between a clip and its reverse on float noise.
func _travel_octant() -> int:
	var angle: float = _travel_angle()
	if is_nan(angle):
		return -1
	return posmod(int(round(angle / (PI / 4.0))), 8)

## The signed angle from the FACING to the direction of travel, in radians,
## positive to the RIGHT. NAN when there is nothing to measure: a body at rest,
## or one with no horizontal facing.
##
## One measurement for both readers. The octant above rounds it; the twist
## below uses it whole, and two atan2 calls with their own sign conventions is
## how the left diagonal ends up on the right clip.
func _travel_angle() -> float:
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if travel.length_squared() < 0.04:
		return NAN
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return NAN
	facing = facing.normalized()
	# Positive to the RIGHT of the facing, the same axis Player._drive_body_yaw()
	# builds for the torso twist -- for a facing of -Z this cross product is +X.
	var right: Vector3 = facing.cross(Vector3.UP)
	travel = travel.normalized()
	return atan2(travel.dot(right), travel.dot(facing))

## The yaw the LOWER body has to carry because the clip on screen does not, as
## a rotation ABOUT Vector3.UP -- which is to say positive turns the body to
## its LEFT, and the sign is the opposite of _travel_angle()'s.
##
## THE FLIP IS THE POINT, and getting it wrong turns the legs away from the
## direction of travel while the shoulders swing into it, which reads as the
## whole body facing backwards. Two conventions meet here and neither is free
## to change: _travel_angle() is positive to the RIGHT because DIRECTION_SETS
## runs clockwise from straight ahead, while Basis(Vector3.UP, angle) is a
## right-handed turn about UP, so for a body facing -Z a positive angle goes
## LEFT. This function speaks the second, because what it feeds is the first
## argument of exactly that Basis.
##
## Inside the forward arc the run band plays ONE forward clip for every
## direction in it (see _target_animation()), so a body running a diagonal at
## full speed has its legs pointing straight ahead while it travels 45 degrees
## off. The packs' own octant clips answer exactly this by rotating the whole
## of Hips 43-47 degrees; this is the same answer for the directions inside the
## arc, where there is no octant clip to reach for.
##
## ZERO WHEREVER AN AUTHORED CLIP IS ALREADY TURNED. Outside the arc the
## eight-way set is playing, and turning the body again on top of it is the
## double-count that shook the first-person camera -- the eye rides the head
## bone, so a fault in the hips surfaces a long way from where it is.
##
## The test is the ARC, not this frame's clip name. The arc carries a tolerance
## across the diagonal it sits on; a question asked of the clip flips on
## velocity noise, which is what made the model judder the last time this was
## tried.
func lower_body_twist() -> float:
	if player.move_manager == null \
			or player.move_manager.current_name != Move.WALKING:
		return 0.0
	if player.horizontal_speed() <= _run_band_speed():
		return 0.0
	if not _travelling_in_forward_arc():
		return 0.0
	var angle: float = _travel_angle()
	return 0.0 if is_nan(angle) else -angle

## True while the body is TRAVELLING inside the forward arc, the same arc that
## decides whether it may reach full ground speed.
##
## Read off velocity rather than off the input, for the reason _travel_octant()
## is: a body carried sideways by a slide or a wall kick is travelling
## sideways whatever the keys say, and the cadence has to answer to the ground
## it is covering.
##
## Motionless counts as forward, matching in_forward_arc()'s own answer for a
## zero direction. Nothing reaches this while standing still -- the run band
## starts at 3.6 m/s -- so it exists to be a defined answer, not a case.
func _travelling_in_forward_arc() -> bool:
	return player.in_forward_arc(Vector3(player.velocity.x, 0.0, player.velocity.z))

## The eight-way family a clip belongs to, or an empty name. Used by
## _drive_speed() so that a strafe scales against the same reference its
## forward twin does -- Walk_L is a walk, and measuring it against the run would
## put it on the scale floor for its whole range.
func _family_of(clip: StringName) -> StringName:
	for family in DIRECTION_SETS:
		for suffix in DIRECTION_SETS[family]:
			if clip == StringName(String(family) + String(suffix)):
				return family
	return &""

## _first_available(), but preferring each candidate's REVERSED twin while the
## body is backpedalling. Falls through to the forward clip whenever the twin is
## missing, so a body with no reversible clips behaves exactly as before.
func _first_available_directional(candidates: Array[StringName]) -> StringName:
	var octant := _travel_octant()
	for candidate in candidates:
		# THE PACKS' OWN EIGHT-WAY SET, when the candidate names a family. A
		# body that has the whole set never reaches anything below this.
		if DIRECTION_SETS.has(candidate):
			var suffixes: Array = DIRECTION_SETS[candidate]
			if octant >= 0:
				var facing_clip := StringName(String(candidate) + String(suffixes[octant]))
				if _has_clip(facing_clip):
					return facing_clip
			# The family's own forward clip, for a body that has some of the set
			# but not this direction -- the free tier ships Crouch_Fwd and none
			# of its seven neighbours. Running forwards is wrong for a strafe,
			# but it is the same body and the same cadence, which the next
			# candidate down would not be.
			var forward_clip := StringName(String(candidate) + String(suffixes[0]))
			if _has_clip(forward_clip):
				return forward_clip
		# THE REVERSED TWIN is the fallback for a body with no eight-way set at
		# all -- the fox -- and it is a coarse approximation: octants 3 to 5 are
		# treated as the whole backward half, not just the exact opposite
		# direction.
		if octant >= 3 and octant <= 5:
			var backward := StringName(String(candidate) + Player.BACKWARD_SUFFIX)
			if _has_clip(backward):
				return backward
		if _has_clip(candidate):
			return candidate
	return Move.KEEP

## Maps the player's current movement state onto a priority list of clips,
## then resolves that list against whatever the attached body actually has.
func _target_animation() -> StringName:
	# THE PACKS COME FIRST, the fox's own six names come last: the pack name is
	# the intended clip everywhere a body carries the Universal Animation
	# Library, and the fox name (`run`/`idle`/`jump`/`sneak`/`sneaking`/
	# `ladder_stillness`) is only the fallback that keeps existing fox scenes
	# working.
	#
	# ONE EXCEPTION, and it is deliberate: the GRAB hang still leads with
	# `ladder_stillness`, because a genuine match outranks this ordering. The
	# packs have nothing for hanging off a ledge; the fox has exactly that.
	#
	# NO Jog_Fwd ANYWHERE: Sprint is the run, DO NOT reintroduce the jog for
	# straight-ahead running. It is gone from the routing, from
	# SPEED_MATCHED_CLIPS, and from the clips Player wires into the graph at
	# all -- left in any of those it would come back the next time a list was
	# reordered.
	# DYING OUTRANKS EVERY MOVE, because it is not one. The level's death
	# sequence locks the input and drives the camera while whatever Move the
	# player died in carries on ticking underneath -- usually a fall. It plays
	# in first person too, not just third: the head is hidden there and it
	# costs nothing to have the body fall over properly.
	if player.is_dying():
		if _death_clips.is_empty():
			_death_clips = _death_clip_list()
		return _first_available(_death_clips)
	# A FRESH ARRAY, NOT .clear(). The lists above are `const`, which in Godot 4
	# means read-only -- clear() on one fails silently apart from an error in
	# the log, so _death_clips never empties and the FIRST death of the session
	# picks the clip for every death after it.
	_death_clips = []
	match player.move_manager.current_name:
		Move.WALKING:
			# THREE BANDS, not two. The free tier has a genuine Walk and the
			# owner asked for it to be used, which also closes the hole the
			# Sprint swap opened: below the run's scale floor a sprint was being
			# played in slow motion, because one clip was covering the whole
			# range from a crawl to full pace.
			# CTRL IS THE WALK, and it is the reason this case is not a plain
			# speed split: the Ctrl walk modifier already IS the walk, so
			# holding it should route straight to a walk clip rather than
			# through the speed thresholds below. Without this case it played
			# a STANDING IDLE: the modifier caps the body at walk_velocity,
			# 0.5 m/s, and the idle-versus-moving threshold sits at 1.0, so a
			# creep never reached the moving branch at all. Feet still, body
			# drifting.
			#
			# Asked of the INPUT rather than the speed, so there is no second
			# epsilon to keep in step with the first: Ctrl held with a direction
			# asked for is a walk, whatever the body has actually reached yet.
			# Ctrl held while standing still falls through to idle below.
			# STEPPING ROUND on the spot: the pack's quarter turn, on the side
			# the body steps to, at PawnConfig.turn_in_place_clip_scale through
			# WalkingMove.clip_time_scale(). Both clips are in
			# Player.SCRIPTED_MOVE_CLIPS, so _route() puts them on a scripted
			# slot like any other one-shot. See Player._begin_turn_in_place().
			if player.is_turning_in_place():
				# A NEW step replays the clip even though its name has not
				# changed -- see Player._turn_in_place_serial.
				if player.turn_in_place_serial() != _turn_serial_seen:
					_turn_serial_seen = player.turn_in_place_serial()
					_replay = true
				var wanted: StringName = player.turn_in_place_clip()
				var other: StringName = &"Turn90_L" if wanted == &"Turn90_R" else &"Turn90_R"
				return _first_available([wanted, other, &"Idle", &"idle"])
			if _creeping():
				return _first_available_directional([&"Walk", &"Walk_Carry", &"Sprint", &"run", &"idle"])
			var speed: float = player.horizontal_speed()
			if speed > _run_band_speed():
				# SPRINT ACROSS THE FORWARD ARC, JOG OUTSIDE IT.
				#
				# Neither pack has an eight-way sprint -- Sprint is one clip,
				# forward only -- and the eight-way sets are the jog's and the
				# walk's. So the run band is split by DIRECTION rather than run
				# on one clip: the arc takes the sprint, and outside it the jog
				# is the only thing that can strafe at all.
				#
				# THE SAME ARC THE SPEED USES, asked of Player rather than
				# rounded to an octant here. Two reasons, and both have already
				# cost a session:
				#
				# ONE ARC, NOT TWO -- the rule 46b5148 set when the slide gate
				# was made to ask in_forward_arc() instead of carrying its own
				# angle. A second angle here would drift from PawnConfig's
				# forward_arc_deg, and the pair is what makes the cadence agree
				# with the speed: inside the arc the body reaches the full
				# 7.2 m/s and the sprint's reference IS 7.2, so it plays at
				# 1.0; outside it the ceiling falls to 4.0 against the jog's
				# 3.6 and it plays at 1.11. Split them and a diagonal ran at
				# full speed on a clip referenced to half of it, which pinned
				# the time scale to SPEED_SCALE_MAX and doubled the cadence
				# the moment a strafe key went down.
				#
				# THE DIAGONAL SITS EXACTLY ON THE EDGE. W+A is 45 degrees and
				# the arc is 45 degrees, so any comparison written here would
				# be between two floats equal in exact arithmetic and not in
				# practice. in_forward_arc() already carries the tolerance that
				# fixes it; rounding travel to the nearest eighth does not, and
				# an octant boundary lands on the diagonal too.
				if _travelling_in_forward_arc():
					return _first_available([&"Sprint", &"Jog_Fwd", &"Walk_Fwd", &"run", &"idle"])
				return _first_available_directional([&"Jog", &"Walk", &"Sprint", &"run", &"idle"])
			if speed > player.config.pawn.run_animation_speed_threshold:
				return _first_available_directional([&"Walk", &"Walk_Carry", &"Sprint", &"run", &"idle"])
			return _first_available([&"Idle", &"Idle_FoldArms", &"idle", &"Walk"])
		Move.FALLING:
			return _first_available(AIRBORNE_LOOP)
		Move.SOFT_LANDING:
			# A RESCUED FALL LOOKS LIKE AN ORDINARY ONE. LiftAir is the dying clip
			# and stays with FALL_UNCONTROLLED: the body about to be caught is not
			# going limp, it just has no say in where it lands.
			#
			# Its own case rather than sharing FALLING's, because
			# test_every_move_has_its_own_case looks for the literal "Move.X:" --
			# a combined case hides whichever name is not last.
			return _first_available(AIRBORNE_LOOP)
		Move.ZIPLINE:
			# No zipline clip in the packs. The airborne loop is the closest
			# honest pose until contact IK gives the hands the cable -- animation
			# for this move is a known gap, to be closed later with hand IK on
			# the Jump clip rather than a dedicated zipline pose.
			return _first_available([&"Jump", &"NinjaJump_Idle", &"jump", &"Idle", &"idle"])
		Move.SWING:
			# The packs carry no swing cycle; the ledge-hang idle is the
			# closest honest two-hands-overhead pose. A real swing clip and
			# hands-on-bar IK are known gaps (spec 2026-08-25 §7).
			return _first_available([&"Climb_Idle", &"NinjaJump_Idle", &"Jump", &"jump", &"idle"])
		Move.LADDER:
			# Per the spec (docs/superpowers/specs/2026-08-25-ladder-design.md
			# §攀爬): the top exit uses the same clip GrabMove's mantle
			# plays, ClimbUp_1m. SELECTION happens right here: is_top_exiting()
			# picks the clip (mirroring GRAB's is_mantling() above), and
			# _route() gates any SCRIPTED_MOVE_CLIPS member onto the scripted
			# slot. Player.set_clip_lift_cancelled(), which
			# LadderMove._begin_top_exit() also arms, plays NO part in clip
			# choice -- it only stops the clip's own baked hip lift from
			# stacking on the scripted vertical carry.
			var ladder_move = player.move_manager.move_for(Move.LADDER)
			if ladder_move != null and ladder_move.is_top_exiting():
				return _first_available([&"ClimbUp_1m", &"ClimbUp_2m", &"ClimbLedge",
					&"Jump_Start", &"jump", &"idle"])
			# Direction-aware: the FULL library carries Climb_Up/Climb_Down
			# cycles; the free tier falls back to the hanging idle, which is
			# the closest honest two-hands-in-front pose. Hand IK on the
			# rungs is a known gap (spec 2026-08-25 §攀爬).
			var dir: int = ladder_move.climb_direction() if ladder_move != null else 0
			if dir > 0:
				return _first_available([&"Climb_Up", &"Climb_Idle", &"NinjaJump_Idle", &"Jump", &"jump", &"idle"])
			if dir < 0:
				return _first_available([&"Climb_Down", &"Climb_Idle", &"NinjaJump_Idle", &"Jump", &"jump", &"idle"])
			return _first_available([&"Climb_Idle", &"NinjaJump_Idle", &"Jump", &"jump", &"idle"])
		Move.RAMP_SLIDE:
			# The seated chute slide. The pack's Slide is a feet-first slide
			# on the ground, which is the same shape from the hips down; no
			# clip in it is a seated slide.
			return _first_available([&"Slide", &"Crouch_Idle", &"idle"])
		Move.SLIDE:
			# A GENUINE MATCH: UAL2 ships Slide_Start / Slide / Slide_Exit. This
			# case is the middle one only -- the two ends are one-shots, armed
			# by _arm_oneshot() at the transitions into and out of the move,
			# because neither end is a state the player spends time in.
			# Everything after Slide is the old PLACEHOLDER reasoning: a slide
			# is fast, committed ground momentum, so a run is the closest thing.
			return _first_available([&"Slide", &"Sprint", &"run", &"idle"])
		Move.SPRING_BOARD:
			# The walk up and the two steps play the pack's StepUp -- a
			# no-hands scramble is what stepping up two plants is -- fitted
			# to both step times through scripted_duration(). The rise is a
			# rise: the same airborne loop every other one plays. No clip in
			# the pack is a spring board; this is the nearest shape.
			var board = player.move_manager.move_for(Move.SPRING_BOARD)
			if board != null and board.is_stepping():
				return _first_available([&"StepUp", &"Jump_Start", &"jump", &"idle"])
			if board != null and board.has_launched():
				return _first_available(AIRBORNE_LOOP)
			return _first_available([&"StepUp", &"Jump_Start", &"Idle", &"idle"])
		Move.SPEED_VAULT:
			# TWO DIFFERENT MOVES BEHIND ONE STATE, told apart the way GRAB's
			# two phases are -- by asking the move.
			#
			# The compensating vault and the one where the shin catches the
			# edge both play StepUp: they are the vaults that were never set
			# up -- no run-up, no plant, the player simply arrived and
			# scrambled. [ME:CONFIRMED 05 §5.7] The original agrees from the
			# other direction: of its six vault types, its two step-up rows
			# (autostepuprightleg, stepuprightleg88) are precisely the two
			# with no hand IK at all, because there is no hand in them.
			var vault_move = player.move_manager.move_for(Move.SPEED_VAULT)
			if vault_move != null and vault_move.is_scramble():
				return _first_available([&"StepUp", &"ClimbUp_1m", &"Jump_Start", &"jump", &"idle"])
			# SafetyVault is a one-handed plant over an obstacle, which is what
			# a vault that WAS set up looks like. Behind it, the old reasoning:
			# a vault is a short airborne burst, so the take-off half of a jump
			# is the closest thing a body without the paid pack has.
			return _first_available([&"SafetyVault", &"Jump_Start", &"NinjaJump_Start", &"jump", &"idle"])
		Move.GRAB:
			# Two phases share this one move (see GrabMove's own header
			# comment): hanging (frozen, waiting on input) and mantling (a
			# scripted climb onto the top). They are told apart here via
			# GrabMove.is_mantling(), the same way test_arena.gd reads
			# SlideMove.is_crawling() to see inside a move from the outside.
			var grab_move = player.move_manager.move_for(Move.GRAB)
			if grab_move != null and grab_move.is_climbing_low():
				# A CLIMB INTO A DUCT IS NOT ANIMATED IN THIS PACK, so it is
				# not animated as a climb.
				#
				# [ME:CONFIRMED] The original carries a SECOND climb for this.
				# A pull-up there pushes the body up on both hands and then
				# brings the feet through; going into a low opening puts the
				# RIGHT FOOT up first and hooks the body in after it. Two
				# actions, not one action trimmed. THE PROPER FIX IS THAT CLIP,
				# and until the pack has one this is a stopgap, kept because a
				# crouch that reads oddly beats a climb that puts the head
				# through the ceiling.
				#
				# Every frame of ClimbUp_1m is a body
				# hauling itself upright -- head high, feet off the floor --
				# and there is no frame in it that is compact, so cutting the
				# clip only chooses which tall pose to end on -- which is why
				# the frame-count trim that used to live here is gone. In a space too
				# low to stand in, that pose is inside the ceiling: the eye
				# leaves the capsule in first person and the model clips in
				# third.
				#
				# So the pose crouches for the whole crossing while the
				# scripted path does the travelling. The capsule leads and the
				# presentation follows -- docs/capsule-leads-presentation.md --
				# and here that means arriving in the pose the body will be in
				# rather than acting out a stand-up it has to undo.
				# Crouch_Enter LEADS. It is a one-shot that folds the legs
				# under the body, and _scripted_fit() stretches it across the
				# whole crossing -- so they tuck over the climb rather than
				# snapping in at the end, and its last frame is already the
				# pose the body hands over into. A locomotion loop can do
				# neither: it ends wherever the cycle happened to be, which is
				# what made the feet twitch at the hand-off.
				#
				# NOT THE PACK'S Crawl_* SET, though it has one and it is a
				# closer name. Crawl there is PRONE, on hands and knees, and
				# this project has no prone state for it to hand over to.
				return _first_available([&"Crouch_Enter", &"Crouch_Fwd",
					&"Crouch_Idle", &"sneaking", &"sneak", &"idle"])
			if grab_move != null and grab_move.is_mantling():
				# ClimbUp_1m leads: the pelvis is pinned to the capsule and a
				# bezier lifts it through the mantle, so what the clip needs
				# to supply is the POSE, not the whole climb. ClimbUp_2m
				# stays as the fallback -- at 1.300 s against ClimbUp_1m's
				# 0.667 it is a slower haul that also reads as a pull-up, and
				# it is what this line played before the capsule started
				# carrying the rise itself. ClimbLedge (0.633 s), the other
				# candidate from UAL1's hang set, is not preferred over
				# either: it is over before the body has left the lip, which
				# reads wrong for a pull-up regardless of how its duration is
				# stretched. (Judged from the names and the company they
				# keep, not from watching them -- the gallery shows all
				# three.)
				#
				# The duration does not follow whichever clip is picked:
				# _scripted_fit() stretches it into GrabConfig.mantle_duration
				# (1.3 s, ClimbUp_2m's own measured length -- [ME:CONFIRMED]
				# the original's TdMove_GrabPullUp carries no duration field
				# of its own, so there the clip IS the duration). 0.667
				# stretched into 1.3 is 0.51x, well inside the clamp, so
				# ClimbUp_1m simply plays slower rather than ending early.
				return _first_available([&"ClimbUp_1m", &"ClimbUp_2m", &"ClimbLedge",
					&"Jump_Start", &"jump", &"idle"])
			# Climb_Idle is UAL1's hang, and leads here since it is no longer
			# behind a paid tier. The fox's `ladder_stillness` keeps second
			# place: it was the genuine match while it was the only one, and
			# it still is for a body that has it.
			# TRAVELLING ALONG THE LEDGE gets its own pair, told apart from a
			# still hang exactly the way the mantle above is told apart from
			# both -- by asking the move, since nothing else can see the
			# difference. Climb_Left and Climb_Right are UAL1's hand-over-hand
			# and belong to the same hang set as Climb_Idle, so the three blend
			# into each other without a re-plant.
			#
			# No `idle` at the end of these two: falling all the way back to a
			# standing pose mid-shimmy would stand the player up in the air.
			# Climb_Idle is the right floor to stop at -- a body that has the
			# hang clip but not the travel clips should keep hanging.
			var shimmy: float = grab_move.shimmy_direction() if grab_move != null else 0.0
			if shimmy < 0.0:
				return _first_available([&"Climb_Left", &"Climb_Idle", &"ladder_stillness"])
			if shimmy > 0.0:
				return _first_available([&"Climb_Right", &"Climb_Idle", &"ladder_stillness"])
			return _first_available([&"Climb_Idle", &"ladder_stillness", &"NinjaJump_Idle", &"Jump", &"jump", &"idle"])
		Move.WALL_RUN:
			# THE DAY HAS ARRIVED. WallRun_L/R are the real thing, and Player
			# has been tracking wall_side for the torso twist all along, so
			# picking between them costs nothing new.
			#
			# wall_side > 0 is a RIGHT-hand wall -- WallRunMove's own look-fan
			# code says so at the line that reads `span if wall_side > 0`.
			#
			# WHICH WAY ROUND THE CLIPS ARE NAMED IS A GUESS: _L could mean
			# the wall is on the left or that the body travels leftward. Taken
			# as the wall's side, which is the commoner convention. If a wall
			# run reads mirrored, this line is the whole of the fix.
			var wall_clip: StringName = &"WallRun_R" if player.wall_side > 0 else &"WallRun_L"
			return _first_available([wall_clip, &"WallRun_L", &"WallRun_R", &"Sprint", &"run", &"idle"])
		Move.CROUCH:
			# Crouch_Fwd / Crouch_Idle are genuine matches, and so are the fox's
			# `sneak` / `sneaking` behind them. Told apart with the exact same
			# speed threshold WALKING uses for idle-versus-run -- rather than
			# inventing a second, crouch-only knob that could quietly drift out
			# of sync with the ground one -- since a low profile does not change
			# what counts as "moving".
			if player.horizontal_speed() > player.config.pawn.run_animation_speed_threshold:
				return _first_available_directional([&"Crouch", &"sneak", &"Walk", &"idle"])
			return _first_available([&"Crouch_Idle", &"sneaking", &"Idle", &"idle"])
		Move.JUMP:
			# A WALL KICK IS A JUMP, but not this one. The packs have a
			# WallRunJump clip and it was never wired up before this case
			# existed. The mechanism has been complete for a while --
			# WallRunMove.wall_jump_launch and the whole Noob/ProAdd skill
			# gradient -- and it hands off to JUMP, so the animator had no way
			# to tell it from stepping off a kerb.
			#
			# wall_side > 0 is a RIGHT-hand wall, so _R is the clip for pushing
			# off one on the right. Same naming guess as WallRun_L/R: taken
			# as the side of the WALL. If a kick reads mirrored, both lines flip
			# together.
			var jump_move = player.move_manager.move_for(Move.JUMP)
			var kick: int = jump_move.kick_side() if jump_move != null else 0
			if kick != 0:
				var kick_clip: StringName = &"WallRun_Jump_R" if kick > 0 else &"WallRun_Jump_L"
				return _first_available([kick_clip, &"WallRun_Jump_L", &"WallRun_Jump_R",
					&"Jump_Start", &"jump", &"idle"])
			# The TAKE-OFF, as against FALLING's airborne loop. This case
			# existing at all was a fix: without it a jump fell through to the
			# default below, whose list is idle-first, so a body with an idle
			# clip STOOD STILL through its own take-off while FALLING, one tick
			# later, correctly played a jump.
			return _first_available([&"Jump_Start", &"NinjaJump_Start", &"jump", &"idle"])
		Move.DODGE_JUMP:
			# UAL 1 has the pair, and they are named for the side the body
			# goes, not for anything it pushes off. Same naming guess as
			# WallRun_L/R above: if a dodge reads mirrored, flip both lines
			# together.
			#
			# The clip runs about four times as long as the move: a dodge
			# crosses enter_to_falling_z_speed in roughly 0.3 s and hands off
			# to FALLING. It is armed as a one-shot at entry so the airborne
			# loop cannot take the body back mid-clip -- see _arm_oneshot().
			return _first_available([_dodge_clip(), &"Dodge_Left", &"Dodge_Right",
				&"Jump_Start", &"jump", &"idle"])
		Move.FALL_UNCONTROLLED:
			# NO LONGER THE SAME AS AN ORDINARY FALL: LiftAir_Fall_Air is the
			# pack's own out-of-control descent, where Jump is a controlled
			# one with the legs under the body.
			#
			# THE _Air ONE, AND ONLY THAT ONE. The three LiftAir clips are not
			# a Start/Idle/Land set, despite what the names suggest. Measured,
			# as hip height over the clip:
			#
			#   LiftAir_Fall        0.96 -> 0.04   a KNOCKDOWN, ending on the
			#                                      floor. Not an entry at all.
			#   LiftAir_Fall_Air    0.19 -> 0.21   flat, looping: the descent
			#   LiftAir_Fall_Impact 0.19 -> 0.05   arriving
			#
			# DO NOT use LiftAir_Fall here: it collapses the body to floor
			# height in MID-AIR, reading as an impact playing once followed
			# by a loop of nothing -- it is a knockdown clip, not an entry.
			return _first_available([&"LiftAir_Fall_Air", &"Jump",
				&"NinjaJump_Idle", &"jump", &"idle"])
		Move.LANDING:
			# The hard landing nobody rolled out of: a two-second lockout spent
			# absorbing the impact low to the ground. Jump_Land is the impact
			# itself and is a genuine match for the first moment of it; the
			# crouch-still pose stands in for the rest, since the body is down
			# and not going anywhere. What this really wants is a stagger.
			return _first_available([&"Jump_Land", &"NinjaJump_Land", &"Crouch_Idle", &"sneaking", &"idle"])
		Move.LAY_ON_GROUND:
			# LiftAir_Fall is a KNOCK-DOWN, whatever its name: hips 0.96 ->
			# 0.04, ending on the floor (measured under FALL_UNCONTROLLED,
			# above, where it was the wrong clip for exactly that reason).
			# Neither clip loops, so each holds its last frame for as long as
			# its phase lasts.
			var lying: Move = player.move_manager.move_for(Move.LAY_ON_GROUND)
			if lying != null and lying.is_rising():
				return _first_available([&"KipUp", &"Crouch_Idle", &"sneaking", &"idle"])
			return _first_available([&"LiftAir_Fall", &"Death02", &"Crouch_Idle", &"sneaking", &"idle"])
		Move.COIL:
			# ✅ GroundSit_Idle, AND THE NAME IS A RED HERRING -- the owner
			# found it: "虽然听上去很怪但动作好像是抱膝". A coil is the legs
			# drawn up under the chin, and a hugging-the-knees sit is that
			# pose. Nothing in the packs is labelled as an airborne tuck.
			#
			# It loops (1.33 s), which is what a pose held for up to half a
			# second needs. ⚠️ NOT Roll, though a roll is the closer NAME:
			# measured, its hips sweep 0.055 -> 1.245 m across 1.47 s and it
			# does not loop, so as a loop it spins the body in mid-air and as a
			# one-shot it finishes early and puts the legs down while the
			# capsule is still shrunk.
			#
			# ⚠️ IT NEEDS A CLIP OFFSET AND WILL LOOK BROKEN WITHOUT ONE.
			# Measured over the clip, hips against the same skeleton:
			#
			#   GroundSit_Idle   0.068          <- sitting ON the floor
			#   Crouch_Idle      0.512          the previous placeholder
			#   Idle / Jump      0.948          standing reference
			#
			# So played untouched the body drops about 0.88 m, which is the
			# same failure LiftAir_Fall produced in mid-air (see
			# Move.FALL_UNCONTROLLED below). The correction belongs in
			# BodyProfile.clip_offsets, keyed by clip and tuned per body with
			# scripts/debug/clip_offset_tuner.gd -- not hardcoded here, because
			# the number is a function of the skeleton and every model has its
			# own.
			#
			# Crouch_Idle stays in the chain behind it: GroundSit_Idle is in
			# UAL1's FULL tier only, and the tracked free packs must still
			# produce something (see FULL-LIBRARY.md).
			return _first_available([&"GroundSit_Idle", &"Crouch_Idle",
				&"sneaking", &"Jump", &"NinjaJump_Idle", &"jump", &"idle"])
		Move.SKILL_ROLL:
			# A GENUINE MATCH: UAL1 ships a Roll.
			return _first_available([&"Roll", &"Jump_Start", &"jump", &"idle"])
		Move.INTO_GRAB:
			# Climb_Enter is the reach onto a ledge -- the arriving half of
			# UAL1's hang set, which is what this move is. Behind it, the old
			# PLACEHOLDER reasoning: airborne and committed, so a take-off.
			return _first_available([&"Climb_Enter", &"Jump_Start", &"jump", &"idle"])
		Move.WALL_CLIMB:
			# ClimbUp_2m, on the measurement: this project's wall climb rises
			# 1.69 m, which is most of the way to the 2 m clip and half again
			# the 1 m one. ClimbUp_1m stays as the fallback it always was.
			return _first_available([&"ClimbUp_2m", &"ClimbUp_1m", &"Jump_Start", &"jump", &"idle"])
		Move.TURN_180:
			# Not really a body move -- the view swings and the facing follows,
			# while whatever the legs were doing continues. So it borrows the
			# same speed split WALKING uses rather than claiming a clip of its
			# own.
			# ALWAYS THE RIGHT-HAND CLIP, because the move only ever turns one
			# way: Turn180Move sets _turn_to = _turn_from - PI unconditionally.
			# [ME:CONFIRMED] Faith only ever turns right in the original,
			# measured directly. Godot's yaw grows counter-clockwise, so that
			# subtraction is clockwise, which is rightward. Turn180_L is wired
			# into the graph and never asked for.
			# Same naming guess as the wall run: _R read as "turns right".
			if _has_clip(&"Turn180_R"):
				return &"Turn180_R"
			var turn_speed: float = player.horizontal_speed()
			if turn_speed > _run_band_speed():
				return _first_available([&"Sprint", &"Walk", &"run", &"idle"])
			if turn_speed > player.config.pawn.run_animation_speed_threshold:
				return _first_available([&"Walk", &"Sprint", &"run", &"idle"])
			return _first_available([&"Idle", &"idle", &"Walk", &"run"])
		Move.BALANCE:
			# The wobble is carried entirely by the camera roll and the
			# skeleton lean (BalanceLean) -- the body itself is just walking.
			# [ME:CONFIRMED 05 §5.6] the beam speed is 8.81 km/h, so Walk is
			# the honest clip. The owner ruled out the packs' lean variants
			# (Jog_Fwd_LeanL/R): those are authored for leaning into a
			# full-speed run, which this is not.
			#
			# STANDING STILL IS STILL STANDING. The beam's own wind keeps the
			# lean moving whether or not the player is walking, so routing on
			# the move being active alone leaves a walk cycle playing under a
			# body that is going nowhere.
			var beam = player.move_manager.move_for(Move.BALANCE)
			if beam != null and not beam.travelling():
				return _first_available([&"Idle", &"idle", &"Walk"])
			return _first_available([&"Walk", &"Idle", &"idle"])
		Move.LEDGE_WALK:
			# Direction-aware, off the Walk family's own _L/_R suffixes (see
			# DIRECTION_SETS). UAL2's Walk_L / Walk_R are a walking-cadence
			# sidestep, which is exactly what shuffling a ledge with your
			# back to the wall is.
			var ledge = player.move_manager.move_for(Move.LEDGE_WALK)
			# TURNING ROUND on a view change: the pack's own half turn, on the
			# side the body pivots to, fitted to LedgeWalkConfig.turn_time
			# through scripted_duration(). Both turn clips are in
			# Player.SCRIPTED_MOVE_CLIPS, so _route() puts them on a scripted
			# slot like any other one-shot.
			if ledge != null and ledge.is_turning():
				var wanted: StringName = ledge.turn_clip()
				var other: StringName = &"Turn180_L" if wanted == &"Turn180_R" else &"Turn180_R"
				return _first_available([wanted, other, &"Idle", &"idle"])
			var dir: int = ledge.shuffle_direction() if ledge != null else 0
			if dir < 0:
				return _first_available([&"Walk_L", &"Walk", &"idle"])
			if dir > 0:
				return _first_available([&"Walk_R", &"Walk", &"idle"])
			return _first_available([&"Idle", &"Walk", &"idle"])
		_:
			# Any move without an explicit case above. Reaching here is a
			# signal that a move was added without deciding what it looks
			# like -- prefer adding a case, even one that returns idle with a
			# comment, over relying on this. Every Move that existed when this
			# was written has one; a new arrival landing here is the point.
			return _first_available([&"Idle", &"idle", &"run", &"jump"])

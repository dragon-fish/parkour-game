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
## Derived the same way the walk's is. The jog only ever plays SIDEWAYS or
## BACKWARD here (see Move.WALKING), so its range is the run band: from
## _run_band_speed() at the bottom to the full ground speed at the top. Setting
## its reference to the bottom of that band puts it at 1.0 where the band starts
## and at SPEED_SCALE_MAX where it ends, which is the whole of the range and no
## more.
##
## DO NOT measure the jog against the same 7.2 reference the run uses: a jog
## covering 7.2 m/s would then play at 1.0, and the stride has to be enormous
## to cover that much ground at a jogging cadence.
const JOG_REFERENCE_PCT := 0.5

## The packs' EIGHT-WAY sets, as suffixes clockwise from straight ahead.
##
## THE TWO PACKS DO NOT AGREE ON THE SIDE NAMES. UAL1 spells them Left and
## Right (Jog_Left, Crouch_Right); UAL2 spells them L and R (Walk_L, Walk_R).
## Nothing derives one from the other -- each family carries its own table, and
## a family added later has to be read off the gallery rather than guessed.
##
## There is NO eight-way Sprint in either pack, which is why Move.WALKING sends
## the sideways and backward octants to the jog and keeps the sprint for
## straight ahead.
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
func _route(target: StringName, delta: float) -> void:
	if Player.SCRIPTED_MOVE_CLIPS.has(target):
		# ARMED FOR THE NEXT ORDINARY CLIP, every tick a scripted one is wanted,
		# so the hold measures how long the ORDINARY target has persisted rather
		# than how long ago the slot was claimed.
		_hold_left = _hold_time()
		_hidden_start = &""
		# ALREADY ON SCREEN -- and this is the common case, since the drive runs
		# every tick for the whole of a move. Re-requesting the input the gate is
		# showing would re-enter it, and the slots reset on entry.
		if _gate_input == _slot_name() and _slot_clip() == target:
			return
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
	Move.FALLING, Move.JUMP, Move.FALL_UNCONTROLLED, Move.COIL,
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
	_oneshot = Move.KEEP
	_oneshot_left = 0.0
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
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if travel.length_squared() < 0.04:
		return -1
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return -1
	facing = facing.normalized()
	# Positive to the RIGHT of the facing, the same axis Player._drive_body_yaw()
	# builds for the torso twist -- for a facing of -Z this cross product is +X.
	var right: Vector3 = facing.cross(Vector3.UP)
	travel = travel.normalized()
	var angle: float = atan2(travel.dot(right), travel.dot(facing))
	return posmod(int(round(angle / (PI / 4.0))), 8)

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
		# TWO DEATHS, and the fall is the odd one out.
		#
		# [ME:CONFIRMED] The original has a single death animation and it is
		# this second branch -- cut up, or shot. Dying to a fall there is a
		# bone-crack and an immediate cut to black. The falling performance is
		# this project's own addition, so it is the branch that needs the
		# special clip; everything else gets the one death the library has.
		#
		# READ FROM death_cause, NOT from the move name: a fatal landing hands
		# the machine back to WALKING before this ever runs. See Player.
		if player.death_cause == Player.DeathCause.FALL:
			# UAL2's own long fall family, not a generic Death02: this branch is
			# a body still falling, not a body giving way.
			#
			# DO NOT use LiftAir_Fall_Impact for the death clip: it reads as a
			# violent full-body convulsion, not a body settling into a fall. It
			# is the arrival -- a body hitting the ground and convulsing -- and
			# played as the whole death it thrashes rather than lands.
			# LiftAir_Fall is the fall itself, which settles.
			#
			# The clip offset and the death eye lift were both tuned against
			# Impact (0.1 m on the model, 0.4 m on the eye) and neither
			# transfers: the two clips put the hips in different places. They
			# are the owner's to re-dial -- F9 for the model, F1 for the eye.
			return _first_available([&"LiftAir_Fall", &"Death02", &"Death01",
				&"sneaking", &"Crouch_Idle", &"idle"])
		# Death02 is UAL1's full library, i.e. PRIVATE. Death01 ships with the
		# repo, so a clone without the private submodule still dies properly.
		# Each clip puts the hips somewhere different, so this branch will want
		# its own offsets in scenes/player/tuning/ once it can be seen.
		return _first_available([&"Death02", &"Death01", &"LiftAir_Fall",
			&"sneaking", &"Crouch_Idle", &"idle"])
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
			if _creeping():
				return _first_available_directional([&"Walk", &"Walk_Carry", &"Sprint", &"run", &"idle"])
			var speed: float = player.horizontal_speed()
			if speed > _run_band_speed():
				# SPRINT AHEAD, JOG TO THE SIDES AND BEHIND.
				#
				# Neither pack has an eight-way sprint -- Sprint is one clip,
				# forward only -- and the eight-way sets are the jog's and the
				# walk's. So the run band is split by DIRECTION rather than run
				# on one clip: straight ahead is the sprint the owner asked for,
				# and everything else takes the jog, which is the only thing
				# that can strafe at all.
				#
				# This extends "do not use the jog" (which was about the
				# forward run) to the sideways case, where a reversed or
				# rotated sprint is the only alternative and there is no
				# eight-way sprint to use instead. The seam is a change of
				# cadence when turning sharply out of a straight run.
				if _travel_octant() <= 0:
					return _first_available([&"Sprint", &"Jog_Fwd", &"Walk_Fwd", &"run", &"idle"])
				return _first_available_directional([&"Jog", &"Walk", &"Sprint", &"run", &"idle"])
			if speed > player.config.pawn.run_animation_speed_threshold:
				return _first_available_directional([&"Walk", &"Walk_Carry", &"Sprint", &"run", &"idle"])
			return _first_available([&"Idle", &"Idle_FoldArms", &"idle", &"Walk"])
		Move.FALLING:
			# `Jump` is the pack's AIRBORNE LOOP (Jump_Loop, with the suffix
			# stripped on merge), which is what a fall is. It led with the fox's
			# `jump` before, which is a whole take-off-to-landing clip.
			return _first_available([&"Jump", &"NinjaJump_Idle", &"jump", &"Idle", &"idle"])
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
		Move.SLIDE:
			# A GENUINE MATCH: UAL2 ships Slide_Start / Slide / Slide_Exit. This
			# case is the middle one only -- the two ends are one-shots, armed
			# by _arm_oneshot() at the transitions into and out of the move,
			# because neither end is a state the player spends time in.
			# Everything after Slide is the old PLACEHOLDER reasoning: a slide
			# is fast, committed ground momentum, so a run is the closest thing.
			return _first_available([&"Slide", &"Sprint", &"run", &"idle"])
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
		_:
			# Any move without an explicit case above. Reaching here is a
			# signal that a move was added without deciding what it looks
			# like -- prefer adding a case, even one that returns idle with a
			# comment, over relying on this. Every Move that existed when this
			# was written has one; a new arrival landing here is the point.
			return _first_available([&"Idle", &"idle", &"run", &"jump"])

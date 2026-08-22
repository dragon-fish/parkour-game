class_name CharacterAnimator
extends Node

# Small REFERENCE driver: reads the player's movement state every physics
# tick and asks the AnimationTree's state machine to travel() to the
# matching clip. See the per-move comments in _target_animation() below for
# what maps to what, and _first_available()'s own comment for why every one
# of those mappings is really a PRIORITY LIST, not a single name.
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
const GRAPH_TIME_SCALE := &"speed"

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
## ⚠️ The one knob here. If the walk looks like it is hurrying or dawdling,
## this is the number -- and moving it moves the handover with it, which is
## the point.
const WALK_REFERENCE_PCT := 0.25

## Assigned in player.gd's _wire_body_animation().
@export var anim_tree: AnimationTree
## Assigned in player.gd's _wire_body_animation().
@export var player: Player

var _playback: AnimationNodeStateMachinePlayback
## The graph itself, cached alongside _playback so _has_clip() below never
## has to re-fetch anim_tree.tree_root every tick for every candidate.
var _graph: AnimationNodeStateMachine

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

func _ready() -> void:
	if anim_tree == null:
		return
	# One level deeper than it used to be: the state machine now sits inside a
	# blend tree so the whole graph can be time-scaled. See
	# player.gd's _wire_body_animation() for why, and _drive_speed() below for
	# what drives it.
	_playback = anim_tree.get("parameters/%s/playback" % GRAPH_STATES)
	var blend_tree := anim_tree.tree_root as AnimationNodeBlendTree
	if blend_tree != null:
		_graph = blend_tree.get_node(GRAPH_STATES) as AnimationNodeStateMachine

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
	_playback.travel(target)
	_drive_speed(target)

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
	Move.FALLING, Move.JUMP, Move.FALL_UNCONTROLLED,
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
		# NOT INTO A CROUCH. ✅ The owner settled this for the blend times
		# already -- a slide into a crouch is continuous, the body simply stays
		# down, while a slide into a run is the picking-yourself-up. Slide_Exit
		# is a stand-up, so it belongs only to the second.
		if to != Move.CROUCH:
			_start_oneshot(&"Slide_Exit")
		return
	if _AIRBORNE_MOVES.has(from) and to == Move.WALKING:
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
	return anim_player.get_animation(clip).length

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
	if CROUCHED_CLIPS.has(base_clip):
		reference *= player.config.pawn.crouched_pct
	elif WALK_CLIPS.has(base_clip):
		reference *= WALK_REFERENCE_PCT
	if reference > 0.0 and SPEED_MATCHED_CLIPS.has(base_clip):
		# travel_speed(), NOT horizontal_speed() -- see travel_speed()'s own
		# note on why velocity lies through a vault or a mantle. The eye already
		# reads it for the same reason.
		# A LOWER FLOOR FOR THE WALK, and it is derived rather than picked: the
		# creep is 0.5 m/s against a walk authored near 1.8, so the honest scale
		# there is 0.28 and the ordinary 0.5 floor would run the feet at 0.9 m/s
		# under a body doing 0.5. SPEED_SCALE_MIN exists to stop ONE clip being
		# stretched across everything; a walk asked to walk slowly is not that.
		var scale_min := SPEED_SCALE_MIN
		if WALK_CLIPS.has(base_clip):
			scale_min = minf(SPEED_SCALE_MIN, player.config.pawn.walk_velocity / reference)
		scale = clampf(player.travel_speed() / reference, scale_min, SPEED_SCALE_MAX)
	anim_tree.set("parameters/%s/scale" % GRAPH_TIME_SCALE, scale)

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
func _moving_backward() -> bool:
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if travel.length_squared() < 0.04:
		return false
	var facing: Vector3 = -player.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return false
	return travel.normalized().dot(facing.normalized()) < -0.5

## _first_available(), but preferring each candidate's REVERSED twin while the
## body is backpedalling. Falls through to the forward clip whenever the twin is
## missing, so a body with no reversible clips behaves exactly as before.
func _first_available_directional(candidates: Array[StringName]) -> StringName:
	if not _moving_backward():
		return _first_available(candidates)
	for candidate in candidates:
		var backward := StringName(String(candidate) + Player.BACKWARD_SUFFIX)
		if _has_clip(backward):
			return backward
		if _has_clip(candidate):
			return candidate
	return Move.KEEP

## Maps the player's current movement state onto a priority list of clips,
## then resolves that list against whatever the attached body actually has.
func _target_animation() -> StringName:
	# THE PACKS COME FIRST, the fox's own six names come last.
	#
	# The order used to be the other way round for a simple historical reason:
	# `run`/`idle`/`jump`/`sneak`/`sneaking`/`ladder_stillness` were the only
	# vocabulary this project had, and the packs were bolted on behind them. The
	# owner has now settled the direction -- the fox is on its way out and the
	# Universal Animation Library is what bodies will actually carry -- so the
	# pack name is the intended clip everywhere and the fox name is the fallback
	# that keeps the existing fox scenes working.
	#
	# ⚠️ ONE EXCEPTION, and it is deliberate: the GRAB hang still leads with
	# `ladder_stillness`, because a genuine match outranks this ordering. The
	# packs have nothing for hanging off a ledge; the fox has exactly that.
	#
	# NO Jog_Fwd ANYWHERE. The owner: Sprint is the run, do not use the jog.
	# It is gone from the routing, from SPEED_MATCHED_CLIPS, and from the clips
	# Player wires into the graph at all -- left in any of those it would come
	# back the next time a list was reordered.
	match player.move_manager.current_name:
		Move.WALKING:
			# THREE BANDS, not two. The free tier has a genuine Walk and the
			# owner asked for it to be used, which also closes the hole the
			# Sprint swap opened: below the run's scale floor a sprint was being
			# played in slow motion, because one clip was covering the whole
			# range from a crawl to full pace.
			# CTRL IS THE WALK, and it is the reason this case is not a plain
			# speed split. ✅ The owner: "we already have the Ctrl walk -- that
			# IS the walk." It was playing a STANDING IDLE: the modifier caps
			# the body at walk_velocity, 0.5 m/s, and the idle-versus-moving
			# threshold sits at 1.0, so a creep never reached the moving branch
			# at all. Feet still, body drifting.
			#
			# Asked of the INPUT rather than the speed, so there is no second
			# epsilon to keep in step with the first: Ctrl held with a direction
			# asked for is a walk, whatever the body has actually reached yet.
			# Ctrl held while standing still falls through to idle below.
			if _creeping():
				return _first_available_directional([&"Walk", &"Walk_Carry", &"Sprint", &"run", &"idle"])
			var speed: float = player.horizontal_speed()
			if speed > _run_band_speed():
				return _first_available_directional([&"Sprint", &"Walk", &"Walk_Carry", &"run", &"idle"])
			if speed > player.config.pawn.run_animation_speed_threshold:
				return _first_available_directional([&"Walk", &"Walk_Carry", &"Sprint", &"run", &"idle"])
			return _first_available([&"Idle", &"Idle_FoldArms", &"idle", &"Walk"])
		Move.FALLING:
			# `Jump` is the pack's AIRBORNE LOOP (Jump_Loop, with the suffix
			# stripped on merge), which is what a fall is. It led with the fox's
			# `jump` before, which is a whole take-off-to-landing clip.
			return _first_available([&"Jump", &"NinjaJump_Idle", &"jump", &"Idle", &"idle"])
		Move.SLIDE:
			# A GENUINE MATCH: UAL2 ships Slide_Start / Slide / Slide_Exit. This
			# case is the middle one only -- the two ends are one-shots, armed
			# by _arm_oneshot() at the transitions into and out of the move,
			# because neither end is a state the player spends time in.
			# Everything after Slide is the old PLACEHOLDER reasoning: a slide
			# is fast, committed ground momentum, so a run is the closest thing.
			return _first_available([&"Slide", &"Sprint", &"run", &"idle"])
		Move.SPEED_VAULT:
			# NO LONGER A PLACEHOLDER, and this was the biggest gap in the file.
			# SafetyVault is a one-handed plant over an obstacle, which is the
			# move exactly. Everything behind it is the old reasoning: a vault
			# is a short airborne burst, so the take-off half of a jump is the
			# closest thing a body without the paid pack has.
			return _first_available([&"SafetyVault", &"Jump_Start", &"NinjaJump_Start", &"jump", &"idle"])
		Move.GRAB:
			# Two phases share this one move (see GrabMove's own header
			# comment): hanging (frozen, waiting on input) and mantling (a
			# scripted climb onto the top). They are told apart here via
			# GrabMove.is_mantling(), the same way test_arena.gd reads
			# SlideMove.is_crawling() to see inside a move from the outside.
			var grab_move = player.move_manager.move_for(Move.GRAB)
			if grab_move != null and grab_move.is_mantling():
				# ClimbLedge over ClimbUp_1m, and the two are not the same
				# action: ClimbUp_* starts from STANDING at the foot of a wall,
				# while ClimbLedge belongs to UAL1's hang set -- pulling up
				# from the Climb_Idle this move's other branch plays. A mantle
				# arrives already hanging, so it is the second.
				# ⚠️ Judged from the names and the company they keep, not from
				# watching them. The gallery shows both.
				return _first_available([&"ClimbLedge", &"ClimbUp_1m", &"Jump_Start", &"jump", &"idle"])
			# Climb_Idle is UAL1's hang, and it is now here -- the comment
			# that used to stand at this line said it was "behind the paid
			# tier", which it no longer is. The fox's `ladder_stillness` keeps
			# second place: it was the genuine match while it was the only one,
			# and it still is for a body that has it.
			return _first_available([&"Climb_Idle", &"ladder_stillness", &"NinjaJump_Idle", &"Jump", &"jump", &"idle"])
		Move.WALL_RUN:
			# THE DAY HAS ARRIVED. WallRun_L/R are the real thing, and Player
			# has been tracking wall_side for the torso twist all along, so
			# picking between them costs nothing new.
			#
			# wall_side > 0 is a RIGHT-hand wall -- WallRunMove's own look-fan
			# code says so at the line that reads `span if wall_side > 0`.
			#
			# ⚠️ WHICH WAY ROUND THE CLIPS ARE NAMED IS A GUESS: _L could mean
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
				return _first_available_directional([&"Crouch_Fwd", &"sneak", &"Walk", &"idle"])
			return _first_available([&"Crouch_Idle", &"sneaking", &"Idle", &"idle"])
		Move.JUMP:
			# The TAKE-OFF, as against FALLING's airborne loop. This case
			# existing at all was a fix: without it a jump fell through to the
			# default below, whose list is idle-first, so a body with an idle
			# clip STOOD STILL through its own take-off while FALLING, one tick
			# later, correctly played a jump.
			return _first_available([&"Jump_Start", &"NinjaJump_Start", &"jump", &"idle"])
		Move.FALL_UNCONTROLLED:
			# The same fall FALLING is, minus the control. Nothing in the free
			# tier distinguishes a flail from a fall, so it reads as one until
			# something does.
			return _first_available([&"Jump", &"NinjaJump_Idle", &"jump", &"idle"])
		Move.LANDING:
			# The hard landing nobody rolled out of: a two-second lockout spent
			# absorbing the impact low to the ground. Jump_Land is the impact
			# itself and is a genuine match for the first moment of it; the
			# crouch-still pose stands in for the rest, since the body is down
			# and not going anywhere. ⚠️ What this really wants is a stagger.
			return _first_available([&"Jump_Land", &"NinjaJump_Land", &"Crouch_Idle", &"sneaking", &"idle"])
		Move.SKILL_ROLL:
			# A GENUINE MATCH: UAL1 ships a Roll. This was once the weakest
			# placeholder in the file -- a ground tumble had no relative in the
			# fox's vocabulary at all, and `jump` stood in for being a committed
			# whole-body action rather than for resembling a roll.
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
			# way: Turn180Move sets _turn_to = _turn_from - PI unconditionally,
			# and its comment records the owner measuring exactly that in the
			# original -- "Faith only ever turns right". Godot's yaw grows
			# counter-clockwise, so that subtraction is clockwise, which is
			# rightward. Turn180_L is wired into the graph and never asked for.
			# ⚠️ Same naming guess as the wall run: _R read as "turns right".
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

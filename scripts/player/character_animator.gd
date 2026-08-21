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
const SPEED_MATCHED_CLIPS: Array[StringName] = [&"run", &"sneak"]

## Bounds on that scaling. Outside them the cadence stops reading as a pace and
## starts reading as a defect -- slow-motion at the bottom, blurred limbs at the
## top. A body slower than the lower bound has already crossed
## run_animation_speed_threshold into idle anyway.
const SPEED_SCALE_MIN := 0.5
const SPEED_SCALE_MAX := 2.0

## Assigned in player.gd's _wire_body_animation().
@export var anim_tree: AnimationTree
## Assigned in player.gd's _wire_body_animation().
@export var player: Player

var _playback: AnimationNodeStateMachinePlayback
## The graph itself, cached alongside _playback so _has_clip() below never
## has to re-fetch anim_tree.tree_root every tick for every candidate.
var _graph: AnimationNodeStateMachine

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

func _physics_process(_delta: float) -> void:
	if player == null or player.move_manager == null or _playback == null:
		return
	var target := _target_animation()
	# Move.KEEP (the same empty-StringName sentinel Move itself
	# uses for "stay put, nothing to do") means every candidate for this tick's
	# move came back missing from the attached body -- see _first_available().
	# There is nothing safe to travel() to, so skip the call entirely rather
	# than ask the graph for a name it does not have.
	if target == Move.KEEP:
		return
	_playback.travel(target)
	_drive_speed(target)

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
	if reference > 0.0 and SPEED_MATCHED_CLIPS.has(clip):
		# travel_speed(), NOT horizontal_speed() -- see travel_speed()'s own
		# note on why velocity lies through a vault or a mantle. The eye already
		# reads it for the same reason.
		scale = clampf(player.travel_speed() / reference, SPEED_SCALE_MIN, SPEED_SCALE_MAX)
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

## Maps the player's current movement state onto a priority list of clips,
## then resolves that list against whatever the attached body actually has.
func _target_animation() -> StringName:
	match player.move_manager.current_name:
		Move.WALKING:
			if player.horizontal_speed() > player.config.pawn.run_animation_speed_threshold:
				return _first_available([&"run", &"Walk_Carry", &"idle"])
			return _first_available([&"idle", &"run", &"Walk_Carry"])
		Move.FALLING:
			return _first_available([&"jump", &"NinjaJump_Idle", &"idle"])
		Move.SLIDE:
			# PLACEHOLDER for a future slide clip. None of the owner's reported
			# clips are a genuine match -- `climb`/`climbing` are prone,
			# crawling-on-the-ground poses, not a fast committed slide. A slide
			# is fast, committed ground momentum -- closest of what exists is
			# run.
			return _first_available([&"Slide", &"run", &"idle"])
		Move.SPEED_VAULT:
			# PLACEHOLDER for a future vault clip. A vault is a short airborne
			# burst clearing an obstacle -- closest of what exists is jump.
			return _first_available([&"jump", &"idle"])
		Move.GRAB:
			# Two phases share this one move (see GrabMove's own header
			# comment): hanging (frozen, waiting on input) and mantling (a
			# scripted climb onto the top). Only hanging has a genuine match in
			# the owner's reported vocabulary -- `ladder_stillness` is
			# "hanging on a ladder", which suits a ledge hang exactly -- so the
			# two phases are told apart here via GrabMove.is_mantling(),
			# the same way test_arena.gd already reads SlideMove.is_crawling()
			# to see inside a move from the outside.
			var grab_move = player.move_manager.move_for(Move.GRAB)
			if grab_move != null and grab_move.is_mantling():
				# MANTLE still has no real match: `climb`/`climbing` are prone,
				# ground-crawling poses, nothing like climbing up and onto a
				# ledge. Left on the same PLACEHOLDER reasoning the whole GRAB
				# move used to share -- a mantle is a short, committed,
				# ascending burst, so jump remains the closest of what exists --
				# unless a pack supplied a real one, which ClimbUp_1m is.
				return _first_available([&"ClimbUp_1m", &"jump", &"idle"])
			return _first_available([&"ladder_stillness", &"jump", &"idle"])
		Move.WALL_RUN:
			# PLACEHOLDER for a future wall-run clip. None of the owner's
			# reported clips fit a lateral run along a vertical surface.
			# Wall running is continuous, fast, directional locomotion along a
			# surface -- closest of what exists is run.
			return _first_available([&"run", &"idle"])
		Move.CROUCH:
			# `sneak`/`sneaking` are genuine matches from the owner's reported
			# vocabulary: crouch WALKING is `sneak`, crouch STILL is
			# `sneaking`. Told apart with the exact same speed-threshold idea
			# WALKING already uses for idle-versus-run -- reusing
			# run_animation_speed_threshold rather than inventing a second,
			# crouch-only knob that could quietly drift out of sync with the
			# ground one -- since a low profile does not change what counts as
			# "moving".
			if player.horizontal_speed() > player.config.pawn.run_animation_speed_threshold:
				return _first_available([&"sneak", &"run", &"idle"])
			return _first_available([&"sneaking", &"idle"])
		Move.JUMP:
			# Not a placeholder -- jump is the genuine match, and this case
			# existing at all is the fix. Without it a jump fell through to the
			# default below, whose list is idle-first, so a body with an idle
			# clip STOOD STILL through its own take-off while FALLING, one tick
			# later, correctly played jump.
			return _first_available([&"jump", &"NinjaJump_Start", &"run", &"idle"])
		Move.FALL_UNCONTROLLED:
			# The same fall FALLING is, minus the control. Nothing in the
			# reported vocabulary distinguishes a flail from a fall, so it reads
			# as one until something does.
			return _first_available([&"jump", &"idle"])
		Move.LANDING:
			# PLACEHOLDER. The hard landing nobody rolled out of: a two-second
			# lockout spent absorbing the impact low to the ground. `sneaking`
			# -- the crouch-still pose -- is the closest of what exists, since
			# the body is down and not going anywhere. Not a real match: this
			# wants a stagger.
			return _first_available([&"NinjaJump_Land", &"sneaking", &"sneak", &"idle"])
		Move.SKILL_ROLL:
			# PLACEHOLDER, and the weakest one here. A ground tumble has no
			# relative in the reported vocabulary at all. jump is chosen for
			# being a committed whole-body action rather than for resembling a
			# roll, which it does not.
			return _first_available([&"jump", &"run", &"idle"])
		Move.INTO_GRAB:
			# PLACEHOLDER. The reach itself, before the hands arrive -- airborne
			# and committed, so the same jump the GRAB mantle borrows.
			return _first_available([&"jump", &"idle"])
		Move.WALL_CLIMB:
			# PLACEHOLDER. A vertical kick up a wall: short, committed,
			# ascending. Exactly the reasoning that puts the GRAB mantle on jump
			# as well.
			return _first_available([&"ClimbUp_1m", &"jump", &"idle"])
		Move.TURN_180:
			# Not really a body move -- the view swings and the facing follows,
			# while whatever the legs were doing continues. So it borrows the
			# same speed split WALKING uses rather than claiming a clip of its
			# own.
			if player.horizontal_speed() > player.config.pawn.run_animation_speed_threshold:
				return _first_available([&"run", &"Walk_Carry", &"idle"])
			return _first_available([&"idle", &"run", &"Walk_Carry"])
		_:
			# Any move without an explicit case above. Reaching here is a
			# signal that a move was added without deciding what it looks
			# like -- prefer adding a case, even one that returns idle with a
			# comment, over relying on this. Every Move that existed when this
			# was written has one; a new arrival landing here is the point.
			return _first_available([&"idle", &"run", &"jump"])

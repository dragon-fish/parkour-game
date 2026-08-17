class_name CharacterAnimator
extends Node

# Small REFERENCE driver: reads the player's movement state every physics
# tick and asks the AnimationTree's state machine to travel() to the
# matching clip. See the per-state comments in _target_animation() below for
# what maps to what, and _first_available()'s own comment for why every one
# of those mappings is really a PRIORITY LIST, not a single name.
#
# WHY a priority list rather than one fixed name per state: the AnimationTree
# this class drives is built at runtime by player.gd's _wire_body_animation(),
# from whatever clips the ATTACHED body's AnimationPlayer actually has (see
# its own comment) -- and body_scene is optional and per-model, so nothing
# here may assume any particular clip, including idle/run/jump, exists.
# travel()ing to a name with no matching node in the graph is not a graceful
# no-op, it is a real engine error (verified directly -- see _has_clip()'s
# comment), which the test gate treats as a hard failure. _first_available()
# is what keeps every case below safe against that: it walks each state's
# candidates in priority order and returns the first one the attached body
# actually has, falling all the way through to PlayerState.KEEP -- "do
# nothing this tick" -- if the body has none of them at all.
#
# WHY travel() has to be called every tick rather than once on a state
# change: player.gd's _wire_body_animation() wires the state machine's
# Start/idle/run/End transitions with advance_mode = ENABLED, not AUTO. That
# is a deliberate fix, not a preserved default -- see that function's own
# comment for why AUTO cannot hold a state at all here. With ENABLED, nothing
# about the graph ever moves on its own, so re-issuing travel() every tick is
# what keeps the animation following the player instead of freezing at
# whatever it last was.

## Assigned in player.gd's _wire_body_animation().
@export var anim_tree: AnimationTree
## Assigned in player.gd's _wire_body_animation().
@export var player: Player

var _playback: AnimationNodeStateMachinePlayback
## The graph itself, cached alongside _playback so _has_clip() below never
## has to re-fetch anim_tree.tree_root every tick for every candidate.
var _graph: AnimationNodeStateMachine

func _ready() -> void:
	if anim_tree != null:
		_playback = anim_tree.get("parameters/playback")
		_graph = anim_tree.tree_root as AnimationNodeStateMachine

func _physics_process(_delta: float) -> void:
	if player == null or player.state_machine == null or _playback == null:
		return
	var target := _target_animation()
	# PlayerState.KEEP (the same empty-StringName sentinel PlayerState itself
	# uses for "stay put, nothing to do") means every candidate for this tick's
	# state came back missing from the attached body -- see _first_available().
	# There is nothing safe to travel() to, so skip the call entirely rather
	# than ask the graph for a name it does not have.
	if target == PlayerState.KEEP:
		return
	_playback.travel(target)

## True when `clip_name` has an actual node in the AnimationTree's graph --
## i.e., travel() can reach it without error. player.gd's
## _wire_body_animation() only ever adds a node for a clip the attached
## body's AnimationPlayer actually has, so this is really asking "does the
## ATTACHED BODY have this clip", one level removed.
func _has_clip(clip_name: StringName) -> bool:
	return _graph != null and _graph.has_node(clip_name)

## Returns the first of `candidates` that _has_clip(), in priority order --
## the highest-priority entry is the genuine, semantically-correct match for
## the calling state; every entry after it is a progressively less accurate
## but still-better-than-nothing fallback. Returns PlayerState.KEEP if the
## attached body (or the lack of one) has none of them.
func _first_available(candidates: Array[StringName]) -> StringName:
	for candidate in candidates:
		if _has_clip(candidate):
			return candidate
	return PlayerState.KEEP

## Maps the player's current movement state onto a priority list of clips,
## then resolves that list against whatever the attached body actually has.
func _target_animation() -> StringName:
	match player.state_machine.current_name:
		PlayerState.GROUND:
			if player.horizontal_speed() > player.config.run_animation_speed_threshold:
				return _first_available([&"run", &"idle"])
			return _first_available([&"idle", &"run"])
		PlayerState.AIR:
			return _first_available([&"jump", &"idle"])
		PlayerState.SLIDE:
			# PLACEHOLDER for a future slide clip. None of the owner's reported
			# clips are a genuine match -- `climb`/`climbing` are prone,
			# crawling-on-the-ground poses, not a fast committed slide. A slide
			# is fast, committed ground momentum -- closest of what exists is
			# run.
			return _first_available([&"run", &"idle"])
		PlayerState.VAULT:
			# PLACEHOLDER for a future vault clip. A vault is a short airborne
			# burst clearing an obstacle -- closest of what exists is jump.
			return _first_available([&"jump", &"idle"])
		PlayerState.LEDGE:
			# Two phases share this one state (see LedgeHangState's own header
			# comment): hanging (frozen, waiting on input) and mantling (a
			# scripted climb onto the top). Only hanging has a genuine match in
			# the owner's reported vocabulary -- `ladder_stillness` is
			# "hanging on a ladder", which suits a ledge hang exactly -- so the
			# two phases are told apart here via LedgeHangState.is_mantling(),
			# the same way test_arena.gd already reads SlideState.is_crawling()
			# to see inside a state from the outside.
			var ledge_state = player.state_machine.state_for(PlayerState.LEDGE)
			if ledge_state != null and ledge_state.is_mantling():
				# MANTLE still has no real match: `climb`/`climbing` are prone,
				# ground-crawling poses, nothing like climbing up and onto a
				# ledge. Left on the same PLACEHOLDER reasoning the whole LEDGE
				# state used to share -- a mantle is a short, committed,
				# ascending burst, so jump remains the closest of what exists.
				return _first_available([&"jump", &"idle"])
			return _first_available([&"ladder_stillness", &"jump", &"idle"])
		PlayerState.WALL:
			# PLACEHOLDER for a future wall-run clip. None of the owner's
			# reported clips fit a lateral run along a vertical surface.
			# Wall running is continuous, fast, directional locomotion along a
			# surface -- closest of what exists is run.
			return _first_available([&"run", &"idle"])
		PlayerState.CROUCH:
			# `sneak`/`sneaking` are genuine matches from the owner's reported
			# vocabulary: crouch WALKING is `sneak`, crouch STILL is
			# `sneaking`. Told apart with the exact same speed-threshold idea
			# GROUND already uses for idle-versus-run -- reusing
			# run_animation_speed_threshold rather than inventing a second,
			# crouch-only knob that could quietly drift out of sync with the
			# ground one -- since a low profile does not change what counts as
			# "moving".
			if player.horizontal_speed() > player.config.run_animation_speed_threshold:
				return _first_available([&"sneak", &"run", &"idle"])
			return _first_available([&"sneaking", &"idle"])
		_:
			# Any state without an explicit case above. Reaching here is a
			# signal that a state was added without deciding what it looks
			# like -- prefer adding a case, even one that returns idle with a
			# comment, over relying on this.
			return _first_available([&"idle", &"run", &"jump"])

class_name CharacterAnimator
extends Node

# Small REFERENCE driver: reads the player's movement state every physics
# tick and asks the AnimationTree's state machine to travel() to the
# matching clip. Deliberately covers only idle / run / jump -- see the
# per-state comments in _target_animation() below for how the states this
# project doesn't yet have a clip for are mapped onto those three, and
# extend that match statement rather than the shape of this class when a
# real move set arrives.
#
# WHY travel() has to be called every tick rather than once on a state
# change: tools/build_player_scene.gd wires the state machine's Start/idle/
# run/End transitions with advance_mode = ENABLED, not AUTO. That is a
# deliberate fix, not a preserved default -- see that file's own comment for
# why AUTO cannot hold a state at all here. With ENABLED, nothing about the
# graph ever moves on its own, so re-issuing travel() every tick is what
# keeps the animation following the player instead of freezing at whatever
# it last was.

## Assigned in tools/build_player_scene.gd.
@export var anim_tree: AnimationTree
## Assigned in tools/build_player_scene.gd.
@export var player: Player

var _playback: AnimationNodeStateMachinePlayback

func _ready() -> void:
	if anim_tree != null:
		_playback = anim_tree.get("parameters/playback")

func _physics_process(_delta: float) -> void:
	if player == null or player.state_machine == null or _playback == null:
		return
	_playback.travel(_target_animation())

## Maps the player's current movement state onto one of the three clips this
## reference animator knows about.
func _target_animation() -> StringName:
	match player.state_machine.current_name:
		PlayerState.GROUND:
			if player.horizontal_speed() > player.config.run_animation_speed_threshold:
				return &"run"
			return &"idle"
		PlayerState.AIR:
			return &"jump"
		PlayerState.SLIDE:
			# PLACEHOLDER for a future slide clip. A slide is fast, committed
			# ground momentum -- closest of the three is run.
			return &"run"
		PlayerState.VAULT:
			# PLACEHOLDER for a future vault clip. A vault is a short airborne
			# burst clearing an obstacle -- closest of the three is jump.
			return &"jump"
		PlayerState.LEDGE:
			# PLACEHOLDER for a future hang/mantle clip. Hanging and climbing is
			# an ascending, airborne action -- closest of the three is jump.
			return &"jump"
		PlayerState.WALL:
			# PLACEHOLDER for a future wall-run clip. Wall running is
			# continuous, fast, directional locomotion along a surface --
			# closest of the three is run.
			return &"run"
		_:
			return &"idle"

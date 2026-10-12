class_name Turn180Move
extends Move

# The original's TdMove_180Turn, the turn on the ground, ported.
# [ME:CONFIRMED decompile]
#
# A plain TdMove under the walking physics, from Walking only. The animation's
# root rotation turns the pawn half a turn clockwise -- RunTurn180 when the body
# is moving at all, StandTurn180Right from a standstill -- and the move lasts
# the animation (OnCustomAnimEnd sets Walking). Move input is ignored for
# DisableMovementTime, 0.3 s; FrictionModifier 0.3 is on for the whole move.
# The timer that ends the input lock turns the root rotation off and re-arms
# itself every 0.2 s until the animation ends. It shares Walking's row of the
# action table: a jump, a slide, a crouch all leave it.
#
# The view turns with the pawn (HalfTurn carries the look fan round), which is
# how this project presents a root rotation in first person.

var _turn: HalfTurn = HalfTurn.new()
var _clip: RootMotionClip = null
var _anim_time: float = 0.0

func is_ported() -> bool:
	return true

## TdMove_180Turn.CanDoMove: from Walking only, then the base's RedoMoveTime.
func can_do_move() -> bool:
	if player.move_manager.current_name != WALKING:
		return false
	return td_can_do_move()

func _init() -> void:
	# [ME:CONFIRMED ini] DisableMovementTime 0.3.
	disable_movement_time = 0.3

## TdMove_180Turn.StartMove.
func enter(_previous: StringName) -> void:
	var moving: bool = PawnPhysics.walking_state(player.horizontal_speed()) != PawnPhysics.WAS_IDLE
	_clip = RootMotionClip.run_turn_180() if moving else RootMotionClip.stand_turn_180()
	_anim_time = 0.0
	_turn.begin(player.pawn_yaw())
	player.use_root_rotation(true)
	set_timer(disable_movement_time)

## TdMove_180Turn.OnTimer: root rotation off, and again 0.2 s later, until
## the animation ends the move.
func on_timer() -> void:
	player.use_root_rotation(false)
	set_timer(0.2)

## The root rotation, while it is on, before the physics.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if player.root_rotation_active and _clip != null:
		_turn.advance(player, _clip.turn(_anim_time + delta) / PI)

## The animation's clock; its end is OnCustomAnimEnd, which sets Walking.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_anim_time += delta
	if _clip != null and _anim_time >= _clip.length:
		player.move_manager.set_move(WALKING)

## Which of the original's two clips is playing: true for the running turn.
func is_running_turn() -> bool:
	return _clip != null and is_equal_approx(_clip.length, 1.0333)

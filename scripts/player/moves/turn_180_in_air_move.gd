class_name Turn180InAirMove
extends PhysicsMove

# The original's TdMove_180TurnInAir, ported. [ME:CONFIRMED decompile N5 §8]
#
# MA_Turn in the air (the action table's air row). PHYS_Falling with move
# input ignored, the crouched collision, and two automatic transitions -- the
# uncontrolled fall and the soft landing (the latter not while the root
# rotation is turning the pawn). JumpTurnFly's root rotation turns the pawn
# half a turn clockwise over 0.3 s. Stuck in mid-air against something for
# longer than 0.3 s, it lands where it is. Its landing is Landing's backwards
# one: Old == 180TurnInAir puts the body on its back.

var _turn: HalfTurn = HalfTurn.new()
var _clip: RootMotionClip = RootMotionClip.jump_turn_fly()
var _anim_time: float = 0.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	check_exit_to_uncontrolled_falling = true
	check_for_soft_landing = true
	use_custom_collision = true
	disable_movement_time = -1.0
	# [ME:CONFIRMED decompile] bDisableFaceRotation: the pawn holds its yaw
	# while the view turns (Player.face_rotation()).
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## TdMove_180TurnInAir.CanDoMove: not out of a soft landing, only moving
## roughly the way the pawn faces (normalised, >= 0.2), then the base.
func can_do_move() -> bool:
	if player.move_manager.current_name == SOFT_LANDING:
		return false
	var v_dir: Vector3 = player.velocity.normalized() if player.velocity.length_squared() > 0.0 else Vector3.ZERO
	if player.facing().dot(v_dir) < 0.2:
		return false
	return td_can_do_move()

func enter(_previous: StringName) -> void:
	_anim_time = 0.0
	_turn.begin(player.pawn_yaw)
	player.use_root_rotation(true)

## TdMove_180TurnInAir PrePhysics (0x0120c120): the TdPhysicsMove exits, then
## the stuck test. The root rotation is advanced first, as the animation does.
func pre_physics(delta: float) -> void:
	if player.using_root_rotation:
		_turn.advance(player, _clip.turn(_anim_time + delta) / PI)
		# OnCeaseRelevantRootMotion for JumpTurnFly turns it off. [ME:INFERRED]
		# when that event fires was not read; taken as the sequence's end.
		if _anim_time + delta >= _clip.length:
			player.use_root_rotation(false)
	super.pre_physics(delta)
	# Asked even when the base has just changed the move, as the original does.
	if move_active_time > 0.3 and player.velocity.length() < 0.1 * UU:
		player.move_manager.set_move(LANDING)

func tick_move(delta: float) -> void:
	super.tick_move(delta)
	_anim_time += delta

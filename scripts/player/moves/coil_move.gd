class_name CoilMove
extends PhysicsMove

# The original's TdMove_Coil, the tuck jump, ported. [ME:CONFIRMED decompile
# N5 §3, emulated]
#
# PHYS_Falling under the PlayerWalking controller, with the crouched
# collision (the feet stay put and the head comes down 58 uu) and one
# automatic transition: the uncontrolled fall. No grab, no vault, no wall --
# a coil that meets an edge it misjudged does not catch it. Before the physics
# every tick the body is lifted by TotalHeightBoost / HeightBoostDuration x dt
# (240 uu/s) until TotalHeightBoost is used up: a displacement, not a speed,
# so the apex rises 60 uu and the fall is unchanged. CoilTime is never read:
# the coil lasts until it lands (Landing) or falls too far.

## TdMove_Coil.HeightBoostLeft, metres.
var height_boost_left: float = 0.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_uncontrolled_falling = true
	use_custom_collision = true

func is_ported() -> bool:
	return true

## TdMove_Coil.CanDoMove: never out of Falling, never from a reach already
## dropping, only in the falling physics, at CoilMinTriggerSpeed along the
## pawn's facing (a 3D dot), and the base's RedoMoveTime.
func can_do_move() -> bool:
	if player.root_rotation_active:
		return false
	var state: StringName = player.move_manager.current_name
	if state == FALLING:
		return false
	if state == INTO_GRAB and player.velocity.y < 0.0:
		return false
	if player.physics != PHYS_FALLING:
		return false
	if player.pawn_facing().dot(player.velocity) < cfg.min_trigger_speed:
		return false
	return td_can_do_move()

func enter(_previous: StringName) -> void:
	height_boost_left = cfg.total_height_boost
	player.coil_capsule_held = true
	# What the landing's camera nod reads (Player.last_landing_coiled).
	player.coiled_since_ground = true

func exit() -> void:
	player.coil_capsule_held = false

## TdMove_Coil PrePhysics (0x0120bf70): the TdPhysicsMove exits, then the
## lift. Moved through the world, so a ceiling stops it; the last step is not
## trimmed, so the total is a whole number of frames' worth.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if height_boost_left > 0.0:
		var d: float = (cfg.total_height_boost / cfg.height_boost_duration) * delta
		height_boost_left -= d
		player.phys.move_actor(Vector3.UP * d)

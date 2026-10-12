class_name JumpMove
extends PhysicsMove

# The original's TdMove_Jump, ported. [ME:CONFIRMED decompile 15.7, N2 §6]
#
# The take-off replaces the vertical speed with BaseJumpZ (Pawn.JumpZ is never
# read), adds JumpAddXY along the facing only when the body is already moving
# forward, and remembers the horizontal speed it left with (PreJumpMomentum),
# which Landing later caps the landing speed against. The physics stays
# PHYS_Walking until StartJump switches it to Falling, which is what stamps
# EnterFallingHeight with the take-off height.
#
# With a ledge found by the jump press (Player.found_ledge) and within reach,
# the jump may instead fly the body straight onto the ledge (PHYS_Flying, a
# precise location, collision off) when its own arc would fall short. The
# arc's prediction uses the SCRIPT gravity, GetGravityZ(), which is half the
# gravity the integrator actually applies -- so it overestimates the height
# and takes the flight less often than the arithmetic suggests. That is the
# original's, kept.

## TdMove_Jump.PreJumpMomentum: |Velocity.xy| at the take-off. Written only
## here, read by Landing; it outlives the jump on purpose.
var pre_jump_momentum: float = 0.0
## TdMove_Jump.WantedJumpVelocity.
var wanted_jump_velocity: Vector3 = Vector3.ZERO
## [ME:CONFIRMED decompile] CanDoMoveTaserLimit: refused below this mobility.
const CAN_DO_MOVE_TASER_LIMIT := 0.5

## The move not yet ported that launched this jump itself, or empty for a jump
## the original's take-off made. Such a move (a wall kick, a slide jump) sets
## the velocity and hands to Jump; the original has a separate move for each
## of those launches, so Falling records it in Jump's place.
var legacy_launch_from: StringName = &""

## Which wall a legacy wall kick left, or 0. Read by CharacterAnimator to pick
## the wall-kick clip.
var _kick_side: int = 0

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_WALKING
	# [ME:CONFIRMED decompile N4 §2.5] bCheckExitToFalling at the default
	# ExitToFallingZSpeed, -400 uu/s; the grab / vault / wall-climb switches
	# are JumpConfig's.
	check_exit_to_falling = true

func is_ported() -> bool:
	return true

func kick_side() -> int:
	return _kick_side

## TdMove_Jump.CanDoMove. [ME:CONFIRMED decompile] RedoMoveTime 1.0 s from
## DefaultPawnMovement.ini; refused on an uncontrolled slide unless that is
## what the body is doing, and below the taser mobility limit.
func can_do_move() -> bool:
	if not td_can_do_move():
		return false
	if player.uncontrolled_slide and player.move_manager.current_name != RAMP_SLIDE:
		return false
	if player.mobility_multiplier() < CAN_DO_MOVE_TASER_LIMIT:
		return false
	return true

## TdMove_Jump.StartMove.
func enter(previous: StringName) -> void:
	legacy_launch_from = player.pending_legacy_launch
	player.pending_legacy_launch = &""
	_kick_side = player.recent_wall_side if previous == WALL_RUN else 0
	if player.camera_rig != null:
		player.camera_rig.kick_takeoff(player.horizontal_speed())
	if legacy_launch_from != &"":
		# The launch already happened, in the move that handed over.
		player.set_physics(PHYS_FALLING)
		return
	player.last_jump_location = player.global_position
	wanted_jump_velocity = player.velocity
	pre_jump_momentum = Vector2(wanted_jump_velocity.x, wanted_jump_velocity.z).length()
	var forward: Vector3 = player.facing()
	if forward.dot(player.velocity) > 10.0 * UU:
		wanted_jump_velocity += config.pawn.jump_add_xy * forward
	wanted_jump_velocity.y = config.pawn.base_jump_z * player.mobility_multiplier()
	wanted_jump_velocity += player.base_velocity
	if not player.found_ledge or not _ledge_assist():
		start_jump()

## The ledge assist. Returns true when the jump flies to the ledge instead.
func _ledge_assist() -> bool:
	var h: float = player.collision_half_height()
	var z_distance: float = player.move_ledge_location.y - (player.global_position.y - h)
	var move_normal_2d: Vector3 = -player.move_normal
	move_normal_2d.y = 0.0
	move_normal_2d = move_normal_2d.normalized() if move_normal_2d.length_squared() > 0.0 else Vector3.ZERO
	if not (z_distance < 112.0 * UU and move_normal_2d.dot(player.velocity.normalized()) > 0.7071):
		return false
	var level := Vector3(player.global_position.x, player.move_ledge_location.y, player.global_position.z)
	var to_ledge: Vector3 = player.move_ledge_location - level
	var time_to_ledge: float = Vector2(_project(to_ledge, move_normal_2d).x,
		_project(to_ledge, move_normal_2d).z).length()
	time_to_ledge -= player.collision_radius() / maxf(absf(move_normal_2d.x), absf(move_normal_2d.z))
	time_to_ledge -= 8.0 * UU
	time_to_ledge = maxf(time_to_ledge, 0.0)
	var along: Vector3 = _project(wanted_jump_velocity, -move_normal_2d)
	var along_speed: float = Vector2(along.x, along.z).length()
	if along_speed <= 0.0:
		return false
	time_to_ledge /= along_speed
	# GetGravityZ() as the script reads it: half the gravity the integrator
	# applies. [ME:CONFIRMED decompile N2 §6]
	var z_with_time: float = wanted_jump_velocity.y * time_to_ledge \
		- time_to_ledge * time_to_ledge * absf(player.gravity_z()) * 0.5
	if z_with_time >= z_distance:
		return false
	var target: Vector3 = player.move_ledge_location + Vector3.UP * (h + 2.0 * UU)
	var start := Vector3(player.global_position.x, target.y, player.global_position.z)
	if player.phys.trace_blocked(target, start, player.collision_extent()):
		return false
	player.set_physics(PHYS_FLYING)
	player.collide_world = false
	set_precise_location(target, wanted_jump_velocity.length())
	return true

static func _project(v: Vector3, onto: Vector3) -> Vector3:
	var sq: float = onto.length_squared()
	return onto * (v.dot(onto) / sq) if sq > 0.0 else Vector3.ZERO

## TdMove_Jump.StartJump: the physics goes to Falling, the velocity becomes the
## wanted one.
func start_jump() -> void:
	player.set_physics(PHYS_FALLING)
	player.velocity = wanted_jump_velocity

## TdMove_Jump.ReachedPreciseLocation: the flight is over; the jump proper
## starts from the ledge.
func reached_precise_location() -> void:
	player.collide_world = true
	start_jump()

## TdMove_Jump.StopMove: a flight that never arrived gives collision back and
## falls.
func exit() -> void:
	if not player.collide_world:
		player.collide_world = true
		player.set_physics(PHYS_FALLING)

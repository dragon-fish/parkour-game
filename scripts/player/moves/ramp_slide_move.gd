class_name RampSlideMove
extends PhysicsMove

# The original's TdMove_RumpSlide, the seated slide down a marked chute,
# ported. [ME:CONFIRMED decompile N5 §4, PrePhysics emulated]
#
# Entered only by the physics: a walking or falling tick whose floor or wall
# carries the uncontrolled-slide mark (the original's PhysMaterial property,
# this project's Probes.UNCONTROLLED_SLIDE_GROUP) raises bUncontrolledSlide,
# and TickSpecial sets this move with the CanDoMove check (MoveManager).
#
# PHYS_Falling at half gravity, with WalkableFloorZ raised to MinSlideFloorZ
# for the slide's length so the chute -- normal z 0.6 .. 0.9 -- is a wall to
# the falling physics, which slides the body down along it. On the frames the
# physics touched the chute, PrePhysics steers: a strafe hint pushes the
# velocity across the fall line by SideControl x sin(slope), and the speed is
# kept and capped at MaxSlideSpeed. Off the chute for 0.1 s with nothing
# within 150 uu below, it is a fall; a floor under 0.9 lands; a jump leaves.

## TdMove_RumpSlide.TimeFalling: how long the physics has not touched the
## chute.
var time_falling: float = 0.0
## TdMove_RumpSlide.bTouchedFallHeightVolume: a TdFallHeightVolume was
## touched during the slide. Landing reads it: only then does a hard landing
## out of the slide count as hard.
var touched_fall_height: bool = false
## TdMove_RumpSlide.OldFloorZ.
var _old_floor_z: float = 0.71

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	disable_movement_time = -1.0
	# [ME:CONFIRMED decompile] bDisableFaceRotation: the pawn holds its yaw
	# while the view turns (Player.face_rotation()).
	disable_face_rotation = true

func is_ported() -> bool:
	return true

## TdMove_RumpSlide.CanDoMove: the chute the physics found must be no flatter
## than MinSlideFloorZ and no steeper than normal z 0.6, then the base's
## RedoMoveTime.
func can_do_move() -> bool:
	var n: Vector3 = player.uncontrolled_slide_normal
	if n.y >= cfg.min_slide_floor_z:
		return false
	if n.y < 0.6:
		return false
	return td_can_do_move()

## TdMove_RumpSlide.StartMove: half gravity; the velocity down the fall line
## at InitialSpeedLoss of the arriving speed; the chute made unwalkable; and
## SetTimer(0), which runs OnTimer at once (the turn to face down the chute).
func enter(_previous: StringName) -> void:
	time_falling = 0.0
	player.gravity_modifier = cfg.gravity_modifier
	var n: Vector3 = player.uncontrolled_slide_normal
	# (N x down) x N: the fall line, |sin(slope)| long. Two cross products,
	# so the handedness of the axes does not change it.
	player.velocity = (n.cross(Vector3.DOWN)).cross(n) * player.velocity.length() * cfg.initial_speed_loss
	_old_floor_z = player.walkable_floor_z
	player.walkable_floor_z = cfg.min_slide_floor_z
	touched_fall_height = false
	set_timer(0.0)

func exit() -> void:
	player.walkable_floor_z = _old_floor_z
	player.gravity_modifier = 1.0
	# The stand-up window the presentation reads (Player.begin_slide_recovery()).
	player.begin_slide_recovery()

func touched_fall_height_volume() -> void:
	touched_fall_height = true

## TdMove_RumpSlide.StartSliding: SetPreciseRotation(Rotator(N x (N x Z)),
## AnimBlendTime) -- turn to face down the chute over 0.5 s.
func on_timer() -> void:
	var n: Vector3 = player.uncontrolled_slide_normal
	# N x (N x Z): downhill along the surface.
	var down: Vector3 = n.cross(n.cross(Vector3.UP))
	if Vector2(down.x, down.z).length_squared() < 1e-8:
		return
	set_precise_rotation(UE.dir_yaw(down), PRECISE_ROTATION_TIME)

## TdMove_RumpSlide.AnimBlendTime, the precise rotation's time.
const PRECISE_ROTATION_TIME := 0.5

## TdMove_RumpSlide PrePhysics (0x01208d70). [ME:CONFIRMED emulated] Only on
## the frames the physics touched the chute.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	# The model is the pawn, and freeze_visual_yaw holds it: it turns with the
	# precise rotation and nothing else.
	player.pin_visual_yaw(player.pawn_yaw)
	if not player.uncontrolled_slide:
		return
	var v: Vector3 = player.velocity
	var speed: float = v.length()
	var n: Vector3 = player.uncontrolled_slide_normal
	# N x (0,0,1) in the original's axes: across the slope, sin(slope) long,
	# and to the LEFT of the fall line.
	var side: Vector3 = Vector3.UP.cross(n)
	var ctrl := Vector3.ZERO
	if player.move_action_hint == MAH_LEFT:
		ctrl = side
	elif player.move_action_hint == MAH_RIGHT:
		ctrl = -side
	# The third case reads the PS3's tilt, 0 on a PC. [ME:INFERRED N5 §25.2]
	var steered: Vector3 = v + ctrl * (cfg.side_control * delta)
	player.velocity = PawnPhysics.safe_normal(steered) * minf(cfg.max_slide_speed, speed)
	# A slide is not a fall: the fall height is measured from here.
	if not touched_fall_height:
		player.enter_falling_height = player.collision_center().y

## TdMove_RumpSlide TickMove (0x011fa1c0): off the chute for more than 0.1 s
## with nothing in a 2 uu box 150 uu below, a fall.
func tick_move(delta: float) -> void:
	time_falling = 0.0 if player.uncontrolled_slide else time_falling + delta
	if time_falling > 0.1:
		var loc: Vector3 = player.collision_center()
		var probe := Vector3(2.0, 2.0, 2.0) * UU
		if not player.phys.trace_blocked(loc - Vector3.UP * 150.0 * UU, loc, probe):
			player.move_manager.set_move(FALLING)
		else:
			time_falling = 0.0
	super.tick_move(delta)

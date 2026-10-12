class_name AirBargeMove
extends BargeMove

# The original's TdMove_AirBarge, ported without damage. [ME:CONFIRMED
# decompile script TdMove_AirBarge, N5 §20]
#
# Melee in the air asks this before the flying kick: an interactable within
# 300 uu ahead (or half a second at the barge speed). Falling physics, the
# small cylinder, the look input off; for its first 0.25 s the body is lifted
# 60 uu (240 uu/s, the coil's lift) where the space above is free, and its
# upward speed is killed where it is not. Hitting something halves the
# velocity on the next frame. Landing plays AirBargeLand, whose root motion
# carries the body 115 cm on, and its end is Walking; an animation that ends in
# the air is Falling.

## The original's 1P sequence lengths, seconds. [ME:CONFIRMED anims]
const AIR_BARGE_IDLE_LENGTH := 1.0
const MELEE_IN_AIR_LENGTH := 0.567
const AIR_BARGE_IMPACT_LENGTH := 1.0
const AIR_BARGE_LAND_LENGTH := 0.5
## AirBargeLand's root, forward. [ME:CONFIRMED anims root_motion/AirBargeLand, 1P]
static var _land_root: RootMotionClip = RootMotionClip.from_track(&"airbargeland")
## The free-space test for the lift is made 30 uu above the centre.
const LIFT_TEST_RAISE := 30.0 * UU

var height_boost_left: float = 0.0
var pre_collision_velocity: Vector3 = Vector3.ZERO
var use_air_barge_anim: bool = false
var is_landing: bool = false
## Metres of AirBargeLand's root already handed to the physics.
var _root_applied: float = 0.0

func _init() -> void:
	super._init()
	# [ME:CONFIRMED decompile] bUseCustomCollision (Move.begin_move / end_move).
	use_custom_collision = true
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_uncontrolled_falling = true
	disable_look_time = -1.0

func enter(previous: StringName) -> void:
	player.set_grounded(false)
	super.enter(previous)

## TdMove_AirBarge.StartBargin. The surface flag that picks AirBargeIdle
## (TdPhysicalMaterialProperty.bShouldAirBarge) has no counterpart here, so it
## is always the plain kick.
func start_bargin() -> void:
	height_boost_left = cfg.total_height_boost
	is_landing = false
	reset_camera_look(0.3)
	use_air_barge_anim = false
	if use_air_barge_anim:
		_anim.play(&"AirBargeIdle", AIR_BARGE_IDLE_LENGTH)
	else:
		_anim.play(&"MeleeInAir", MELEE_IN_AIR_LENGTH)

## Native PrePhysics.
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if height_boost_left > 0.0:
		var d: float = (cfg.total_height_boost / cfg.height_boost_duration) * delta
		height_boost_left -= d
		var test: Vector3 = player.collision_center() + Vector3.UP * LIFT_TEST_RAISE
		if not player.phys.trace_blocked(test, test, player.collision_extent()):
			player.phys.move_actor(Vector3.UP * d)
		else:
			player.velocity.y = minf(player.velocity.y, 0.0)
	if pre_collision_velocity != Vector3.ZERO:
		player.velocity = pre_collision_velocity * 0.5
		pre_collision_velocity = Vector3.ZERO
	if is_landing:
		_apply_root_motion(delta)

## AirBargeLand's root motion, handed to the physics as this frame's root
## velocity (Player.use_root_motion(), PlayLanded's UseRootMotion(true)).
func _apply_root_motion(delta: float) -> void:
	if not player.root_motion_active or delta <= 0.0:
		return
	var t: float = minf(_anim.elapsed + delta, AIR_BARGE_LAND_LENGTH)
	var forward: float = _land_root.displacement(t).x
	var step: float = forward - _root_applied
	_root_applied = forward
	player.root_motion_velocity = player.facing() * (step / delta)

## TryGiveBargeDamage, without the damage: the first thing hit halves the
## velocity on the next frame.
func try_give_barge_damage(_normal: Vector3, _collider: Object) -> void:
	if is_landing or has_dealt_damage:
		return
	has_dealt_damage = true
	for entry in barge_actor_list:
		if is_interactable(entry["collider"]):
			pre_collision_velocity = player.velocity
	if use_air_barge_anim:
		_anim.play(&"AirBargeImpact", AIR_BARGE_IMPACT_LENGTH)

func landed(_normal: Vector3) -> void:
	play_landed()

func play_landed() -> void:
	is_landing = true
	_root_applied = 0.0
	player.use_root_motion(true)
	_anim.play(&"AirBargeLand", AIR_BARGE_LAND_LENGTH)

func on_custom_anim_end(anim_name: StringName) -> void:
	if anim_name == &"AirBargeLand":
		player.move_manager.set_move(WALKING)
	elif anim_name == &"AirBargeImpact":
		play_landed()
	else:
		player.move_manager.set_move(FALLING)

func abort_barge() -> void:
	player.move_manager.set_move(FALLING)

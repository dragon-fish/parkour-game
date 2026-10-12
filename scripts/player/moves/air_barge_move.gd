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
## AirBargeLand's root, cm forward, every 0.05 s. [ME:CONFIRMED anims
## root_motion/AirBargeLand, 1P]
const AIR_BARGE_LAND_ROOT := [0.0, 17.6, 38.1, 51.6, 62.6, 72.4, 81.5, 90.4, 98.8, 106.9, 115.4]
## The free-space test for the lift is made 30 uu above the centre.
const LIFT_TEST_RAISE := 30.0 * UU

var height_boost_left: float = 0.0
var pre_collision_velocity: Vector3 = Vector3.ZERO
var use_air_barge_anim: bool = false
var is_landing: bool = false
var _root_applied: float = 0.0

func _init() -> void:
	super._init()
	pawn_physics = PHYS_FALLING
	controller_state = CS_PLAYER_WALKING
	check_exit_to_uncontrolled_falling = true
	disable_look_time = -1.0

func enter(previous: StringName) -> void:
	player.set_grounded(false)
	CustomCollision.shrink(player)
	super.enter(previous)

func exit() -> void:
	super.exit()
	CustomCollision.enlarge(player)

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

## AirBargeLand's root motion. [ME:INFERRED] the original turns it into the
## velocity (RMM_Accel); the root-motion layer is not ported yet, so the body
## is carried along it directly and keeps no speed from it.
func _apply_root_motion(delta: float) -> void:
	var t: float = minf(_anim.elapsed + delta, AIR_BARGE_LAND_LENGTH)
	var x: float = t / 0.05
	var i: int = mini(int(x), AIR_BARGE_LAND_ROOT.size() - 2)
	var cm: float = lerpf(AIR_BARGE_LAND_ROOT[i], AIR_BARGE_LAND_ROOT[i + 1], x - float(i))
	var step: float = (cm - _root_applied) * UU
	_root_applied = cm
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.phys.move_actor(player.facing() * step)

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

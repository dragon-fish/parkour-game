class_name AirBargeMove
extends BargeMove

# The original's TdMove_AirBarge, ported. [ME:CONFIRMED decompile script
# TdMove_AirBarge, N5 §20]
#
# Melee in the air asks this before the flying kick: an interactable within
# 300 uu ahead (or half a second at the barge speed). Falling physics, the
# small cylinder, the look input off; for its first 0.25 s the body is lifted
# 60 uu (240 uu/s, the coil's lift) where the space above is free, and its
# upward speed is killed where it is not. Hitting something halves the
# velocity on the next frame. Landing plays AirBargeLand, whose root motion
# carries the body 115 cm on, and its end is Walking; an animation that ends in
# the air is Falling.

## The free-space test for the lift is made 30 uu above the centre.
const LIFT_TEST_RAISE := 30.0 * UU

var height_boost_left: float = 0.0
var pre_collision_velocity: Vector3 = Vector3.ZERO
var use_air_barge_anim: bool = false
var is_landing: bool = false

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
		play_slot_anim(&"AirBargeIdle", 1.0, 0.15, 0.15)
	else:
		play_slot_anim(&"MeleeInAir", 1.0, 0.15, 0.15)

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

## TryGiveBargeDamage: the first thing hit (HitWall or Bump) deals the barge
## to every interactable the trace found -- at the location of what was hit,
## not their own -- and halves the velocity on the next frame.
func try_give_barge_damage(normal: Vector3, collider: Object) -> void:
	if is_landing or has_dealt_damage:
		return
	has_dealt_damage = true
	var at: Vector3 = (collider as Node3D).global_position if collider is Node3D else player.global_position
	for entry in barge_actor_list:
		if is_interactable(entry["collider"]):
			hit_object(player, entry["collider"], at, normal)
			pre_collision_velocity = player.velocity
	player.anim_slot.stop(0.0)
	if use_air_barge_anim:
		play_slot_anim(&"AirBargeImpact", 1.0, 0.0, 0.1)

func landed(_normal: Vector3) -> void:
	play_landed()

## PlayLanded: AirBargeLand with root motion, which the slot hands the
## physics.
func play_landed() -> void:
	is_landing = true
	player.use_root_motion(true)
	play_slot_anim(&"AirBargeLand", 1.0, 0.1, 0.1, true)

func on_custom_anim_end(anim_name: StringName) -> void:
	if anim_name == &"AirBargeLand":
		player.move_manager.set_move(WALKING)
	elif anim_name == &"AirBargeImpact":
		play_landed()
	else:
		player.move_manager.set_move(FALLING)

func abort_barge() -> void:
	player.anim_slot.stop(0.5, UPPER_BODY)
	player.move_manager.set_move(FALLING)

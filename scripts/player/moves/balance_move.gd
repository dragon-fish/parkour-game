class_name BalanceMove
extends PhysicsMove

# The original's TdMove_Balance (MOVE_Balance 29): walking a balance beam.
# [ME:CONFIRMED decompile script TdMove_Balance.uc; PrePhysics 0x0120a280 and
# TickMove 0x011fa570 emulated, N5 §18]
#
# Taken every tick inside a balance volume from Walking, Crouch or Slide. The
# body walks (PHYS_Walking, SpeedModifier 0.34: 244.8 uu/s at most) along
# the beam; each tick after the physics it is pulled onto the line at
# 10 x speed / 300 per second and turned along it.
#
# BalanceFactor runs -1 (leaning left) .. 1 (right):
#   dBF/dt = (0.3 cam + 0.3 sin(BF pi / 2) + 1.5 strafe) x (1 + 2.5 min(v/300, 1))
# where cam is the view's yaw off the beam (+-8192 units = +-1) and strafe
# the stick (right positive). The sine pushes away from 0, so the balance is
# kept by steering AGAINST the lean. At the stop (+-1) the body has
# TimeToCounter, 0.8 s, to get back inside 0.9 or it falls off: the fall's
# root motion carries it off the side, and Falling follows 0.1 s after.
#
# The volume is a BALANCE InterestLine. [ME:INFERRED] The spline natives were
# not decompiled: the line's closest point and UNIT tangent stand in for
# FindClosestPointOnDSpline and GetSlopeOnSpline; the tangent's length enters
# the starting BalanceFactor, so a unit one is what keeps it small.

var volume: InterestLine = null
var current_param_on_curve: float = 0.0
var is_facing_forward: bool = true
var is_in_danger_mode: bool = false
var has_fallen: bool = false
var balance_factor: float = 0.0
var counter_timer: float = 0.0
## Nothing in the game writes it.
var external_force: float = 0.0

func _init() -> void:
	super._init()
	controller_state = CS_PLAYER_BALANCE_WALK
	disable_face_rotation = true
	disable_controller_facing_pawn_yaw_rotation = true
	avoid_ledges = false

func is_ported() -> bool:
	return true

func uses_view_rotation() -> bool:
	return true

func _balance_cfg() -> BalanceConfig:
	return cfg as BalanceConfig

## TdMove_Balance.CanDoMove: from Walking, Crouch or Slide.
func can_do_move() -> bool:
	var state: StringName = player.movement_state
	if state != WALKING and state != CROUCH and state != SLIDE:
		return false
	return td_can_do_move()

func _spline_at(location: Vector3) -> Dictionary:
	current_param_on_curve = volume.closest_offset(location)
	return volume.sample(current_param_on_curve)

## TdMove_Balance.StartMove.
func enter(_previous: StringName) -> void:
	var spline_direction: Vector3 = _spline_at(player.global_position)["tangent"]
	is_facing_forward = player.facing().dot(PawnPhysics.safe_normal(spline_direction)) > 0.0
	var along: Vector3 = spline_direction * (1.0 if is_facing_forward else -1.0)
	set_precise_rotation(UE.dir_yaw(along), 0.2)
	balance_factor = ((-0.2 if is_facing_forward else 0.2) * player.facing()).dot(UE.cross(spline_direction, Vector3.UP))
	external_force = 0.0
	has_fallen = false
	is_in_danger_mode = false

## TdMove_Balance.StopMove.
func exit() -> void:
	player.use_root_motion(false)
	player.face_rotation_time_left = 0.4
	if player.camera_rig != null:
		player.camera_rig.set_balance_lean(0.0, 0.0)

## UTdMove_Balance's native PrePhysics. [ME:CONFIRMED emulated 0x0120a280]
func pre_physics(delta: float) -> void:
	super.pre_physics(delta)
	if has_fallen or player.move_manager.current_move() != self:
		return
	var c: BalanceConfig = _balance_cfg()
	var f: Vector3 = player.facing()
	var control: float = clampf(player.acceleration.dot(UE.cross(f, Vector3.UP)) / UU, -1.0, 1.0)
	var grav: float = sin(balance_factor * PI * 0.5)
	var speed: float = 1.0 + c.speed_influence * minf(player.horizontal_speed() / (300.0 * UU), 1.0)
	var yaw: int = UE.normalize_axis(UE.yaw_units(player.rotation.y) - UE.yaw_units(player.pawn_yaw))
	var cam: float = clampf(float(yaw) / 8192.0, -1.0, 1.0)
	balance_factor = clampf(balance_factor + (c.camera_influence * cam + c.gravity_influence * grav
		+ c.control_influence * control + external_force) * speed * delta, -1.0, 1.0)
	if not is_in_danger_mode:
		if absf(balance_factor) >= 1.0:
			counter_timer = 0.0
			is_in_danger_mode = true
	else:
		counter_timer += delta
		if counter_timer > c.time_to_counter:
			falloff()
			return
		if absf(balance_factor) <= 0.9:
			is_in_danger_mode = false
	if player.camera_rig != null:
		player.camera_rig.set_balance_lean(deg_to_rad(-balance_factor * c.max_camera_roll_deg),
			absf(balance_factor) * c.fov_squeeze_deg)

## TdMove_Balance.Falloff: off the side the lean is to, by the fall's root
## motion.
func falloff() -> void:
	has_fallen = true
	player.set_physics(PHYS_FALLING)
	if balance_factor < 0.0:
		play_slot_anim(&"walkbalancefalloffleft", 1.0, 0.3, 0.3, true)
	else:
		play_slot_anim(&"walkbalancefalloffright", 1.0, 0.3, 0.3, true)
	player.use_root_motion(true)

func on_cease_relevant_root_motion() -> void:
	set_move_timer(0.1, false, _go_into_falling)

func _go_into_falling() -> void:
	player.move_manager.set_move(FALLING)

func hit_wall(_normal: Vector3, _collider: Object) -> void:
	player.anim_slot.stop(0.1)
	player.move_manager.set_move(LANDING)

## UTdMove_Balance's native TickMove. [ME:CONFIRMED emulated 0x011fa570] After
## the physics: onto the line at 10 x speed / 300 a second, turned along it.
func tick_move(delta: float) -> void:
	super.tick_move(delta)
	if has_fallen or player.move_manager.current_move() != self or volume == null \
			or not is_instance_valid(volume):
		return
	var here: Vector3 = player.global_position
	var sample: Dictionary = _spline_at(here)
	var closest: Vector3 = sample["position"]
	closest.y = here.y
	var t: Vector3 = sample["tangent"]
	if not is_facing_forward:
		t = -t
	t.y = 0.0
	t = t.normalized() if t.length_squared() > 1e-8 else t
	var speed: float = player.horizontal_speed() / (300.0 * UU)
	player.phys.move_actor((closest - here) * delta * 10.0 * speed)
	player.pawn_yaw = UE.godot_yaw(UE.dir_yaw(t))

## The volume's PawnLeavingVolume and PawnUpdate.
func volume_leaving(_line: InterestLine) -> void:
	if player.movement_state == BALANCE and not has_fallen:
		player.move_manager.set_move(WALKING)

func volume_pawn_update(line: InterestLine) -> bool:
	volume = line
	if can_do_move():
		player.move_manager.set_move(BALANCE)
		return true
	return false

## For the presentation: the lean, -1 left .. 1 right.
func signed_severity() -> float:
	return balance_factor

## For the animation: whether the body is walking along the beam.
func travelling() -> bool:
	return player.horizontal_speed() > 10.0 * UU

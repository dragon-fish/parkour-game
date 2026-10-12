extends ParkourTest

# The ground family of the faithful port (W2c): structural invariants and the
# original's own arithmetic, no tuning values. [ME:CONFIRMED decompile N5,
# N1 §4.2, N2 §2c]

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []
var _bodies: Array = []

func after_each() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			(body as Node).queue_free()
	_bodies.clear()
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()
	await step(1)

func _world() -> Dictionary:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(20)
	return world

## A box of `size` whose top is at `top_y`, centred on (x, z).
func _box(size: Vector3, centre_xz: Vector2, top_y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = Vector3(centre_xz.x, top_y - size.y * 0.5, centre_xz.y)
	_bodies.append(body)
	return body

func _flat_speed(player: Player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()

## TdMove_Slide.StopMove: Velocity / 2, on every way out.
func test_leaving_a_slide_halves_the_velocity() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.velocity = player.facing() * 6.0
	player.move_manager.set_move(Move.SLIDE)
	assert_eq(player.move_manager.current_name, Move.SLIDE, "the slide did not start")
	var before: Vector3 = player.velocity
	player.move_manager.set_move(Move.CROUCH)
	assert_almost_eq(player.velocity.length(), before.length() * 0.5, 0.0001,
		"the slide's StopMove did not halve the speed")

## Move input is ignored for the whole slide, so CalcVelocity brakes:
## dV/dt = -2 * BrakingFrictionStrength * GroundFriction * 0.1 * V = -0.8 V on
## the flat, applied once per 1/60 s frame (one 30 ms slice).
func test_a_slide_on_the_flat_brakes_at_0_8_per_second() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	# Held, or the key's release ends the slide when it stops going in.
	input.press_crouch()
	player.velocity = player.facing() * 6.0
	player.move_manager.set_move(Move.SLIDE)
	await step(1)
	var v0: float = _flat_speed(player)
	await step(30)
	assert_eq(player.move_manager.current_name, Move.SLIDE, "the slide ended early")
	var expected: float = v0 * pow(1.0 - 0.8 / 60.0, 30)
	assert_almost_eq(_flat_speed(player), expected, 0.05,
		"the slide does not brake at the slide friction's 0.8/s")

## TdMove_Slide.ShouldAbort: the hint back aborts to Crouch.
func test_holding_back_aborts_a_slide_into_a_crouch() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.press_crouch()
	player.velocity = player.facing() * 6.0
	player.move_manager.set_move(Move.SLIDE)
	input.hold_move(0.0, -1.0)
	await step(3)
	assert_eq(player.move_manager.current_name, Move.CROUCH,
		"the hint back did not abort the slide to Crouch")

## The crouched collision: the feet stay, the height is 61 uu x 2, and the
## standing height comes back when the crouch ends.
func test_crouch_and_slide_share_the_crouched_collision() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var standing: float = player.current_capsule_height()
	player.move_manager.set_move(Move.CROUCH)
	assert_almost_eq(player.current_capsule_height(), player.config.pawn.custom_collision_height, 0.001,
		"Crouch did not shrink the collision")
	player.velocity = player.facing() * 6.0
	player.move_manager.set_move(Move.SLIDE)
	assert_almost_eq(player.current_capsule_height(), player.config.pawn.custom_collision_height, 0.001,
		"Slide out of Crouch changed the collision")
	player.move_manager.set_move(Move.WALKING)
	assert_almost_eq(player.current_capsule_height(), standing, 0.001,
		"leaving for Walking did not give the standing height back")

## A fully held strafe key turns a ground jump into a dodge jump: JumpAddXY
## along the pawn's right plus 0.3 of the velocity, BaseJumpZ up.
func test_a_jump_with_strafe_held_is_a_dodge_jump() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 0.0)
	await step(2)
	input.hold_move(1.0, 0.0)
	await step(1)
	var right: Vector3 = player.facing().cross(Vector3.UP).normalized()
	var carried: Vector3 = player.velocity
	input.press_jump()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "the jump was not a dodge jump")
	var dodge_cfg: DodgeJumpConfig = player.config.dodge_jump
	var expected_side: float = dodge_cfg.jump_add_xy + carried.dot(right) * dodge_cfg.inertia_conservation
	assert_almost_eq(player.velocity.dot(right), expected_side, 0.3,
		"the dodge did not throw the body JumpAddXY to the right")

## TdMove_Coil: no time limit (CoilTime is never read) -- the coil holds
## until it lands.
func test_a_coil_lasts_until_it_lands() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(40)
	input.press_jump()
	await step(2)
	input.press_crouch()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.COIL, "a running jump did not coil")
	await step(36)
	assert_eq(player.move_manager.current_name, Move.COIL,
		"the coil ended before the landing (0.6 s in)")

## The coil's lift: 240 uu/s for 0.25 s, a displacement -- the apex rises
## by 60 uu over the jump's own 124.
func test_a_coil_lifts_the_apex_by_60_uu() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(40)
	var y0: float = player.global_position.y
	input.press_jump()
	await step(1)
	input.press_crouch()
	var top: float = y0
	for i in 50:
		await step(1)
		top = maxf(top, player.global_position.y)
	assert_almost_eq(top - y0, 1.24 + 0.6, 0.05, "the coiled jump's apex is not 1.84 m")

## Turn180 is a ground move: from Walking only, half a turn clockwise, and the
## animation's end hands back to Walking.
func test_the_ground_turn_turns_half_a_turn_and_returns_to_walking() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	var yaw0: float = player.rotation.y
	input.press_turn()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.TURN_180, "Q on the ground did not turn")
	await step(30)
	assert_almost_eq(absf(wrapf(player.rotation.y - yaw0, -PI, PI)), PI, 0.02,
		"the turn did not come half a turn round")
	await step(30)
	assert_eq(player.move_manager.current_name, Move.WALKING,
		"the standing turn did not end with its 0.8 s animation")

## LookBehind is an exec binding: it runs before PlayerInput, so the turn's
## DisableMovementTime already zeroes the axes of the frame it starts on, and
## that frame brakes instead of sprinting. [ME:CONFIRMED 15 §15.13] every
## recorded Q turn shows its first frame already slower.
func test_a_running_turn_brakes_on_the_frame_it_starts() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	input.hold_move(0.0, 1.0)
	await step(120)
	var before: float = player.horizontal_speed()
	input.press_turn()
	await step(1)
	assert_eq(player.move_manager.current_name, Move.TURN_180, "test setup: Q did not turn")
	assert_lt(player.horizontal_speed(), before - 0.1,
		"the turn's first frame still ran on the sprint's axes")

## The UncontrolledFall state refuses every move but Landing and SoftLanding.
func test_the_uncontrolled_fall_refuses_every_move_but_the_landings() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.global_position.y += 20.0
	player.move_manager.set_move(Move.FALL_UNCONTROLLED)
	assert_true(player.uncontrolled_fall, "the pawn did not enter its UncontrolledFall state")
	assert_false(player.move_manager.set_move(Move.FALLING), "Falling was let in")
	assert_false(player.move_manager.set_move(Move.LAY_ON_GROUND), "LayOnGround was let in")
	assert_eq(player.move_manager.current_name, Move.FALL_UNCONTROLLED)

## RumpSlide raises the pawn's walkable floor to MinSlideFloorZ for its length
## and gives the old value back on the way out.
func test_the_rump_slide_makes_its_chute_unwalkable_for_its_length() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var walkable: float = player.walkable_floor_z
	player.uncontrolled_slide_normal = Vector3(0.0, 0.8, 0.6).normalized()
	assert_true(player.move_manager.set_move(Move.RAMP_SLIDE, true), "the slide refused a 0.8 chute")
	assert_almost_eq(player.walkable_floor_z, 0.9, 0.0001, "WalkableFloorZ was not raised")
	assert_almost_eq(player.gravity_modifier, 0.5, 0.0001, "the slide's half gravity is missing")
	player.move_manager.set_move(Move.FALLING)
	assert_almost_eq(player.walkable_floor_z, walkable, 0.0001, "WalkableFloorZ was not restored")
	assert_almost_eq(player.gravity_modifier, 1.0, 0.0001, "the gravity modifier was not restored")

## RumpSlide.CanDoMove: a chute flatter than 0.9 or steeper than 0.6 is not one.
func test_the_rump_slide_only_takes_a_chute_between_0_6_and_0_9() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.uncontrolled_slide_normal = Vector3(0.0, 0.95, 0.31).normalized()
	assert_false(player.move_manager.can_do(Move.RAMP_SLIDE), "a 0.95 surface was taken")
	player.uncontrolled_slide_normal = Vector3(0.0, 0.5, 0.87).normalized()
	assert_false(player.move_manager.can_do(Move.RAMP_SLIDE), "a 0.5 surface was taken")

## CheckForLedges: only Crouch is held back at an edge.
func test_a_crouch_is_held_at_an_edge_that_walking_walks_off() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	_box(Vector3(10.0, 3.0, 10.0), Vector2(0.0, 0.0), 3.0)
	player.global_position = Vector3(0.0, 3.95, -3.0)
	await step(10)
	input.press_crouch()
	input.hold_move(0.0, -1.0)
	await step(2)
	# Not past 0.8: a forward hint makes EdgeCheck give the delta back.
	input.hold_move(0.0, 0.6)
	await step(240)
	assert_eq(player.move_manager.current_name, Move.CROUCH, "the crouch did not stay a crouch")
	assert_gt(player.global_position.y, 3.5, "the crouch walked off the edge")

## Vertigo: walking slowly at a drop of more than 10 m, facing it, the walking
## physics starts it and holds the body at the edge.
func test_walking_slowly_at_a_deep_drop_starts_vertigo() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var input: ScriptedInputSource = world["input"]
	_box(Vector3(10.0, 1.0, 10.0), Vector2(0.0, 0.0), 15.0)
	player.global_position = Vector3(0.0, 15.95, -3.5)
	# CheckForLedges asks Vertigo.CanDoMove BEFORE it stores the new edge, so
	# the edge CanDoMove checks is the one stored the time before (zero in a
	# fresh pawn). Stand one in ahead of the body.
	player.move_manager.move_for(Move.VERTIGO).last_edge_position = Vector3(0.0, 15.5, -20.0)
	await step(10)
	input.hold_move(0.0, 0.25)
	var started := false
	for i in 240:
		await step(1)
		if player.move_manager.current_name == Move.VERTIGO:
			started = true
			break
	assert_true(started, "walking at the drop never started Vertigo")
	assert_gt(player.global_position.y, 14.5, "the body went over the edge")

## [ME:CONFIRMED decompile] The view resets that decide where the run goes on
## from: SkillRoll.StartMove ResetCameraLook(0.2); LayOnGround's GetUp and
## GetUpBack ResetCameraLook(1.0), the back roll also looking 1000 uu ahead
## and 300 down; 180TurnInAir.StartMove looks at the take-off point.
func test_the_rolls_and_turns_reset_the_view_as_the_original_does() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var manager: MoveManager = player.move_manager
	manager.start(Move.SKILL_ROLL)
	var roll: Move = manager.current_move()
	assert_true(roll.reset_camera_look_active, "the roll does not reset the view")
	assert_almost_eq(roll.cancel_reset_camera_look_time - player.world_time, 0.2, 0.001)
	manager.start(Move.LAY_ON_GROUND)
	var lying: LayOnGroundMove = manager.current_move()
	assert_false(lying.reset_camera_look_active, "test setup: lying already resets")
	lying._get_up()
	assert_true(lying.reset_camera_look_active, "the get-up does not reset the view")
	assert_almost_eq(lying.cancel_reset_camera_look_time - player.world_time, 1.0, 0.001)
	manager.start(Move.LAY_ON_GROUND)
	lying._get_up_back()
	assert_true(lying.reset_camera_look_active, "the back roll does not reset the view")
	assert_true(lying.look_at_target_location_active, "the back roll does not look ahead")
	var ahead: Vector3 = lying.look_at_target_location - player.global_position
	assert_almost_eq(ahead.y, -3.0, 0.001, "the back roll's look-at is not 300 uu down")
	assert_almost_eq(Vector2(ahead.x, ahead.z).length(), 10.0, 0.001, "nor 1000 uu ahead")
	player.last_jump_location = player.global_position + Vector3(0.0, 0.0, 3.0)
	manager.start(Move.TURN_180_IN_AIR)
	var turn: Move = manager.current_move()
	assert_true(turn.look_at_target_location_active, "the turn in the air does not look back")
	assert_almost_eq(turn.look_at_target_location, player.last_jump_location + Vector3(0.0, 0.9, 0.0), Vector3.ONE * 0.001)

## [ME:CONFIRMED decompile TdMove.ShrinkCollision] The crouched collision
## moves Location down 29 uu with it: every height the original measures off
## Location -- EnterFallingHeight first -- is the crouched centre's.
func test_a_crouched_body_measures_its_fall_from_the_crouched_centre() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.move_manager.start(Move.CROUCH)
	assert_almost_eq(player.collision_center().y, player.global_position.y - 0.29, 0.001,
		"test setup: the crouch did not shrink the collision 29 uu")
	player.set_physics(Move.PHYS_FALLING)
	assert_almost_eq(player.enter_falling_height, player.collision_center().y, 0.0001,
		"EnterFallingHeight is not the crouched Location")

## [ME:CONFIRMED decompile TdMove.EnlargeCollision] The standing size comes
## back the moment the crouched move stops, room overhead or not, and a body
## on the ground is stepped back down onto its floor.
func test_the_standing_size_comes_back_at_once_and_on_the_floor() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	var feet: float = player.global_position.y - player.standing_height() * 0.5
	player.move_manager.start(Move.CROUCH)
	player.move_manager.start(Move.WALKING)
	# Within the walk's 2.15 uu hover of where it stood: the step down ends
	# touching the floor.
	assert_almost_eq(player.global_position.y - player.standing_height() * 0.5, feet, 0.025,
		"the body was not stepped back down onto its floor")
	player.move_manager.start(Move.CROUCH)
	_box(Vector3(4.0, 0.2, 4.0), Vector2(player.global_position.x, player.global_position.z),
		feet + 1.2 + 0.2)
	await step(1)
	player.move_manager.start(Move.WALKING)
	assert_almost_eq(player.current_capsule_height(), player.standing_height(), 0.0001,
		"the standing size was held back for headroom")

## [ME:CONFIRMED decompile TdMove_Slide.StopMove] FaceRotationTimeLeft = 0.4:
## out of a slide the pawn eases round to the view instead of snapping to it.
func test_the_slide_hands_the_facing_back_over_0_4_s() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.move_manager.start(Move.SLIDE)
	player.face_rotation_time_left = 0.0
	player.move_manager.set_move(Move.CROUCH)
	assert_almost_eq(player.face_rotation_time_left, 0.4, 0.0001, "the slide's stop set no facing ease")

## [ME:CONFIRMED anims root_motion/JumpTurnFly] The turn in the air is done
## 0.283 s in -- seventeen frames -- at an even rate.
func test_the_turn_in_the_air_is_done_in_17_frames() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.global_position.y += 10.0
	player.move_manager.start(Move.FALLING)
	await step(2)
	var from: float = player.pawn_yaw
	player.move_manager.start(Move.TURN_180_IN_AIR)
	await step(16)
	var sixteen: float = absf(wrapf(player.pawn_yaw - from, -PI, PI))
	await step(1)
	var seventeen: float = absf(wrapf(player.pawn_yaw - from, -PI, PI))
	assert_lt(sixteen, PI - 0.1, "the turn was done before its seventeenth frame")
	assert_almost_eq(seventeen, PI, 0.001, "the turn was not done on its seventeenth frame")

## [ME:CONFIRMED decompile 0x00efc460 / 0x00d235c0] Root motion is taken from
## the frame AFTER UseRootMotion(true) (PreviousRMM), and an anim update with
## no root-motion animation playing empties the delta rather than leaving the
## last one for the physics.
func test_root_motion_waits_a_frame_and_empties_without_an_animation() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.use_root_motion(true)
	assert_false(player.root_motion_takes_velocity(), "the frame root motion was switched on took it")
	player.add_root_motion(Vector3(0.5, 0.0, 0.0))
	player.tick_anim_slot(1.0 / 60.0)
	assert_true(player.root_motion_takes_velocity(), "the next frame does not take the root motion")
	assert_eq(player.root_motion_delta, Vector3.ZERO, "an update with nothing playing left a delta")
	player.use_root_motion(false)
	assert_false(player.root_motion_takes_velocity(), "root motion off is not taken off at once")

## [ME:CONFIRMED decompile 0x00d235c0] A root rotation sets the view's yaw to
## the pawn's: whatever the view was turned by, it ends on the pawn.
func test_a_root_rotation_brings_the_view_yaw_onto_the_pawn() -> void:
	var world: Dictionary = await _world()
	var player: Player = world["player"]
	player.rotation.y = player.pawn_yaw + 0.7
	player.turn_by_root_rotation(UE.yaw_units(player.pawn_yaw) + 4096)
	assert_almost_eq(wrapf(player.rotation.y - player.pawn_yaw, -PI, PI), 0.0, 1e-6,
		"the view's yaw kept its offset from the turned pawn")

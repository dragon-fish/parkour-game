extends ParkourTest

# DodgeJump -- the sideways hop off A or D. The original's TdMove_DodgeJump.
#
# WHAT IS PINNED HERE IS NOT THE NUMBERS. 3.0 m/s up, 6.0 m/s sideways and the
# 0.99 threshold are dials; a wrong one is visible the first time it is
# played. What these cases hold down is the handful of facts that do not move
# when the feel is retuned:
#
#   * A DIAGONAL STILL DODGES. [ME:CONFIRMED 04 §4.5] W+A and space fires a
#     left dodge in the original. This is the fact that killed the earlier
#     reading of StrafeThreshold = 0.99 as "the input must be a pure A or D":
#     the threshold is on the strafe AXIS, which a key pushes full-scale
#     whether or not W is held too. See MoveInput.strafe_axis.
#
#   * THE IMPULSE IS A WORLD VECTOR, SOLVED ONCE. [ME:CONFIRMED 04 §4.5]
#     swinging the view 90 degrees mid-dodge inherits the sideways speed as
#     forward speed. That is a bug in the original and copying it is the port,
#     so the impulse must be spent on entry and never recomputed against the
#     current facing. A per-tick push along the body's own right would grow
#     the speed instead of carrying it, which is what these cases watch for.
#
#   * THE RUN IS CARRIED INTO THE LAUNCH, SCALED. [ME:CONFIRMED 04 §4.5]
#     DodgeJumpInertiaConservation = 0.3 is applied to the horizontal velocity
#     and the impulse added on top, so a dodge out of a run leaves FASTER than
#     one from a standstill. Dropping the momentum instead predicts the
#     standstill case exactly and every other case wrong, which is why the
#     cases below pin the run one.
#
#   * IT COSTS NO SPEED ENERGY. A dodge out of a sprint does sag to near base
#     velocity afterwards, but that is the velocity being turned back under the
#     held input on touchdown -- land already facing the way the dodge threw
#     you and the speed climbs from the first grounded tick instead.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## Standing still on the floor, settled.
func _standing() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(30)
	return _world["player"]

## Running straight ahead long enough to bank speed energy well clear of the
## base floor, so that spending it down to that floor is measurable.
func _running() -> Player:
	var player: Player = await _standing()
	_world["input"].hold_move(0.0, 1.0)
	await step(240)
	return player

func _horizontal(player: Player) -> Vector2:
	return Vector2(player.velocity.x, player.velocity.z)

# --- entry --------------------------------------------------------------------

func test_a_sideways_jump_is_a_dodge() -> void:
	var player: Player = await _standing()
	_world["input"].hold_move(1.0, 0.0)
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP,
		"strafe + jump did not dodge (got %s)" % player.move_manager.current_name)

func test_a_diagonal_jump_is_still_a_dodge() -> void:
	# [ME:CONFIRMED 04 §4.5] W+A and space fires a left dodge. The strafe axis
	# is full-scale on a keyboard whichever other keys are held, so the
	# threshold is met even though the normalised move vector's x component is
	# only 0.707.
	var player: Player = await _standing()
	_world["input"].hold_move(-1.0, 1.0)
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP,
		"a diagonal jump did not dodge (got %s)" % player.move_manager.current_name)

func test_a_straight_ahead_jump_is_an_ordinary_jump() -> void:
	var player: Player = await _standing()
	_world["input"].hold_move(0.0, 1.0)
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"running straight ahead dodged (got %s)" % player.move_manager.current_name)

func test_a_half_pushed_stick_does_not_dodge() -> void:
	# The whole reason strafe_axis is a field. A stick pushed diagonally reads
	# 0.707 on the axis where a key reads 1.0, and a threshold of 0.99 refuses
	# it. [ME:INFERRED] whether the original's own pad really behaves this way.
	# What is pinned here is only that the threshold is asked of the AXIS
	# rather than of the normalised vector, so that the answer is allowed to
	# differ between a key and a stick at all.
	var player: Player = await _standing()
	_world["input"].hold_move(-1.0, 1.0)
	_world["input"].state.strafe_axis = -0.707
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"a half-pushed axis dodged (got %s)" % player.move_manager.current_name)

# --- the impulse ----------------------------------------------------------------

func test_the_dodge_impulse_is_spent_once_not_per_tick() -> void:
	# A per-tick push along the body's own right would keep adding speed for
	# as long as the move ran. Held with no input at all, so nothing but the
	# move itself can touch the horizontal velocity.
	var player: Player = await _standing()
	_world["input"].hold_move(1.0, 0.0)
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")

	_world["input"].hold_move(0.0, 0.0)
	var launched := _horizontal(player)
	await step(5)
	assert_almost_eq(_horizontal(player).length(), launched.length(), 0.001,
		"the sideways speed changed while airborne with no input")

func test_the_dodge_carries_the_view_swing_rather_than_following_it() -> void:
	# The dodge glitch, and the reason it is a REQUIREMENT rather than a
	# defect: the sideways speed is a world vector, so swinging the view
	# mid-dodge leaves it pointing where it was. DO NOT "fix" this.
	var player: Player = await _standing()
	_world["input"].hold_move(1.0, 0.0)
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")

	_world["input"].hold_move(0.0, 0.0)
	var launched := _horizontal(player)
	player.rotation.y += PI * 0.5
	await step(1)
	assert_almost_eq(_horizontal(player).angle(), launched.angle(), 0.001,
		"the sideways velocity turned with the body")

# --- the cost ------------------------------------------------------------------

func test_a_dodge_does_not_spend_speed_energy() -> void:
	# The banked energy is what the run rebuilds against, and billing it here
	# would drag the landing back down to base velocity -- which is precisely
	# the speed the side-jump boost exists to keep. The sag a run-entered dodge
	# really does show belongs to the velocity being turned, not to a ceiling
	# this move lowered.
	var player: Player = await _running()
	var banked: float = player.speed_energy.energy
	assert_gt(banked, player.speed_energy.base_floor(),
		"test setup: the run banked no energy to spend")

	_world["input"].hold_move(1.0, 1.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	assert_almost_eq(player.speed_energy.energy, banked, 0.001,
		"the dodge billed the banked speed energy")

func test_a_dodge_from_a_standstill_leaves_at_the_impulse() -> void:
	# With nothing to conserve, inertia_conservation has nothing to scale and
	# the body leaves along jump_add_xy alone. THIS CASE CANNOT TELL THE TWO
	# READINGS APART -- dropping the momentum predicts it just as well -- and
	# it is here to say so, next to the run case that does separate them.
	var player: Player = await _standing()
	# Jumped on the same tick the strafe starts: WalkingMove accelerates before
	# it reads the press, so every tick held first is momentum the launch then
	# has something to conserve, and the case stops being a standstill one.
	_world["input"].hold_move(1.0, 0.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	assert_almost_eq(_horizontal(player).length(), player.config.dodge_jump.jump_add_xy, 0.3,
		"a standing dodge did not leave at the impulse")

func test_a_dodge_out_of_a_run_leaves_faster_than_the_impulse_alone() -> void:
	# The fact that kills "the horizontal momentum is gone": if it were, every
	# dodge would leave at jump_add_xy whatever ran into it. Measured off the
	# original, a standstill dodge leaves at 21.60 km/h and a dodge out of a
	# 25.58 km/h run leaves at 26.51 [ME:CONFIRMED 04 §4.5].
	var player: Player = await _running()
	assert_gt(_horizontal(player).length(), player.config.pawn.speed_max_base_velocity,
		"test setup: the run never passed base velocity")

	_world["input"].hold_move(1.0, 1.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	assert_gt(_horizontal(player).length(), player.config.dodge_jump.jump_add_xy + 0.1,
		"a dodge out of a run left with no more than the impulse")

func test_a_dodge_out_of_a_run_carries_a_share_of_the_forward_speed() -> void:
	# Scaled, not kept whole and not dropped: the component along the way the
	# run was going survives the launch and is smaller than it was. Stated as a
	# band rather than as a number because inertia_conservation is a dial --
	# what must not move is that both ends of the band are open.
	var player: Player = await _running()
	var before := _horizontal(player)

	_world["input"].hold_move(1.0, 1.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	var carried: float = _horizontal(player).dot(before.normalized())
	assert_gt(carried, 0.0, "the dodge dropped the forward speed entirely")
	assert_lt(carried, before.length(), "the dodge carried the whole run through the turn")

# --- the capability set ----------------------------------------------------------

func test_a_dodge_reaches_for_nothing() -> void:
	# [ME:CONFIRMED 11 §11.2] the capability matrix puts DodgeJump in exactly
	# one of the six lists (ExitToFalling) and in none of the three probe
	# ones. Left false in the config it reads like forgotten wiring, so it is
	# nailed down here: a later "fix" for a dodge that refuses a ledge in
	# reach has to argue with a test rather than with a comment.
	var cfg := MovementConfig.new()
	assert_false(cfg.dodge_jump.check_for_grab, "DodgeJump must not check for a grab")
	assert_false(cfg.dodge_jump.check_for_vault_over, "DodgeJump must not check for a vault")
	assert_false(cfg.dodge_jump.check_for_wall_climb, "DodgeJump must not check for a wall")

# --- cooldown -----------------------------------------------------------------

func test_a_dodge_inside_its_cooldown_is_an_ordinary_jump() -> void:
	var player: Player = await _standing()
	_world["input"].hold_move(1.0, 0.0)
	await step(10)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: no first dodge")
	for i in 120:
		await step(1)
		if player.move_manager.current_name == Move.WALKING:
			break
	assert_eq(player.move_manager.current_name, Move.WALKING, "test setup: never landed")
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.JUMP,
		"a second dodge fired inside the cooldown (got %s)" % player.move_manager.current_name)

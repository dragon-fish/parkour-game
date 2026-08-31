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
#   * THE COST IS SPEED ENERGY, DOWN TO THE FLOOR EVERYTHING ELSE STOPS AT.
#     [ME:CONFIRMED 04 §4.5] a dodge out of a run leaves the speed energy at
#     base velocity, 14.4 km/h. That floor already exists twice over
#     (SpeedEnergy.spend_turn() and Player's out-of-arc drain), and this is a
#     third caller of it rather than a fourth number.

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

func test_the_dodge_spends_speed_energy_down_to_base() -> void:
	# [ME:CONFIRMED 04 §4.5] a dodge out of a run drops the speed energy to
	# base velocity, 14.4 km/h. Not a separate number --
	# PawnConfig.speed_max_base_velocity is where turning and out-of-arc
	# running already stop.
	var player: Player = await _running()
	var floor_energy: float = player.speed_energy.base_floor()
	assert_gt(player.speed_energy.energy, floor_energy,
		"test setup: the run banked no energy to spend")

	_world["input"].hold_move(1.0, 1.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	assert_almost_eq(player.speed_energy.energy, floor_energy, 0.001,
		"the dodge did not spend the banked energy down to base velocity")

func test_a_dodge_out_of_a_run_gives_up_the_forward_momentum() -> void:
	# [ME:CONFIRMED 04 §4.5] the forward momentum is GONE on the tick the dodge
	# starts -- not scaled, not clamped -- and the body turns a corner no real
	# one could. Base velocity is where the CEILING lands, i.e. the speed the
	# run rebuilds from after touchdown; it is not a floor the airborne body
	# gets to keep.
	#
	# Anything left in the forward direction composes with the impulse instead
	# of being replaced by it, and the dodge comes out FASTER than the run that
	# entered it, aimed up the diagonal. Keeping 4.0 of a 5.0 run did exactly
	# that: 4 forward and 6 sideways leave at 7.2, pointing 34 degrees off the
	# way the dodge was thrown.
	var player: Player = await _running()
	var before := _horizontal(player)
	assert_gt(before.length(), player.config.pawn.speed_max_base_velocity,
		"test setup: the run never passed base velocity")

	_world["input"].hold_move(1.0, 1.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	assert_almost_eq(_horizontal(player).dot(before.normalized()), 0.0, 0.05,
		"the dodge carried forward speed through the turn")

func test_a_dodge_leaves_along_the_impulse_and_nothing_else() -> void:
	# The other half of the same fact, stated as a speed rather than as a
	# direction: what the body leaves with IS the impulse. A run that
	# contributes anything at all shows up here as a horizontal speed above
	# jump_add_xy.
	var player: Player = await _running()
	_world["input"].hold_move(1.0, 1.0)
	_world["input"].press_jump()
	await step(2)
	assert_eq(player.move_manager.current_name, Move.DODGE_JUMP, "test setup: not dodging")
	assert_almost_eq(_horizontal(player).length(), player.config.dodge_jump.jump_add_xy, 0.05,
		"the dodge left with more than the impulse it was given")

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

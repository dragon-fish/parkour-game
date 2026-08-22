extends ParkourTest

# A vault can be caught on the way DOWN, within limits.
#
# Five of the six rows in SpeedVaultConfig.variants require MinSpeedZ >= 0 --
# they only match while rising -- and the sixth, auto_step_up_right_leg, is the
# descending one but tops out at 0.48 m and 3 m/s. So falling onto a metre-high
# ledge at running pace matched NOTHING, and the only way to vault it was to
# catch the rising half of a jump. The owner: "the tolerance is terrible, and
# the jump lasts hardly any time at all."
#
# ⚠️ A DELIBERATE DIVERGENCE. The original's descending row is a RESCUE for a
# jump that fell short, not a second way to vault, and this widens it. The three
# gates below are what keep it a rescue, and each of them is why this file
# exists: a rescue that fires when the player did not ask for it, or on a fall
# that is about to cost two seconds, is the game playing itself.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A falling player, `fallen` metres below where it launched, with `holding`
## as this tick's input. Returns what the vault table would be asked about.
func _reported_speed_z(fallen: float, holding: Vector2, rising: bool = false) -> float:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(20)
	var player: Player = _world["player"]
	var move: AirborneMove = player.move_manager.move_for(Move.FALLING)
	player.velocity.y = 4.0 if rising else -8.0
	# Faces -Z at rest, so a forward hold is a hold toward whatever the probe
	# is looking at.
	player.rotation.y = 0.0
	var input := MoveInput.new()
	input.move = holding
	player.last_input = input
	# fall_height is launch_y - world_y, and reset() re-baselines to a ground
	# height -- so a launch this far above the body is a fall of that depth.
	player.fall_tracker.reset(player.global_position.y + fallen)
	player.fall_tracker.update(0.0, player.velocity.y, player.global_position.y)
	return move._vault_speed_z()

# --- the window is open -------------------------------------------------------

func test_a_short_fall_with_forward_held_reads_as_level() -> void:
	# Level, not rising: reported as 0.0 rather than as a flag, so the HIGH
	# tiers -- which ask for MinSpeedZ 0.5 -- still refuse. A genuinely high
	# vault still costs a jump; only the middle tier is rescued.
	var reported: float = await _reported_speed_z(2.0, Vector2(0.0, 1.0))
	assert_almost_eq(reported, 0.0, 0.0001,
		"a 2 m fall with forward held reported %.2f" % reported)

# --- and the three things that close it ----------------------------------------

func test_a_fall_that_is_about_to_hurt_is_not_rescued() -> void:
	# hard_landing_height is the same 5.3 m that decides whether a landing costs
	# two seconds. A fall that is about to hurt is not one to rescue -- otherwise
	# the rescue quietly becomes a way to cancel the penalty.
	var deep: float = 5.4
	var reported: float = await _reported_speed_z(deep, Vector2(0.0, 1.0))
	assert_lt(reported, 0.0,
		"a %.1f m fall was rescued anyway (reported %.2f)" % [deep, reported])

func test_falling_past_a_ledge_without_asking_is_just_a_fall() -> void:
	# No input at all. Turning this into a vault would be the game playing
	# itself.
	var reported: float = await _reported_speed_z(2.0, Vector2.ZERO)
	assert_lt(reported, 0.0, "an unheld fall was rescued (reported %.2f)" % reported)

func test_holding_away_from_the_obstacle_does_not_count() -> void:
	# The probe looks along the facing, so backing away is not "asking for it".
	var reported: float = await _reported_speed_z(2.0, Vector2(0.0, -1.0))
	assert_lt(reported, 0.0, "a backward hold was rescued (reported %.2f)" % reported)

func test_a_rising_body_is_reported_honestly() -> void:
	# The real rows already cover it; the rescue must not touch the number and
	# quietly change which variant a jump matches.
	var reported: float = await _reported_speed_z(0.0, Vector2(0.0, 1.0), true)
	assert_gt(reported, 0.0, "a rising body was reported as %.2f" % reported)

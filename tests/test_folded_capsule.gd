extends ParkourTest

# A vault and a pull-up FOLD the body, and then give it back.
#
# ✅ The owner's reading, and the arithmetic behind it is the convincing part:
# they had been dialling in per-clip offsets of roughly 0.8 m by hand, and
# 1.8 minus 1.0 is 0.8. A rigid upright capsule has to be lifted clear of
# anything it crosses, and lifting the FEET above an obstacle puts the EYE a
# further 1.66 m up -- which is exactly the "the eye sits at wall top plus a
# whole capsule" they reported.
#
# What is tested here is not the height. It is that the fold is GIVEN BACK. A
# state that shrinks the body and does not restore it leaves the player
# permanently crouched, and GrabMove had no exit() at all before this -- the
# same shape of leak SpeedVaultMove once had with its camera roll.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(30)
	return _world["player"]

# --- the vault ------------------------------------------------------------------

func test_a_vault_folds_the_body_and_stands_it_back_up() -> void:
	var player: Player = await _player()
	var standing: float = player.current_capsule_height()
	assert_almost_eq(standing, player.standing_height(), 0.001,
		"the fixture did not start standing")

	# The middle tier, resolved through the real table rather than named here.
	player.pending_vault_variant = player.config.speed_vault.pick_variant(
		1.0, false, 1.0, 6.0)
	assert_false(player.pending_vault_variant.is_empty(), "no middle-tier row")
	player.move_manager.start(Move.SPEED_VAULT)
	assert_almost_eq(player.current_capsule_height(),
		player.config.crouch.crouch_capsule_height, 0.001,
		"the vault did not fold the body (capsule is %.2f m)"
		% player.current_capsule_height())

	# Open sky above the fixture, so the restore is not deferred.
	player.move_manager.start(Move.WALKING)
	await step(3)
	assert_almost_eq(player.current_capsule_height(), standing, 0.001,
		"the body was left folded at %.2f m after the vault"
		% player.current_capsule_height())

# --- the pull-up ------------------------------------------------------------------

func test_a_grab_gives_the_capsule_back_on_the_way_out() -> void:
	# GrabMove HAD NO exit(). That was survivable only while it changed nothing
	# needing to be put back; the mantle's folded capsule does.
	var player: Player = await _player()
	var standing: float = player.current_capsule_height()
	var grab := player.move_manager.move_for(Move.GRAB)
	assert_not_null(grab, "there is no GrabMove to ask")

	# Folded by hand rather than by driving a real mantle, which needs geometry
	# this fixture has none of. What is under test is the restore.
	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	grab.exit()
	await step(3)
	assert_almost_eq(player.current_capsule_height(), standing, 0.001,
		"leaving a grab left the body folded at %.2f m"
		% player.current_capsule_height())

func test_the_hang_and_drop_path_survives_the_restore() -> void:
	# exit() runs on every way out of GRAB, including the one that never
	# mantled and never folded anything. Asking for a standing capsule you
	# already have has to cost nothing.
	var player: Player = await _player()
	var standing: float = player.current_capsule_height()
	var grab := player.move_manager.move_for(Move.GRAB)
	grab.exit()
	await step(3)
	assert_almost_eq(player.current_capsule_height(), standing, 0.001,
		"a grab that never folded anything changed the capsule anyway")

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

# --- which end stays put ----------------------------------------------------------

## The capsule's top and bottom in the body's own space, which is what the
## anchor decides between.
func _span(player: Player) -> Vector2:
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	return Vector2(shape_node.position.y - capsule.height * 0.5,
			shape_node.position.y + capsule.height * 0.5)

func test_a_crouch_holds_the_feet_and_lowers_the_head() -> void:
	# The original behaviour, and every caller before the vault wanted it: you
	# are standing on the same floor, so the soles are the fixed end.
	var player: Player = await _player()
	var standing: Vector2 = _span(player)
	player.set_capsule_height(0.9)
	var folded: Vector2 = _span(player)
	assert_almost_eq(folded.x, standing.x, 0.0001,
		"the soles moved %.3f m" % (folded.x - standing.x))
	assert_lt(folded.y, standing.y - 0.5, "the head did not come down")

func test_standing_back_up_puts_the_soles_back_on_the_floor() -> void:
	# The soles never move in the first place -- the fold shortens the capsule
	# from the head. This is the guard that keeps it that way.
	var player: Player = await _player()
	var standing: Vector2 = _span(player)
	player.set_capsule_height(0.9)
	player.request_standing_capsule()
	await step(3)
	var restored: Vector2 = _span(player)
	assert_almost_eq(restored.x, standing.x, 0.0001, "the soles came back wrong")
	assert_almost_eq(restored.y, standing.y, 0.0001, "the crown came back wrong")

# --- the model rides the shortened capsule's top ----------------------------------

func test_a_folded_body_drops_to_sit_on_the_shortened_capsule() -> void:
	# ✅ THE OWNER, after two attempts that each did half of it: "the capsule
	# should shrink hugging the FEET -- but the model and the eye should come
	# down with it, instead of the capsule getting shorter while the model goes
	# on playing anchored at the soles. The model's head should be anchored to
	# the capsule's top."
	#
	# The COLLISION stays on the floor. It is the MODEL that moves, by exactly
	# what the capsule lost.
	var player: Player = await _player_with_body()
	var standing_y: float = player.body.position.y
	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	player.set_body_folded(true)
	await step(60)
	var lost: float = player.standing_height() - player.config.crouch.crouch_capsule_height
	assert_almost_eq(player.body.position.y, standing_y - lost, 0.01,
		"the model dropped %.2f m for a fold that lost %.2f"
		% [standing_y - player.body.position.y, lost])

func test_unfolding_puts_the_model_back() -> void:
	var player: Player = await _player_with_body()
	var standing_y: float = player.body.position.y
	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	player.set_body_folded(true)
	await step(60)
	player.request_standing_capsule()
	player.set_body_folded(false)
	await step(60)
	assert_almost_eq(player.body.position.y, standing_y, 0.01,
		"the model was left %.2f m low" % (standing_y - player.body.position.y))

func test_a_crouch_alone_does_not_move_the_model() -> void:
	# The pair, and the reason set_body_folded() is a separate declaration
	# rather than being read off the capsule: a CROUCH shortens the capsule too,
	# and the model must not drop for it -- the crouch is in the animation.
	var player: Player = await _player_with_body()
	var standing_y: float = player.body.position.y
	player.set_capsule_height(player.config.crouch.crouch_capsule_height)
	await step(60)
	assert_almost_eq(player.body.position.y, standing_y, 0.001,
		"an ordinary crouch dropped the model %.2f m"
		% (standing_y - player.body.position.y))

## A player with a real attached body, built at runtime so this depends on no
## untracked model.
func _player_with_body() -> Player:
	var player: Player = await _player()
	var root := Node3D.new()
	root.name = "fake_body"
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	library.add_animation(&"Idle", animation)
	anim_player.add_animation_library("", library)
	root.add_child(anim_player)
	anim_player.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	player._attach_body(packed)
	return player

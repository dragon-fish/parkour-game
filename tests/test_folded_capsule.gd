extends ParkourTest

# A folded body, and a crouch: which end of the shortened capsule stays put,
# and that the model follows the fold but not the crouch.

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

# --- which end stays put ----------------------------------------------------------

## The capsule's top and bottom in the body's own space, which is what the
## anchor decides between.
func _span(player: Player) -> Vector2:
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as BoxShape3D
	return Vector2(shape_node.position.y - capsule.size.y * 0.5,
			shape_node.position.y + capsule.size.y * 0.5)

func test_a_crouch_holds_the_feet_and_lowers_the_head() -> void:
	# The soles are the fixed end -- you are standing on the same floor, so
	# every caller wants them anchored, not the head.
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
	# The capsule shrinks hugging the FEET, but the model and the eye must
	# come down with it -- the model does not go on playing anchored at the
	# soles while the capsule gets shorter. The model's head is anchored to
	# the capsule's top.
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

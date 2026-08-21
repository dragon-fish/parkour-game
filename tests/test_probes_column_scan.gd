extends ParkourTest

# The forward probe scans a COLUMN from the feet to the eye, rather than asking
# a single shin-height ray whether there is a face.
#
# The shin was the whole problem. The owner ran at a ventilation duct with open
# space beneath it and simply stopped dead -- nothing at shin height, so the old
# first gate refused the vault before anything else was considered. A chain-link
# fence fails the same way.
#
# The column also carries the classification rule rather than needing a
# threshold beside it: the lowest sample that hits is where the face begins on
# the body, and a hit at the TOP sample means the obstacle reaches the eye, at
# which point it is not a vault at all. See docs/feel-backlog.md 25-28.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _props: Array[Node] = []

func after_each() -> void:
	for prop in _props:
		prop.get_parent().remove_child(prop)
		prop.free()
	_props.clear()
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## A box whose BOTTOM is at `bottom` and top at `top`, `depth` deep, placed
## ahead of the player along -Z.
func _slab(bottom: float, top: float, depth: float, at_z: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, top - bottom, depth)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, (bottom + top) * 0.5, at_z)
	_props.append(body)

func _standing_player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(20)
	return world["player"]

# --- the obstacles the old probe could not see --------------------------------

func test_a_duct_with_open_space_beneath_it_is_seen() -> void:
	# THE REPORTED BUG. Nothing at shin height, so the old probe refused it
	# before considering anything else, and running at it just stopped the
	# player dead with no vault and no grab.
	var player: Player = await _standing_player()
	# Hangs from 0.7 to 1.2: knees pass under it, chest meets it.
	_slab(0.7, 1.2, 0.5, -1.0)
	await step(1)
	var hit: Dictionary = player.probes.vault_query()
	assert_true(hit["valid"], "a duct with air underneath was invisible to the probe")
	assert_almost_eq(float(hit["height"]), 1.2, 0.15, \
		"the top was not found where the duct actually is")

func test_a_narrow_fence_is_seen() -> void:
	# Same shape of failure: a fence is a thin plate, and the old probe's own
	# top-surface anchor was planted at a fixed distance that sailed past it.
	var player: Player = await _standing_player()
	_slab(0.0, 1.2, 0.08, -1.0)
	await step(1)
	var hit: Dictionary = player.probes.vault_query()
	assert_true(hit["valid"], "a thin fence was invisible to the probe")

# --- the eye is the ceiling ---------------------------------------------------

func test_an_obstacle_reaching_the_eye_is_not_a_vault() -> void:
	# ✅ The boundary, from play: what you can vault is what you can get your
	# hands on top of, which is about eye height. Past that it is a wall, and
	# the grab probe's business rather than this one's.
	var player: Player = await _standing_player()
	var eye_above_feet: float = player.config.camera.eye_height + 0.9
	_slab(0.0, eye_above_feet + 0.4, 0.5, -1.0)
	await step(1)
	assert_false(player.probes.vault_query()["valid"], \
		"a wall taller than the eye was offered as a vault")

func test_the_same_obstacle_below_the_eye_is_a_vault() -> void:
	# The pair to the test above: identical geometry, just short enough.
	var player: Player = await _standing_player()
	var eye_above_feet: float = player.config.camera.eye_height + 0.9
	_slab(0.0, eye_above_feet - 0.3, 0.5, -1.0)
	await step(1)
	assert_true(player.probes.vault_query()["valid"], \
		"an obstacle just below the eye was refused")

# --- standability decides the landing, not whether a vault happens ------------

func test_an_unstandable_top_is_still_a_vault() -> void:
	# ✅ Settled from play: a fence and the cabinet beside it are the same
	# height and BOTH report VaultOver -- the cabinet's wide top is simply
	# where Faith ends up standing. One axis decides the family, another the
	# landing. Refusing the whole vault on a top you cannot stand on is how a
	# pipe became an invisible wall.
	var player: Player = await _standing_player()
	_slab(0.0, 1.2, 0.08, -1.0)
	await step(1)
	var hit: Dictionary = player.probes.vault_query()
	assert_true(hit["valid"], "a thin top refused the vault outright")
	assert_true(hit.has("standable"), \
		"the probe no longer reports whether the top can be stood on")

func test_a_walkable_ramp_is_not_an_obstacle() -> void:
	# Still refused, and this one matters: a slope CharacterBody3D already
	# climbs would otherwise re-trigger a vault on every step up it. Measured
	# once on the arena's own 18.4 degree ramp.
	var world := TestWorld.build_on_slope(get_tree(), MovementConfig.new(), deg_to_rad(18.4))
	_world = world
	await step(20)
	var player: Player = world["player"]
	assert_false(player.probes.vault_query()["valid"], \
		"a walkable ramp read as something to vault")

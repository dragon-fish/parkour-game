extends ParkourTest

# WHICH node the head-follow camera latches onto inside an attached body.
#
# Player._find_head_node() is a BFS SUBSTRING match on "neck"/"head", which is
# right for "track whatever model someone dropped in" and wrong the moment a
# model names an ANCESTOR after the head too. A group node called "AllHead2"
# sitting three levels above the real "Head" wins on both counts: it contains
# the needle, and BFS reaches it first. The camera then tracks a point above
# the neck, which reads as a feel problem rather than a wiring one.
#
# Built here as a SYNTHETIC node tree rather than by loading the body that
# exposed this. That body is a CC BY-NC-SA model the repo deliberately does not
# track (see .gitignore) -- a test that preloaded it would fail on any fresh
# clone and would bake a reference to a licence-incompatible asset into the
# suite. The naming collision is the thing under test; the model is not.

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}
var _body: Node3D = null

func after_each() -> void:
	if _body != null:
		_body.free()
		_body = null
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

## The exact shape that broke: the real Head buried under a group node whose
## own name also contains "head".
func _body_with_a_head_shaped_ancestor() -> Node3D:
	var root := Node3D.new()
	root.name = "fake_body"
	var chain := ["UpperBody20", "AllHead2", "MHead", "Head2", "Head"]
	var parent: Node3D = root
	for part in chain:
		var node := Node3D.new()
		node.name = part
		parent.add_child(node)
		parent = node
	return root

func _player() -> Player:
	_world = TestWorld.build(get_tree(), MovementConfig.new())
	await step(1)
	TestWorld.place(_world)
	await step(2)
	return _world["player"]

func test_the_name_search_claims_the_ancestor() -> void:
	# PINS THE DEFECT the override exists to correct, so the reason for the
	# override cannot quietly evaporate. Not a bug to fix in the search itself:
	# preferring the deepest match would be a guess about every other model's
	# naming, made to fix one model whose path is known exactly.
	var player: Player = await _player()
	_body = _body_with_a_head_shaped_ancestor()
	var found: Node3D = player._find_head_node(_body)
	assert_not_null(found, "the name search found nothing at all")
	assert_eq(String(found.name), "AllHead2", \
		"the search resolved '%s' -- if this is now 'Head', the search changed" \
		% String(found.name))

func test_an_explicit_path_overrides_the_search() -> void:
	var player: Player = await _player()
	_body = _body_with_a_head_shaped_ancestor()
	player.body_head_path = NodePath("UpperBody20/AllHead2/MHead/Head2/Head")
	var found: Node3D = player._resolve_head_node(_body)
	assert_not_null(found, "the explicit path resolved to nothing")
	assert_eq(String(found.name), "Head", \
		"the override resolved '%s' instead of the node it names" % String(found.name))

func test_an_empty_path_falls_back_to_the_search() -> void:
	# The override must not become the only way this works: any body dropped in
	# with no path configured still relies on the search.
	var player: Player = await _player()
	_body = _body_with_a_head_shaped_ancestor()
	player.body_head_path = NodePath()
	var found: Node3D = player._resolve_head_node(_body)
	assert_not_null(found, "an unset path found nothing")
	assert_eq(String(found.name), "AllHead2", "the fallback stopped going through the search")

func test_a_broken_path_falls_back_rather_than_crashing() -> void:
	# Presentational, so it degrades -- _attach_body() already takes the same
	# line for a body that cannot be attached at all. It warns, so the symptom
	# is not silent.
	var player: Player = await _player()
	_body = _body_with_a_head_shaped_ancestor()
	player.body_head_path = NodePath("UpperBody20/NoSuchNode")
	var found: Node3D = player._resolve_head_node(_body)
	assert_not_null(found, "a bad path took the head node down with it")
	assert_eq(String(found.name), "AllHead2", "a bad path did not fall back to the search")

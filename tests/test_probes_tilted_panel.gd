extends ParkourTest

# A THIN, TILTED, SUSPENDED PANEL, grabbed by its edge.
#
# The owner's route in the original: wall run, Q, jump, and grab the leaning
# board on the right. Ours refuses it. This is a different geometry class from
# everything the probes have handled so far -- every previous case was a solid
# thing standing on the ground with a horizontal top -- so this file exists to
# say WHICH gate refuses it rather than to guess.

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

## A thin plate, `tilt` radians from horizontal, hanging in the air with its
## centre at `at`. tilt = 0 is a flat shelf; tilt = PI/2 is a vertical wall.
func _panel(tilt: float, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 0.2 m thick: a plausible scaffold deck, and exactly the ledge column's own
	# sample spacing. Anything thinner is an honest limit of a ray column rather
	# than a bug -- see LEDGE_COLUMN_SAMPLES.
	box.size = Vector3(6.0, 0.2, 2.0)
	shape.shape = box
	body.add_child(shape)
	get_tree().root.add_child(body)
	body.global_position = at
	body.rotation = Vector3(tilt, 0.0, 0.0)
	_props.append(body)

func _player_at(y: float) -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(30)
	var player: Player = world["player"]
	player.global_position = Vector3(0.0, y, 0.0)
	await step(1)
	return player

func test_a_suspended_platform_is_found_by_its_edge() -> void:
	# THE OWNER'S ROUTE: wall run, Q, jump, and grab the near edge of a scaffold
	# platform cantilevered off a wall, with open space beneath it.
	#
	# It was invisible. ledge_query() looked for a face with ONE ray at chest
	# height, which passes straight under anything suspended -- the same failure
	# the vault probe had with a ventilation duct. The tilt in the owner's first
	# screenshot was a red herring: a perfectly FLAT panel failed too.
	for degrees in [0.0, 20.0]:
		var player: Player = await _player_at(1.0)
		_panel(deg_to_rad(degrees), Vector3(0.0, 2.2, -1.2))
		await step(1)
		var hit: Dictionary = player.probes.ledge_query()
		assert_true(hit.get("valid", false), 			"a platform hanging in the air at %.0f degrees was invisible" % degrees)
		after_each()

func test_a_platform_too_steep_to_pull_onto_is_still_refused() -> void:
	# The column finds it; walkable_floor_z then refuses it, which is the right
	# division of labour. Past 45 degrees there is nothing to pull yourself onto
	# -- you would slide off -- so this is a deliberate no, not a blind spot.
	for degrees in [50.0, 70.0]:
		var player: Player = await _player_at(1.0)
		_panel(deg_to_rad(degrees), Vector3(0.0, 2.2, -1.2))
		await step(1)
		assert_false(player.probes.ledge_query().get("valid", false), 			"a %.0f degree slope was offered as something to hang from" % degrees)
		after_each()

func test_a_thin_edge_needs_the_finer_column() -> void:
	# The arithmetic that sets LEDGE_COLUMN_SAMPLES, pinned. What a grab looks
	# for can be the near edge of a flat plank -- a vertical strip only as tall
	# as the plank is thick -- so the spacing has to be finer than a plank.
	var config := MovementConfig.new()
	var spacing: float = config.grab.ledge_max_height / float(Probes.LEDGE_COLUMN_SAMPLES - 1)
	assert_lt(spacing, 0.25, 		"the ledge column samples %.2f m apart, which a plank's edge falls through" % spacing)

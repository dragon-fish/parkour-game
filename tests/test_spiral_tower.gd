extends ParkourTest

# The tower's SHAPE is arithmetic, and only the arithmetic is asserted. How
# many turns, how wide the gaps and how tall the rise are the author's, and
# nothing here pins any of them.

const TOWER := "res://scenes/levels/level_0/tower.tscn"

func test_the_spiral_goes_up() -> void:
	# A height derived from the wrong index gives a flat ring: it still looks
	# like a tower in the file, it still passes a count check, and the player
	# walks round and round arriving nowhere.
	var shape := SpiralTower.DEFAULT_SHAPE
	var previous: float = -INF
	for i in SpiralTower.platform_count(shape):
		var height: float = SpiralTower.platform_origin(shape, i).y
		assert_gt(height, previous,
			"platform %d does not stand higher than the one below it" % i)
		previous = height

func test_a_wider_gap_puts_fewer_platforms_on_a_turn() -> void:
	# Catches a per_turn() that ignores its arguments -- a hardcoded count
	# looks right at the default shape and stops responding to every dial.
	var tight := SpiralTower.DEFAULT_SHAPE.duplicate()
	var loose := SpiralTower.DEFAULT_SHAPE.duplicate()
	tight.gap = 1.0
	loose.gap = 12.0
	assert_gt(SpiralTower.per_turn(tight), SpiralTower.per_turn(loose),
		"widening the gap did not thin out the platforms")

func test_the_summit_is_above_the_last_platform() -> void:
	# The orb hangs at the summit. Below the top platform it is unreachable
	# from the tower and the level has no ending.
	var shape := SpiralTower.DEFAULT_SHAPE
	var last: int = SpiralTower.platform_count(shape) - 1
	assert_gt(SpiralTower.summit_origin(shape).y,
		SpiralTower.platform_origin(shape, last).y,
		"the summit is not above the top platform")

func test_every_platform_wears_the_same_material() -> void:
	# A pipeline is compiled the first time a material is actually DRAWN. One
	# material per platform means one compiled pipeline per reveal, and the
	# symptom is a single dropped frame on one particular lap.
	var tower: Node = load(TOWER).instantiate()
	var shared: Material = null
	var seen := 0
	for mesh in tower.find_children("*", "MeshInstance3D", true, false):
		if not (mesh.get_parent().name as String).begins_with("Platform"):
			continue
		seen += 1
		if shared == null:
			shared = mesh.material_override
		assert_eq(mesh.material_override, shared,
			"%s carries a material of its own" % mesh.get_parent().name)
	assert_gt(seen, 0, "the tower scene has no platforms")
	tower.free()

func test_the_tower_carries_a_checkpoint_at_its_base() -> void:
	# The base checkpoint is what the floor's disappearance hangs off, and it
	# is the only thing standing between a fall and restarting the whole level.
	var tower: Node = load(TOWER).instantiate()
	var base := tower.get_node_or_null("Checkpoint00")
	assert_not_null(base, "the tower has no Checkpoint00 at its base")
	assert_gt(base.find_children("*", "CollisionShape3D", true, false).size(), 0,
		"the base checkpoint has no shape, so nothing can enter it")
	tower.free()

func test_the_tower_carries_an_orb_at_its_summit() -> void:
	# The orb is the level's only exit. Without it the player climbs to the
	# top of a tower and there is nothing there.
	var tower: Node = load(TOWER).instantiate()
	var orb := tower.get_node_or_null("Orb")
	assert_not_null(orb, "the tower has no Orb")
	assert_true(orb is Area3D, "the Orb is not an Area3D, so it cannot be touched")
	tower.free()

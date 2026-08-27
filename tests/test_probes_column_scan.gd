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
	# 30, not 20: the fixture's own note says a spawn does not settle until
	# about tick 20 and gives a false landing before that. A body still drifting
	# reports its feet in the wrong place, and every height here is measured
	# from the feet.
	await step(30)
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
	# WITHIN THE DUCT'S OWN SPAN, not at its exact top. The surface probe lands
	# somewhere on the obstacle rather than precisely on its highest point --
	# recorded as docs/feel-backlog.md 30 rather than asserted away, because the
	# vault aims at whatever this reports and a low reading lands low.
	var top_above_feet: float = float(hit["height"])
	assert_gt(top_above_feet, 0.6, "the top was found below the duct entirely")
	assert_lt(top_above_feet, 1.35, "the top was found above the duct entirely")

func test_a_narrow_fence_is_seen() -> void:
	# Same shape of failure: a fence is a thin plate, and the old probe's own
	# top-surface anchor was planted at a fixed distance that sailed past it.
	var player: Player = await _standing_player()
	_slab(0.0, 1.2, 0.08, -1.0)
	await step(1)
	var hit: Dictionary = player.probes.vault_query()
	assert_true(hit["valid"], "a thin fence was invisible to the probe")

# --- hand reach is the ceiling ------------------------------------------------

func test_an_obstacle_past_hand_reach_is_not_a_vault() -> void:
	# MEASURED TWICE, 2 cm apart, from two different approaches: a vault
	# commits when the top is about 1.89 m above the FEET. Past that it is a
	# wall, and the grab probe's business rather than this one's. See
	# SpeedVaultConfig.max_edge_above_feet.
	var player: Player = await _standing_player()
	var eye_above_feet: float = player.config.camera.eye_height + 0.9
	_slab(0.0, eye_above_feet + 0.4, 0.5, -1.0)
	await step(1)
	assert_false(player.probes.vault_query()["valid"], \
		"a wall taller than the eye was offered as a vault")

func test_the_same_obstacle_inside_hand_reach_is_a_vault() -> void:
	# The pair to the test above: identical geometry, just short enough.
	var player: Player = await _standing_player()
	var eye_above_feet: float = player.config.camera.eye_height + 0.9
	_slab(0.0, eye_above_feet - 0.3, 0.5, -1.0)
	await step(1)
	assert_true(player.probes.vault_query()["valid"], \
		"an obstacle just below the eye was refused")

# --- standability decides the landing, not whether a vault happens ------------

func test_an_unstandable_top_is_still_a_vault() -> void:
	# Settled from play: a fence and the cabinet beside it are the same
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

func test_a_thin_obstacle_offers_a_far_side_and_a_wide_one_does_not() -> void:
	# THE AXIS THAT PICKS THE LANDING. The owner settled it from play -- a fence
	# and the cabinet beside it are the same height and both vault, and the
	# cabinet's wide top is simply where Faith ends up standing.
	#
	# The first attempt read this off `standable`, which asks whether the top is
	# FLAT. Every box has a flat top, so every vault landed on the obstacle and
	# stopped at its edge. Pinned here so the two questions cannot be confused
	# again.
	var player: Player = await _standing_player()
	_slab(0.0, 1.2, 0.08, -1.0)
	await step(1)
	var thin: Dictionary = player.probes.vault_query()
	assert_true(thin["valid"], "the thin obstacle was not seen at all")
	assert_true(bool(thin["vault_over"]), "a 8 cm deep fence offered no far side")
	assert_ne(thin["far_point"], Vector3.ZERO, "there is no far-side point to land on")
	after_each()

	player = await _standing_player()
	# Centre at -2.6 so the near face is 1.1 m out: inside the probe's 1.4 m
	# reach, and far enough that the body is not standing in the block.
	_slab(0.0, 1.2, 3.0, -2.6)
	await step(1)
	var wide: Dictionary = player.probes.vault_query()
	assert_true(wide["valid"], "the wide obstacle was not seen at all")
	assert_false(bool(wide["vault_over"]), \
		"a 3 m deep block offered a far side to be carried past")

func test_thin_obstacles_report_a_far_side_at_every_height() -> void:
	# The owner, from the calibration course: a 1.4 high by 0.1 deep box still
	# lands the vault on top instead of carrying past it. The 1.2 by 0.08 case
	# above passes, so something varies with the size -- most likely the
	# top-surface probe landing somewhere other than the top (feel-backlog.md
	# 30), which would put the far-side probe inside the obstacle.
	for spec in [[1.2, 0.08], [1.4, 0.1], [1.4, 0.3], [0.8, 0.1], [1.7, 0.1]]:
		var height: float = spec[0]
		var depth: float = spec[1]
		var player: Player = await _standing_player()
		_slab(0.0, height, depth, -1.0)
		await step(1)
		var hit: Dictionary = player.probes.vault_query()
		assert_true(hit["valid"], "%.2f x %.2f was not seen at all" % [height, depth])
		assert_true(bool(hit["vault_over"]), \
			"%.2f high by %.2f deep offered no far side (top read at %.2f above the feet)" \
			% [height, depth, float(hit["height"])])
		after_each()

# --- headroom ------------------------------------------------------------------

func test_a_body_does_not_fit_under_a_cap() -> void:
	# [ME:INFERRED] A ledge with a slab overhanging it can be hung from and
	# shimmied along, but cannot be pulled up onto. Ours pulled up regardless
	# and put the body inside the geometry, which showed up often as visible
	# clipping.
	#
	# Asked of the BODY with the shapecast that already existed for the
	# crouch-to-stand restore, not of a fresh raycast. A shape, because a body
	# has width.
	var player: Player = await _standing_player()
	var ledge_top := Vector3(0.0, 1.9, -1.1)
	_slab(0.0, 1.9, 0.6, -1.1)
	# Low enough over the ledge that nothing could stand there.
	_slab(2.3, 2.8, 2.4, -1.5)
	await step(1)
	assert_false(player.fits_standing_at(ledge_top), 		"a body was said to fit under a slab 0.4 m above the ledge")

func test_a_body_fits_on_an_open_ledge() -> void:
	# The control. Without it the test above passes on a check that always says
	# no, which is the failure mode that would quietly kill every mantle.
	var player: Player = await _standing_player()
	var ledge_top := Vector3(0.0, 1.9, -1.1)
	_slab(0.0, 1.9, 0.6, -1.1)
	await step(1)
	assert_true(player.fits_standing_at(ledge_top), 		"a body was said not to fit on a ledge with open sky above it")

func test_the_clearance_probe_goes_back_where_it_belongs() -> void:
	# fits_standing_at() MOVES the shapecast. Left where it was put, the
	# crouch-to-stand restore would be asking about a ledge somewhere across the
	# level, and a crouched player would either never stand or stand inside a
	# ceiling.
	var player: Player = await _standing_player()
	var probe: ShapeCast3D = player.get_node("StandClearance")
	var before: Vector3 = probe.global_position
	player.fits_standing_at(Vector3(0.0, 12.0, -30.0))
	assert_almost_eq(probe.global_position.distance_to(before), 0.0, 0.0001, 		"the clearance probe was left where the last question put it")

func test_a_thin_obstacle_with_a_drop_beyond_is_still_an_over() -> void:
	# A 2.2 m by 0.35 m wall put the player up ON TOP of it to take a step,
	# which is absurd -- 0.35 m is not somewhere to stand.
	#
	# The cause was the far-side ray reaching only a vault's own height, 1.92 m,
	# on the reasoning that anything deeper is "a drop, not a landing". True as
	# far as it goes, but it made a MISSING landing refuse the whole family, and
	# the variant table then fell through to vault_onto.
	#
	# Two failures were being treated as one. A hit ABOVE the top means the top
	# is WIDE and the body would genuinely stand there; NO hit at all means a
	# thin face with a hole behind it. One is somewhere to stand, the other is a
	# fence over a stairwell -- and the second is still an over, just without a
	# landing to aim at.
	#
	# ASKED OF THE FUNCTION, not through vault_query(). A 2.2 m top is out of
	# reach from the ground, so the whole query answers "invalid" and a test
	# routed through it asserts nothing -- which the first draft of this did,
	# and it passed against the old behaviour too.
	var player: Player = await _standing_player()
	_slab(0.0, 2.2, 0.35, -1.0)
	await step(1)
	assert_true(player.probes._query_vault_over(Vector3(0.0, 2.2, -1.0)),
		"a 0.35 m thin wall with a drop beyond was offered as somewhere to stand on")

func test_a_wide_top_is_still_not_an_over() -> void:
	# The pair, and the one that stops the change above from turning every
	# obstacle into an over: a hit ABOVE the top is a WIDE top, which is a real
	# place to stand and must stay a vault-onto.
	var player: Player = await _standing_player()
	_slab(0.0, 1.2, 3.0, -2.6)
	await step(1)
	assert_false(player.probes._query_vault_over(Vector3(0.0, 1.2, -1.4)),
		"a 3 m deep block offered a far side to be carried past")

# --- a face that is higher is not automatically the one you can grab ----------

func test_a_ledge_with_a_cap_on_it_is_grabbed_at_the_rim() -> void:
	# JUMPING AT A CAPPED OBSTACLE MUST FIND THE LOWER RIM, not the taller cap
	# above it -- anchoring on the cap puts the grab target out of reach and
	# grabs nothing at all.
	#
	# THE COLUMN MUST NOT STOP AT ONE ANSWER. "The highest hit wins" is not
	# the whole rule -- one face, one down-probe, one height gate would let a
	# cap presenting a face 1.5 m above the rim win the column, fail the gate
	# on its own top being out of reach, and take the entire query down with
	# it. The rim it stands on must still get asked about.
	#
	# Not a rare shape either: a parapet, a plant box, a plinth or another
	# storey all stack two faces in this column, and the lower one is the one
	# the hands can reach.
	var player: Player = await _standing_player()
	var feet: float = player.global_position.y - player.current_capsule_height() * 0.5
	var rim: float = feet + player.config.grab.min_wall_height + 0.3
	_slab(feet, rim, 1.0, -1.4)
	# The cap: standing ON the rim, set back so the rim survives as a ledge.
	_slab(rim, rim + 1.5, 0.6, -1.8)
	await step(1)
	var hit: Dictionary = player.probes.ledge_query()
	assert_true(hit["valid"],
		"a capped ledge came back invalid, which is the reported bug")
	assert_almost_eq(float(hit["edge"].y), rim, 0.1,
		"the anchor landed at y %.2f rather than on the rim at %.2f"
		% [hit["edge"].y, rim])

func test_an_uncapped_ledge_is_unaffected() -> void:
	# The pair. Highest-first is still the preference -- a higher grabbable
	# ledge is more progress than a lower one -- and this is what says the
	# rewrite did not quietly turn it into lowest-first.
	var player: Player = await _standing_player()
	var feet: float = player.global_position.y - player.current_capsule_height() * 0.5
	var top: float = feet + player.config.grab.min_wall_height + 0.3
	_slab(feet, top, 1.0, -1.4)
	await step(1)
	var hit: Dictionary = player.probes.ledge_query()
	assert_true(hit["valid"], "a plain wall stopped being grabbable")
	assert_almost_eq(float(hit["edge"].y), top, 0.1,
		"the anchor landed at y %.2f rather than the top at %.2f"
		% [hit["edge"].y, top])

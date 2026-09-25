extends ParkourTest

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

# A Player does NOT configure itself: setup(config, input) has to be called
# after it enters the tree, or config, fall_tracker, speed_energy and statuses
# are all null. TestWorld.build() does that, and gives a floor to stand on.
func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	return world["player"]

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = INF
	return s

func test_a_blocked_move_cannot_be_entered() -> void:
	var p := _player()
	await step(1)
	assert_true(p.move_manager.can_enter(Move.WALL_RUN), "the fixture starts blocked")
	p.statuses.apply(_spec(Status.Effect.BLOCK_WALL_RUN), p, 0)
	assert_false(p.move_manager.can_enter(Move.WALL_RUN), "the block did not reach can_enter")

func test_an_unblockable_move_is_always_enterable() -> void:
	var p := _player()
	await step(1)
	for name in [Move.WALKING, Move.FALLING, Move.LANDING]:
		assert_true(p.move_manager.can_enter(name), "%s was refused" % name)

## Builds a world and settles the body standing on the floor.
##
## A STAGGER does not fire in mid-air, so a stagger test needs a body that is
## really grounded, not one still being pushed out of the slab it spawned
## inside. The floor is left exactly where build() put it and the body is
## dropped onto it instead: TestWorld.place() moves the slab, and a torn-down
## world is still in the tree for the following test's first frame -- which
## leaves that test standing on a floor at a height it never asked for.
func _standing_player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	# build()'s slab is 1 m thick and centred on the origin, so its top face is
	# y = 0.5; one standing half-height above that is where place() would leave
	# the body if the slab had been moved instead.
	world["player"].global_position = Vector3(0.0, 1.45, 0.0)
	await step(30)
	return world["player"]

## A STAGGER carrying `damage` health, lasting until removed.
func _hit(damage: float = 35.0) -> StatusSpec:
	var s := _spec(Status.Effect.STAGGER)
	s.amount = damage
	return s

func test_a_stagger_hurts_and_empties_the_budget_without_a_lockout() -> void:
	# [ME:CONFIRMED] unpacked: a cut forces no lockout, only the slowdown --
	# and an emptied budget is that slowdown. See Player.take_hazard_hit().
	var p := await _standing_player()
	assert_true(p.grounded, "test setup: the body never settled onto the floor")
	p.speed_energy.energy = 7.0
	var hp: float = p.health.hp
	p.statuses.apply(_hit(35.0), p, 0)
	await step(2)
	assert_almost_eq(p.health.hp, hp - 35.0, 0.01, "the hit did not hurt")
	assert_lt(p.speed_energy.energy, 0.1, "the hit did not empty the speed budget")
	assert_ne(p.move_manager.current_name, Move.LANDING, "the hit locked the body out")

func test_a_stagger_shows_its_own_tint_or_the_landing_red() -> void:
	# An electric fence is drawn blue; a spec with no tint of its own keeps
	# the ordinary red.
	var p := await _standing_player()
	var shock := _hit()
	shock.tint = Color(0.3, 0.6, 1.0, 0.5)
	p.statuses.apply(shock, p, 0)
	await step(2)
	assert_eq(p.screen_effects.tint_color(), shock.tint, "the hit's own tint was not shown")
	var q := await _standing_player()
	q.statuses.apply(_hit(), q, 0)
	await step(2)
	assert_eq(q.screen_effects.tint_color(), q.config.landing.tint_color, \
		"a hit without a tint lost the ordinary red")

func test_a_stagger_is_ignored_while_already_dying() -> void:
	var p := _player()
	await step(1)
	p.move_manager.start(Move.FALL_UNCONTROLLED)
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.FALL_UNCONTROLLED, \
		"a stagger interrupted a death")

## Same as _spec(), with a finite life. STAGGER is the one effect whose
## `seconds` is a window in which it may still fire rather than how long it
## lasts, and the two tests below are what pins that reading.
func _spec_lasting(effect: int, seconds: float) -> StatusSpec:
	var s := _spec(effect)
	s.seconds = seconds
	return s

## Drops the body from just under a metre up, airborne and already falling.
##
## The height is chosen to be nowhere near hard_landing_height, so an ordinary
## touchdown from here goes to WALKING: any LANDING these tests see can only
## have come from the stagger. Unlike the 30 m drop at the end of this file,
## the body reaches the floor well inside the tests' own tick budget.
func _falling_player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	var p: Player = world["player"]
	await step(1)
	p.global_position = Vector3(0.0, 2.3, 0.0)
	p.move_manager.start(Move.FALLING)
	await step(2)
	return p

func test_a_stagger_fires_in_mid_air_rather_than_waiting_for_the_ground() -> void:
	# Barbed wire cuts you when you touch it. A volume tall enough to cover a
	# fence charges the vault at the moment it is taken, not on the far side.
	var p := await _falling_player()
	assert_false(p.grounded, "test setup: the body is not actually airborne")
	var hp: float = p.health.hp
	p.statuses.apply(_hit(), p, 0)
	await step(2)
	assert_lt(p.health.hp, hp, "a hit taken in the air did not fire")
	assert_false(p.grounded, "test setup: the body reached the floor too soon")

func test_a_hit_in_the_air_lands_from_a_standstill() -> void:
	# The budget the hit took is not handed back by the landing: the run
	# starts again from nothing, which reads as a stumble without being one.
	var p := await _falling_player()
	p.speed_energy.energy = 7.0
	p.velocity = Vector3(6.0, 0.0, 0.0)
	p.statuses.apply(_hit(), p, 0)
	for i in 90:
		await step(1)
		if p.grounded:
			break
	assert_true(p.grounded, "test setup: the body never reached the floor")
	await step(2)
	assert_lt(p.speed_energy.energy, 0.2, \
		"the landing handed back the budget the hit took")

func test_a_second_stagger_is_eaten_by_the_immunity_window() -> void:
	# A volume renews its STAGGER every tick the body is in it; without the
	# window each renewal would hurt again and empty the budget again.
	var p := await _standing_player()
	p.statuses.apply(_hit(), p, 0)
	await step(2)
	var hp: float = p.health.hp
	assert_true(p.is_stagger_immune(), "the hit did not arm the window")
	p.statuses.apply(_hit(), p, 0)
	await step(2)
	assert_almost_eq(p.health.hp, hp, 0.01, "a hit landed inside the immunity window")
	assert_false(p.statuses.has(Status.Effect.STAGGER), \
		"the eaten stagger was left in the list to fire when the window closed")

func test_standing_in_the_wire_costs_again_once_the_window_closes() -> void:
	# A hazard the player can stand in has to keep charging, or they walk the
	# whole length of it having paid once. The cadence is stagger_immunity_time.
	var p := await _standing_player()
	var immunity: float = p.config.pawn.stagger_immunity_time
	var hp: float = p.health.hp
	for i in int(immunity * 60.0) + 10:
		p.statuses.apply(_hit(10.0), p, 0)
		await step(1)
	assert_almost_eq(p.health.hp, hp - 20.0, 0.01, \
		"standing in the wire did not cost again once the window closed")

func test_stepping_back_into_the_wire_costs_immediately() -> void:
	# The window exists so the player can walk OUT. It must not also be one in
	# which they can hop off the wire and back on for free -- wire you can
	# bounce along is a platform, not a hazard. Only the volume can tell
	# walking in from a renewal, which is why it arrives as an argument.
	var p := await _standing_player()
	p.statuses.apply(_hit(10.0), p, 0)
	await step(2)
	var hp: float = p.health.hp
	p.apply_status(_hit(10.0), p, 0, true)
	await step(2)
	assert_almost_eq(p.health.hp, hp - 10.0, 0.01, \
		"the wire could be hopped off and back onto for free")

func test_a_crouch_block_forbids_the_choice_but_not_the_ceiling() -> void:
	# What a level forbids is the player CHOOSING to duck. A body that cannot
	# stand up is the geometry talking, and refusing that would leave a slide
	# under a low ceiling with no exit -- unable to end and, because steering
	# is deliberately slow, unable to be driven out either.
	var p := await _standing_player()
	p.move_manager.start(Move.WALKING)
	assert_true(p.has_headroom(), "test setup: the fixture has a ceiling on it")
	assert_true(p.move_manager.can_enter(Move.CROUCH), "test setup: crouch starts open")

	p.statuses.apply(_spec(Status.Effect.BLOCK_CROUCH), p, 0)
	assert_false(p.move_manager.can_enter(Move.CROUCH), \
		"the block never reached the voluntary crouch")

	# A lid the crouched body fits under and the standing one does not. Placed
	# off the FEET: the Player origin is the capsule CENTRE, and crouching
	# moves it while the feet stay put.
	var feet: float = p.global_position.y - p.standing_height() * 0.5
	p.move_manager.start(Move.CROUCH)
	await step(4)
	var lid := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, 6.0)
	shape.shape = box
	lid.add_child(shape)
	add_child_autofree(lid)
	lid.global_position = Vector3(p.global_position.x, \
		feet + p.config.crouch.crouch_capsule_height + 0.05 + box.size.y * 0.5, \
		p.global_position.z)
	await step(4)
	assert_false(p.has_headroom(), "test setup: the lid left room to stand")
	assert_true(p.move_manager.can_enter(Move.CROUCH), \
		"a crouch the body cannot avoid was refused, so a slide here could not end")

# --- a hit knocks the body off what it holds ----------------------------------

func test_a_hit_knocks_a_hanging_body_off_the_ledge() -> void:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	await step(1)
	TestWorld.place(world)
	await step(20)
	var p: Player = world["player"]
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 2.0, 3.0)
	shape.shape = box
	body.add_child(shape)
	p.get_parent().add_child(body)
	body.global_position = Vector3(0.0, 1.0, -3.0)
	var edge := Vector3(0.0, 2.0, -1.6)
	var query := {"valid": true, "edge": edge, "top": edge,
			"normal": Vector3.UP, "face_normal": Vector3(0, 0, 1)}
	p.global_position = IntoGrabMove.hanging_pose(p, p.config, query)
	p.pending_ledge = query
	p.move_manager.start(Move.GRAB)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.GRAB, "test setup: not hanging")
	p.statuses.apply(_hit(), p, 0)
	await step(2)
	body.queue_free()
	assert_ne(p.move_manager.current_name, Move.GRAB, "a hit left the body hanging on")

func test_a_hit_on_the_ground_keeps_the_body_on_its_feet() -> void:
	var p := await _standing_player()
	p.move_manager.start(Move.WALKING)
	await step(1)
	p.statuses.apply(_hit(), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.WALKING, "a hit on the ground knocked the body out of its walk")

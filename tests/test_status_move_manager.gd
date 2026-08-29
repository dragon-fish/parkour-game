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

func test_a_stagger_puts_the_body_into_the_landing_lockout() -> void:
	# STAGGER says "go there"; the red tint, the camera dip and the 2 s lockout
	# all belong to LandingMove and come along for free.
	var p := await _standing_player()
	assert_true(p.grounded, "test setup: the body never settled onto the floor")
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LANDING, \
		"a stagger did not reach the lockout")

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
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LANDING, \
		"a stagger taken in the air did not fire")
	assert_false(p.grounded, "test setup: the body reached the floor too soon")

func test_a_body_staggered_in_the_air_keeps_falling() -> void:
	# THE REASON THE AIRBORNE CASE WAS ONCE REFUSED. LandingMove pins
	# velocity.y to the floor-snap speed while grounded; off the floor the
	# same line lowers the body at a constant crawl with no gravity, hanging
	# it in the sky for the whole lockout.
	#
	# ASSERTED AS ACCELERATION, not as distance. Over a short window the snap
	# crawl and real gravity from a standing start cover about the same ground,
	# so a distance threshold cannot tell them apart -- but a constant speed
	# covers equal distances in equal windows and gravity does not.
	var p := await _falling_player()
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LANDING, "test setup: no stagger")
	var top: float = p.global_position.y
	await step(5)
	var first: float = top - p.global_position.y
	var mid: float = p.global_position.y
	await step(5)
	var second: float = mid - p.global_position.y
	assert_false(p.grounded, "test setup: the body reached the floor mid-measurement")
	assert_gt(second, first * 1.5, \
		"the staggered body descended at a constant crawl instead of falling")

func test_a_second_stagger_is_eaten_by_the_immunity_window() -> void:
	# The escape. The lockout refuses movement input, so a volume renewing its
	# STAGGER would re-fire on the tick the lockout ends and there would be no
	# tick in which to walk out of the wire.
	var p := await _standing_player()
	p.move_manager.start(Move.WALKING)
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LANDING, "test setup: no first stagger")
	# Past the lockout, into the window it arms on the way out.
	await step(int(ceil(p.config.landing.lockout_time * 60.0)) + 4)
	assert_ne(p.move_manager.current_name, Move.LANDING, "test setup: still locked out")
	assert_true(p.is_stagger_immune(), "the lockout did not arm the window")
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_ne(p.move_manager.current_name, Move.LANDING, \
		"a stagger landed inside the immunity window")
	assert_false(p.statuses.has(Status.Effect.STAGGER), \
		"the eaten stagger was left in the list to fire when the window closed")

func test_a_staggered_body_stops_the_moment_it_lands() -> void:
	# The knock-down keeps speed so a wired fence stays passable, but that
	# inertia is for the ARC. Carried past touchdown it slides the body across
	# the floor through a lockout that refuses every input, which reads as the
	# character walking off by itself.
	var p := await _falling_player()
	p.velocity = Vector3(6.0, 0.0, 0.0)
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(2)
	assert_eq(p.move_manager.current_name, Move.LANDING, "test setup: no stagger")
	assert_gt(absf(p.velocity.x), 0.5, \
		"test setup: the knock-down kept no inertia to carry into the fall")
	await step(60)
	assert_true(p.grounded, "test setup: the body never reached the floor")
	assert_almost_eq(Vector2(p.velocity.x, p.velocity.z).length(), 0.0, 0.001, \
		"the staggered body kept sliding after it landed")

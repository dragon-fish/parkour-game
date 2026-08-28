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
## A STAGGER is refused in mid-air, so a stagger test needs a body that is
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

func test_a_stagger_does_not_land_on_an_airborne_body() -> void:
	# A volume tall enough to cover a fence is entered in mid-air on purpose.
	# LandingMove.enter() zeroes velocity and its physics_update() then
	# descends at floor_snap_speed with no gravity, so a stagger caught up
	# there hangs the body in the sky for the whole lockout. Last in the file
	# on purpose: it leaves a body 30 m up, and a world torn down at the end
	# of a test is still in the tree for the next one's first frame.
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	var p: Player = world["player"]
	await step(1)
	p.global_position = Vector3(0.0, 30.0, 0.0)
	p.move_manager.start(Move.FALLING)
	await step(2)
	assert_false(p.grounded, "test setup: the body is not actually airborne")
	p.statuses.apply(_spec(Status.Effect.STAGGER), p, 0)
	await step(4)
	assert_ne(p.move_manager.current_name, Move.LANDING, \
		"a stagger froze the body in mid-air")

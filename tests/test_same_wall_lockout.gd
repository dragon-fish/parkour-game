extends ParkourTest

# What the wall you just left will not let you do.
#
# Kicking off a wall sends the body away from it, so for about a second
# afterwards anything requiring a move back toward that wall is impossible. The
# owner drew three cases and marked them:
#
#   one flat wall, chained          X   the same wall cannot take you back
#   a wall then one angled away     v   that is a different wall
#   two walls facing each other     v   the zig-zag corridor, opposite sides
#
# ...plus the same reasoning applied to hands rather than feet: "you cannot
# climb onto the top of the wall you are running on -- your legs are pushing
# off it, you cannot send your body to the same side."

const TestWorld = preload("res://tests/world_fixture.gd")

var _world: Dictionary = {}

func after_each() -> void:
	if _world.is_empty():
		return
	TestWorld.teardown(_world)
	_world = {}

func _player() -> Player:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_world = world
	await step(1)
	TestWorld.place(world)
	await step(2)
	return world["player"]

## A normal pointing along +X, i.e. a wall on the player's LEFT when facing -Z.
const LEFT_WALL_NORMAL := Vector3(1.0, 0.0, 0.0)
const LEFT := -1
const RIGHT := 1

# --- the rule itself ---------------------------------------------------------

func test_the_same_wall_will_not_take_you_back() -> void:
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	assert_true(player.recent_wall_refuses_run(LEFT_WALL_NORMAL, LEFT), \
		"the wall just left accepted an immediate re-run on the same side")

func test_a_wall_facing_the_other_way_is_a_different_wall() -> void:
	# The zig-zag corridor. Two walls facing each other are on OPPOSITE sides of
	# the body, and the second is the one you are travelling toward.
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	assert_false(player.recent_wall_refuses_run(-LEFT_WALL_NORMAL, RIGHT), \
		"a facing wall on the other side was refused, so the corridor is dead")

func test_a_wall_angled_away_is_a_different_wall() -> void:
	# Same side, but genuinely turned: the middle of the owner's three drawings.
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	var turned: Vector3 = LEFT_WALL_NORMAL.rotated(Vector3.UP, deg_to_rad(45.0))
	assert_false(player.recent_wall_refuses_run(turned, LEFT), \
		"a wall angled 45 degrees away counted as the same wall")

func test_a_barely_different_wall_is_still_the_same_wall() -> void:
	# The threshold has to be a real angle, not an epsilon, or a wall with any
	# construction tolerance at all reads as new.
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	var nudged: Vector3 = LEFT_WALL_NORMAL.rotated(Vector3.UP, deg_to_rad(5.0))
	assert_true(player.recent_wall_refuses_run(nudged, LEFT), \
		"5 degrees of difference was enough to count as a new wall")

func test_the_refusal_expires() -> void:
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	# same_wall_lockout is 1 s. 70 ticks is comfortably past it.
	await step(70)
	assert_false(player.recent_wall_refuses_run(LEFT_WALL_NORMAL, LEFT), \
		"the lockout never expired")

# --- hands, not just feet ----------------------------------------------------

func test_you_cannot_climb_onto_the_wall_you_are_running_on() -> void:
	# The normal points back at the body, so the wall itself -- and its top --
	# is in the NEGATIVE direction along it.
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	var on_the_wall: Vector3 = player.global_position - LEFT_WALL_NORMAL * 0.6 + Vector3.UP
	assert_true(player.recent_wall_refuses_climb_onto(on_the_wall), \
		"a ledge on the wall's own side was allowed")

func test_a_ledge_on_the_far_side_is_still_fair_game() -> void:
	# The rule is about the wall being pushed off, not about ledges in general.
	var player: Player = await _player()
	player.note_wall_contact(LEFT_WALL_NORMAL, LEFT)
	var away: Vector3 = player.global_position + LEFT_WALL_NORMAL * 0.6 + Vector3.UP
	assert_false(player.recent_wall_refuses_climb_onto(away), \
		"a ledge on the side the body is travelling toward was refused")

func test_nothing_is_refused_without_a_recent_wall() -> void:
	var player: Player = await _player()
	assert_false(player.has_recent_wall(), "a fresh player remembers a wall")
	assert_false(player.recent_wall_refuses_run(LEFT_WALL_NORMAL, LEFT), \
		"a player who has touched no wall refused a wall run")
	assert_false(player.recent_wall_refuses_climb_onto(player.global_position + Vector3.UP), \
		"a player who has touched no wall refused a grab")

extends ParkourTest

# Where a grab aimed at the bleed zone ends up.
#
# The probing half needs geometry and a body; this pins the ORDER the offsets
# are tried in, which is the part that decides whether a correction is a nudge
# or a yank.

func test_the_middle_is_tried_before_anything_is_moved() -> void:
	var offsets: Array[float] = IntoGrabMove.search_offsets(0.4, 4)
	assert_eq(offsets[0], 0.0, "a grab that was already legal would still be moved")

func test_nearer_offsets_come_before_further_ones() -> void:
	# The rule the whole feature rests on: move the SHORTEST distance that makes
	# the hang legal. Sorting the other way would slide every bleed-zone grab to
	# the far side of the ledge.
	var offsets: Array[float] = IntoGrabMove.search_offsets(0.4, 4)
	var previous: float = -1.0
	for offset in offsets:
		assert_true(absf(offset) >= previous - 0.0001, \
			"offset %.3f was tried after a further one" % offset)
		previous = absf(offset)

func test_both_sides_are_tried_at_every_distance() -> void:
	# Otherwise a lip whose safe zone lies to the left is only ever found by
	# grabs that were already left of it.
	var offsets: Array[float] = IntoGrabMove.search_offsets(0.4, 4)
	for offset in offsets:
		assert_true(offsets.has(-offset), "%.3f was tried with no mirror" % offset)

func test_the_search_never_leaves_the_bleed_zone() -> void:
	# Bounded by one capsule radius, which IS the bleed's width: the safe zone
	# ends a radius short of each corner, so a radius is the furthest a legal
	# grab can ever sit from it. Correcting further would drag a player who
	# aimed at a corner into the middle of the ledge.
	for offset in IntoGrabMove.search_offsets(0.4, 4):
		assert_true(absf(offset) <= 0.4 + 0.0001, \
			"the search reached %.3f, past the bleed zone" % offset)

func test_a_zero_width_bleed_asks_only_about_the_middle() -> void:
	assert_eq(IntoGrabMove.search_offsets(0.0, 4), [0.0] as Array[float])
	assert_eq(IntoGrabMove.search_offsets(0.4, 0), [0.0] as Array[float])

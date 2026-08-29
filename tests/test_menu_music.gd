extends ParkourTest

# The handoff is the whole feature, and it is arithmetic: the record is entered
# at the chorus's downbeat PLUS however far into a bar the title fragment had
# got, so the beat carries through the crossfade unbroken. It works at any
# moment only because the tempo never changes across the track.
#
# Asserted as arithmetic too -- a headless run has a dummy audio driver and
# reports a playback position of zero forever, so a test that played the files
# and read the clock back would pass for the wrong reason.

func test_a_click_on_a_bar_line_enters_the_chorus_on_its_downbeat() -> void:
	for bars in [0.0, 1.0, 4.0, 7.0]:
		assert_almost_eq(MenuMusic.chorus_entry(bars * MenuMusic.BAR),
			MenuMusic.CHORUS_START, 0.0001,
			"a click %d bars in did not land on the chorus's downbeat" % int(bars))

func test_a_click_mid_bar_carries_that_much_of_the_bar_across() -> void:
	# The point of the whole thing: half a bar into the fragment is half a bar
	# into the chorus, so the next kick lands exactly where it was going to.
	var half: float = MenuMusic.BAR * 0.5
	assert_almost_eq(MenuMusic.chorus_entry(3.0 * MenuMusic.BAR + half),
		MenuMusic.CHORUS_START + half, 0.0001,
		"the phase was dropped, so the beat restarts inside the crossfade")

func test_the_entry_never_lands_more_than_a_bar_past_the_chorus() -> void:
	# Whatever the fragment reports -- and a looping stream may or may not wrap
	# its own clock -- the answer has to stay inside the chorus's first bar.
	for position in [0.0, 14.0, 14.4897, 30.0, 999.0]:
		var entry: float = MenuMusic.chorus_entry(position)
		assert_between(entry, MenuMusic.CHORUS_START,
			MenuMusic.CHORUS_START + MenuMusic.BAR,
			"a position of %.4f s asked for %.4f s into the record" % [position, entry])

func test_the_chorus_sits_where_the_grid_says_it_does() -> void:
	# Bar 32, and the record has to be long enough to contain it with room to
	# spare -- entering a file that ends at the chorus would be silence.
	assert_almost_eq(MenuMusic.CHORUS_START / MenuMusic.BAR, 32.0, 0.001,
		"the chorus stopped being bar 32")

func test_the_looping_fragment_is_a_whole_number_of_bars() -> void:
	# It loops, so its length IS the loop point: cut to some other length it
	# would come round off the grid, which is audible immediately and
	# impossible to diagnose by reading the code.
	assert_true(ResourceLoader.exists(MenuMusic.LOOP_STREAM), "the title fragment is missing")
	var bars: float = load(MenuMusic.LOOP_STREAM).get_length() / MenuMusic.BAR
	assert_almost_eq(bars, 8.0, 0.02, "the title fragment is %.3f bars long, not 8" % bars)

func test_the_record_is_whole_and_reaches_well_past_its_own_chorus() -> void:
	# One file covers two of the menu's three moments: entered at the chorus it
	# is "from the chorus onward", entered at zero it is the track from the
	# top. A file cut short would silently turn the second into the first.
	assert_true(ResourceLoader.exists(MenuMusic.FULL_STREAM), "the record is missing")
	var length: float = load(MenuMusic.FULL_STREAM).get_length()
	assert_gt(length, MenuMusic.CHORUS_START + 60.0,
		"the record is only %.1f s -- it does not reach past its own chorus" % length)

func test_silence_is_a_number_the_mixer_will_take() -> void:
	# linear_to_db(0) is -inf and the bus refuses it, which would leave the
	# outgoing fragment stuck at full volume for the whole crossfade.
	assert_true(is_finite(MenuMusic._gain_db(0.0)), "silence came out as -inf")
	assert_almost_eq(MenuMusic._gain_db(1.0), 0.0, 0.001, "full volume was not unity")

func test_the_title_fragment_is_held_well_below_the_chorus() -> void:
	# It is the first sound the game makes, under a title card, often through
	# headphones somebody set for something else.
	assert_lt(MenuMusic.HELD_LEVEL, MenuMusic.CHORUS_LEVEL,
		"the quiet part is not quieter than the loud part")
	assert_lt(linear_to_db(MenuMusic.CHORUS_LEVEL) - linear_to_db(MenuMusic.HELD_LEVEL), 18.0,
		"the lift into the chorus is a jump, not a swell")

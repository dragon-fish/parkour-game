extends ParkourTest

# The handoff is the whole feature, and it is arithmetic: the chorus is entered
# at the phase the loop had reached, so the beat carries through the crossfade.
# Asserted as arithmetic too -- a headless run has a dummy audio driver and
# reports a playback position of zero forever, so a test that played the files
# and read the clock back would pass for the wrong reason.

func test_entering_on_a_bar_line_enters_the_chorus_at_its_own_start() -> void:
	for bars in [0.0, 1.0, 4.0, 7.0]:
		assert_almost_eq(MenuMusic.chorus_entry(bars * MenuMusic.BAR), 0.0, 0.0001, \
			"a click %d bars in did not land on the chorus's downbeat" % int(bars))

func test_entering_mid_bar_carries_that_much_of_the_bar_across() -> void:
	# The point of the whole thing: half a bar into the loop is half a bar
	# into the chorus, so the next kick lands exactly where it was going to.
	var half: float = MenuMusic.BAR * 0.5
	assert_almost_eq(MenuMusic.chorus_entry(3.0 * MenuMusic.BAR + half), half, 0.0001, \
		"the phase was dropped, so the beat restarts inside the crossfade")

func test_the_entry_never_runs_past_a_bar() -> void:
	# Whatever the loop reports -- and a looping stream may or may not wrap its
	# own clock -- the answer has to stay inside one bar of the chorus.
	for position in [0.0, 14.0, 14.4897, 30.0, 999.0]:
		var entry: float = MenuMusic.chorus_entry(position)
		assert_between(entry, 0.0, MenuMusic.BAR, \
			"a position of %.4f s asked for %.4f s into the chorus" % [position, entry])

func test_the_two_pieces_are_present_and_a_whole_number_of_bars_long() -> void:
	# The loop is eight bars and the chorus sixteen. A file re-cut to some
	# other length would loop off the grid, which is audible immediately and
	# impossible to diagnose by reading the code.
	for entry in [[MenuMusic.LOOP_STREAM, 8], [MenuMusic.CHORUS_STREAM, 12]]:
		var path: String = entry[0]
		assert_true(ResourceLoader.exists(path), "%s is missing" % path)
		var stream: AudioStream = load(path)
		var bars: float = stream.get_length() / MenuMusic.BAR
		assert_almost_eq(bars, float(entry[1]), 0.02, \
			"%s is %.3f bars long, not %d" % [path, bars, entry[1]])

func test_silence_is_a_number_the_mixer_will_take() -> void:
	# linear_to_db(0) is -inf and the bus refuses it, which would leave the
	# outgoing loop stuck at full volume for the whole crossfade.
	assert_true(is_finite(MenuMusic._gain_db(0.0)), "silence came out as -inf")
	assert_almost_eq(MenuMusic._gain_db(1.0), 0.0, 0.001, "full volume was not unity")

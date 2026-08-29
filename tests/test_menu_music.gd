extends ParkourTest

# The handoff is the whole feature, and it is arithmetic: the record is entered
# at the chorus's downbeat PLUS however far into a bar the title fragment had
# got, so the beat carries through the crossfade unbroken. It works at any
# moment only because the tempo never changes across the track.
#
# Asserted as arithmetic too -- a headless run has a dummy audio driver and
# reports a playback position of zero forever, so a test that played the files
# and read the clock back would pass for the wrong reason.

func test_a_click_on_a_bar_line_enters_the_approach_on_its_downbeat() -> void:
	for bars in [0.0, 1.0, 4.0, 7.0]:
		assert_almost_eq(MenuMusic.chorus_entry(bars * MenuMusic.BAR),
			MenuMusic.APPROACH_START, 0.0001,
			"a click %d bars in did not land on a downbeat" % int(bars))

func test_a_click_mid_bar_carries_that_much_of_the_bar_across() -> void:
	# The point of the whole thing: the entry keeps the phase, so the next
	# kick lands exactly where it was going to. WHICH bar it enters is not
	# part of that -- a click with too little run-up left drops back one --
	# so what is asserted is the phase, not the address.
	var phase: float = MenuMusic.BAR * 0.4
	var entry: float = MenuMusic.chorus_entry(3.0 * MenuMusic.BAR + phase)
	assert_almost_eq(fmod(entry, MenuMusic.BAR), fmod(phase, MenuMusic.BAR), 0.0001,
		"the phase was dropped, so the beat restarts inside the crossfade")
	assert_lt(entry, MenuMusic.CHORUS_START, "the entry landed on or past the drop")

func test_the_entry_never_lands_more_than_a_bar_past_the_chorus() -> void:
	# Whatever the fragment reports -- and a looping stream may or may not wrap
	# its own clock -- the answer has to stay inside the chorus's first bar.
	for position in [0.0, 14.0, 14.4897, 30.0, 999.0]:
		var entry: float = MenuMusic.chorus_entry(position)
		var lead: float = MenuMusic.time_to_the_drop(entry)
		assert_between(lead, MenuMusic.MIN_RUN_UP, MenuMusic.RUN_UP + MenuMusic.BAR,
			"a position of %.4f s left %.4f s of run-up" % [position, lead])

func test_the_click_lands_before_the_drop_and_not_on_it() -> void:
	# The mistake this replaced: entering the chorus itself means entering it
	# PARTWAY THROUGH ITS FIRST BAR, so its downbeat -- the heaviest moment in
	# the piece -- has already gone by and the full arrangement simply
	# appears. Entering on the approach lets the drop arrive on its own.
	assert_almost_eq(MenuMusic.CHORUS_START / MenuMusic.BAR, 32.0, 0.001,
		"the chorus stopped being bar 32")
	assert_lt(MenuMusic.APPROACH_START, MenuMusic.CHORUS_START,
		"the click enters on the drop again, which is what sounded abrupt")
	var lead: float = MenuMusic.RUN_UP
	assert_almost_eq(lead / MenuMusic.BAR, 1.0, 0.001,
		"the run-up is %.2f bars, not the one the entrance is timed against"
			% (lead / MenuMusic.BAR))

func test_the_drop_lands_on_the_body_coming_up() -> void:
	# Measured off a shipped menu: its music peaks about 1.75 s after the
	# press, on the beat of the character standing. MainMenu takes RISE_TIME
	# to do the same thing, so the two want to be the same number -- the drop
	# belongs on the body coming up, not on the menu settling a second later.
	var lead: float = MenuMusic.RUN_UP
	assert_almost_eq(lead, MainMenu.RISE_TIME, 0.4,
		"the chorus lands %.2f s after the click and the body is up at %.2f s"
			% [lead, MainMenu.RISE_TIME])

func test_the_swell_finishes_exactly_when_the_drop_lands() -> void:
	# Arriving early leaves it sitting at full through the last of the quiet
	# approach; arriving late means the loudest moment is still climbing.
	for phase in [0.0, MenuMusic.BAR * 0.5, MenuMusic.BAR * 0.99]:
		var entry: float = MenuMusic.chorus_entry(phase)
		assert_almost_eq(entry + MenuMusic.time_to_the_drop(entry),
			MenuMusic.CHORUS_START, 0.0001,
			"a click at phase %.2f s swelled past the drop" % phase)

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

func test_the_sweep_runs_in_octaves_and_not_in_hertz() -> void:
	# Pitch is logarithmic. A linear ramp through frequency spends nearly all
	# its time in the top octave, where almost nothing is happening, and
	# crosses the octaves that matter in an instant, so it reads as a click
	# rather than as an opening.
	var lo: float = MenuMusic.TOP_FROM_HZ
	var hi: float = MenuMusic.TOP_TO_HZ
	assert_almost_eq(MenuMusic.sweep_at(0.0, lo, hi), lo, 0.1, "the sweep does not start closed")
	assert_almost_eq(MenuMusic.sweep_at(1.0, lo, hi), hi, 0.1, "the sweep does not finish open")
	assert_almost_eq(MenuMusic.sweep_at(0.5, lo, hi), sqrt(lo * hi), 1.0,
		"halfway is not the geometric middle, so the ramp is linear in frequency")

func test_the_closed_state_is_a_band_and_not_a_muffle() -> void:
	# Measured off a shipped menu that does this properly: between its quiet
	# loop and its full arrangement the sub, the low and the top each rise
	# about 8 dB while the mids rise 2.5. The melodic core is the same layer
	# in both states; what arrives on the click is the bottom and the air.
	#
	# A plain low-pass is that fingerprint upside down -- it keeps the bottom
	# and takes the mids away -- and sounds like a filter rather than like
	# instruments arriving.
	assert_gt(MenuMusic.BOTTOM_FROM_HZ, 120.0,
		"the closed state still passes the kick, so the click has no bottom to bring in")
	assert_lt(MenuMusic.TOP_FROM_HZ, 5000.0,
		"the closed state still passes the air, so the click has no top to bring in")
	assert_lt(MenuMusic.BOTTOM_FROM_HZ, MenuMusic.TOP_FROM_HZ,
		"the two filters close past each other, which passes nothing at all")
	# And what is left between them has to be the mids.
	assert_lt(MenuMusic.BOTTOM_FROM_HZ, 400.0, "the band starts above the melody")
	assert_gt(MenuMusic.TOP_FROM_HZ, 1800.0, "the band ends below the melody")

func test_both_ends_are_open_by_the_time_the_drop_lands() -> void:
	var bottom: float = MenuMusic.sweep_at(1.0, MenuMusic.BOTTOM_FROM_HZ, MenuMusic.BOTTOM_TO_HZ)
	assert_lt(bottom, 30.0, "the record still has its sub filtered out when the chorus lands")
	var top: float = MenuMusic.sweep_at(1.0, MenuMusic.TOP_FROM_HZ, MenuMusic.TOP_TO_HZ)
	assert_gt(top, 18000.0, "the record still has its air filtered out when the chorus lands")

func test_the_sweep_gets_a_bus_of_its_own_and_gives_it_back() -> void:
	# The only part of this that is not arithmetic, and the part where a typo
	# in an AudioServer call would be invisible: buses are engine-wide, so one
	# left behind by every visit to the menu accumulates for the session.
	assert_eq(AudioServer.get_bus_index(MenuMusic.BUS), -1,
		"test setup: something already left this bus behind")
	var music := MenuMusic.new()
	add_child(music)
	await step(1)
	var index: int = AudioServer.get_bus_index(MenuMusic.BUS)
	assert_ne(index, -1, "the sweep has nowhere to live")
	assert_eq(AudioServer.get_bus_effect_count(index), 2, "both ends of the band need a filter")
	assert_true(AudioServer.get_bus_effect(index, 0) is AudioEffectHighPassFilter,
		"nothing is holding the bottom back")
	assert_true(AudioServer.get_bus_effect(index, 1) is AudioEffectLowPassFilter,
		"nothing is holding the top back")
	music.free()
	await step(1)
	assert_eq(AudioServer.get_bus_index(MenuMusic.BUS), -1,
		"the bus outlived the menu that made it")

func test_a_second_menu_does_not_stack_a_second_bus() -> void:
	var first := MenuMusic.new()
	var second := MenuMusic.new()
	add_child(first)
	add_child(second)
	await step(1)
	var buses: int = 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == MenuMusic.BUS:
			buses += 1
	first.free()
	second.free()
	await step(1)
	assert_eq(buses, 1, "a rebuilt menu added a second bus of the same name")

func test_a_click_late_in_a_bar_takes_the_longer_approach() -> void:
	# Entry keeps the phase the fragment had reached, so a click near the end
	# of a bar leaves almost no run-up -- at a phase of 1.79 s there are
	# nineteen milliseconds until the drop, and the chorus would arrive with
	# the band still shut and the level still down. It drops back a bar.
	var late: float = MenuMusic.chorus_entry(MenuMusic.BAR * 0.99)
	var lead: float = MenuMusic.time_to_the_drop(late)
	assert_gt(lead, MenuMusic.MIN_RUN_UP,
		"a click at the end of a bar got %.3f s to open in" % lead)

func test_every_entry_still_lands_on_the_grid() -> void:
	# Whichever bar it falls back to, the entry has to keep the phase -- that
	# is the whole reason the beat carries through the crossfade.
	for phase in [0.0, 0.3, 0.9, 1.5, 1.79]:
		var entry: float = MenuMusic.chorus_entry(phase)
		var kept: float = fmod(entry - phase, MenuMusic.BAR)
		assert_true(kept < 0.001 or absf(kept - MenuMusic.BAR) < 0.001,
			"a click at phase %.2f s entered off the grid by %.4f s" % [phase, kept])

func test_the_goodbye_ramp_stays_somewhere_audible() -> void:
	# Hearing is logarithmic, so the fade is even in decibels -- but decibels
	# run to negative infinity, and aiming the ramp at the silence floor put
	# half its length below -42 dB, which is already gone. A 2.2 s goodbye
	# sounded like a one-second one.
	assert_gt(MenuMusic.FADE_FLOOR_DB, MenuMusic._gain_db(0.0) + 20.0,
		"the ramp still ends at the silence floor, so most of it is inaudible")
	assert_lt(MenuMusic.FADE_FLOOR_DB, -20.0,
		"the ramp stops while the music is still clearly there")
	# And the level it starts from has to be well above where it ends, or
	# there is no ramp to hear at all.
	assert_gt(linear_to_db(MenuMusic.CHORUS_LEVEL) - MenuMusic.FADE_FLOOR_DB, 20.0,
		"there is less than 20 dB of fade between playing and gone")

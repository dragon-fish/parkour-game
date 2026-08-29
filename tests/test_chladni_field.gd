extends ParkourTest

# The background field is scenery, so what is guarded is not how it looks but
# the two ways it can silently stop being a Chladni figure at all: a mode pair
# that cancels itself to a blank plate, and an analyser that never got
# installed -- either of which leaves a rectangle of nothing, with no error.

func test_the_two_modes_are_never_equal() -> void:
	# At n == m the closed form is zero everywhere and the plate goes blank.
	# It is reachable in the worst possible place: the two ends of the
	# spectrum move together on every drop, which is exactly when the figure
	# is meant to reorganise.
	for bottom in [0.0, 0.02, 0.05, 0.083, 0.2, 1.0]:
		for top in [0.0, 0.005, 0.025, 0.1, 1.0]:
			var pair: Vector2i = ChladniField.mode_pair(bottom, top)
			assert_ne(pair.x, pair.y,
				"bottom %.3f / top %.3f asked for a flat plate" % [bottom, top])

func test_every_mode_stays_in_range() -> void:
	# The closed form only draws a symmetric figure at whole numbers, and past
	# the top of the range the lines are finer than the grain.
	for bottom in [-1.0, 0.0, 0.5, 99.0]:
		for top in [-1.0, 0.0, 0.5, 99.0]:
			var pair: Vector2i = ChladniField.mode_pair(bottom, top)
			assert_between(pair.x, ChladniField.MODE_MIN, ChladniField.MODE_MAX,
				"bottom %.1f asked for mode %d" % [bottom, pair.x])
			assert_between(pair.y, ChladniField.MODE_MIN, ChladniField.MODE_MAX,
				"top %.1f asked for mode %d" % [top, pair.y])

func test_a_louder_end_asks_for_a_finer_figure() -> void:
	# The whole point of driving it from the spectrum: more energy, more
	# nodal lines. If this ever inverts the field would calm down on the drop.
	assert_gt(ChladniField.mode_pair(0.09, 0.0).x, ChladniField.mode_pair(0.0, 0.0).x,
		"a loud bottom did not ask for more lines than a silent one")
	assert_gt(ChladniField.mode_pair(0.0, 0.03).y, ChladniField.mode_pair(0.0, 0.0).y,
		"a loud top did not ask for more lines than a silent one")

func test_the_window_only_ever_sits_on_a_whole_number() -> void:
	# The field is mirror-symmetric about a point only when BOTH cosines are
	# even there, which for whole modes is every integer and nowhere else. A
	# fractional centre is a figure that is not symmetric at all, and it would
	# look merely "off" rather than broken.
	for n in range(ChladniField.MODE_MIN, ChladniField.MODE_MAX + 1):
		for m in range(ChladniField.MODE_MIN, ChladniField.MODE_MAX + 1):
			var at: Vector2 = ChladniField.lattice_point(n, m)
			assert_almost_eq(at.x, roundf(at.x), 0.0001,
				"mode %d/%d put the window at x %.3f" % [n, m, at.x])
			assert_almost_eq(at.y, roundf(at.y), 0.0001,
				"mode %d/%d put the window at y %.3f" % [n, m, at.y])

func test_the_window_always_sits_on_a_crossing_and_never_on_a_peak() -> void:
	# The half of the lattice that is symmetric but useless. On integer points
	# the field is either 0 or +/-2, and +/-2 is the ANTINODE -- the place the
	# powder is thrown hardest away from. Centre the window there and, zoomed
	# in, the screen is blank.
	for n in range(ChladniField.MODE_MIN, ChladniField.MODE_MAX + 1):
		for m in range(ChladniField.MODE_MIN, ChladniField.MODE_MAX + 1):
			var at: Vector2 = ChladniField.lattice_point(n, m)
			var f: float = cos(n * PI * at.x) * cos(m * PI * at.y) 				- cos(m * PI * at.x) * cos(n * PI * at.y)
			assert_almost_eq(f, 0.0, 0.0001,
				"mode %d/%d centred the window on a peak, not a crossing" % [n, m])

func test_different_modes_look_at_different_crossings() -> void:
	# The whole reason the window moves: a looping beat asks for the same
	# handful of modes over and over, and a fixed window would answer with the
	# same handful of shapes all evening.
	var seen := {}
	for n in range(ChladniField.MODE_MIN, ChladniField.MODE_MAX + 1):
		for m in range(ChladniField.MODE_MIN, ChladniField.MODE_MAX + 1):
			seen[ChladniField.lattice_point(n, m)] = true
	assert_gt(seen.size(), 3,
		"every mode looks at the same %d place(s)" % seen.size())

func test_the_analyser_is_installed_and_given_back() -> void:
	# Bus effects are engine-wide, so one left on Master by every visit to the
	# menu accumulates for the session. The only part of this that is not
	# arithmetic, and where a typo would be invisible.
	var before: int = _analysers_on_master()
	var field := ChladniField.new()
	add_child(field)
	await step(1)
	assert_eq(_analysers_on_master(), before + 1, "nothing is reading the spectrum")
	field.free()
	await step(1)
	assert_eq(_analysers_on_master(), before, "the analyser outlived the menu that made it")

func test_a_second_field_does_not_stack_a_second_analyser() -> void:
	var before: int = _analysers_on_master()
	var first := ChladniField.new()
	var second := ChladniField.new()
	add_child(first)
	add_child(second)
	await step(1)
	var during: int = _analysers_on_master()
	first.free()
	second.free()
	await step(1)
	assert_eq(during, before + 1, "a rebuilt menu added a second analyser")
	assert_eq(_analysers_on_master(), before, "removing them took somebody else's with it")

func _analysers_on_master() -> int:
	var found: int = 0
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectSpectrumAnalyzer:
			found += 1
	return found

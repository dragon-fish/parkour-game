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

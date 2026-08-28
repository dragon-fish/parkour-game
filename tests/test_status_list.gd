extends ParkourTest

# Pure logic, no physics world -- StatusList owns no node and does no queries,
# the same stance as FallTracker and SpeedEnergy.

func _spec(effect: int, seconds: float = INF, amount: float = 0.0, \
		subject: StringName = &"") -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	s.seconds = seconds
	s.amount = amount
	s.subject = subject
	return s

func _source(name: String) -> Node:
	var n := Node.new()
	n.name = name
	autofree(n)
	return n

func test_two_subjects_of_the_same_effect_coexist() -> void:
	# The key is (effect, subject): blocking one rope must not unblock another.
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe2"), a, 0)
	assert_eq(list.entry_count(), 2, "two subjects collapsed into one entry")
	assert_true(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe1"), "pipe1 missing")
	assert_true(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe2"), "pipe2 missing")

func test_the_same_key_never_stacks() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), a, 0)
	assert_eq(list.entry_count(), 1, "same key stacked instead of replacing")

func test_the_same_source_always_refreshes() -> void:
	# A polling volume re-applies at its OWN priority every refresh_interval.
	# If equal priority were ignored across the board it would starve itself.
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.SPEED_CAP, 0.5, 0.5), a, 0)
	list.tick(0.4)
	assert_true(list.apply(_spec(Status.Effect.SPEED_CAP, 0.5, 0.5), a, 0), \
		"a source could not refresh its own status")
	list.tick(0.4)
	assert_true(list.has(Status.Effect.SPEED_CAP), "the volume starved its own status")

func test_a_higher_layer_wins_and_a_lower_one_is_ignored() -> void:
	var list := StatusList.new()
	var low := _source("low")
	var high := _source("high")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), low, 0)
	assert_true(list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), high, 1), \
		"a higher layer was refused")
	assert_almost_eq(list.amount_of(Status.Effect.SPEED_CAP), 0.3, 0.0001, \
		"the higher layer did not take effect")
	assert_false(list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.9), low, 0), \
		"a lower layer overwrote a higher one")
	assert_almost_eq(list.amount_of(Status.Effect.SPEED_CAP), 0.3, 0.0001, \
		"the lower layer changed the value anyway")

func test_equal_layers_from_different_sources_keep_the_incumbent() -> void:
	var list := StatusList.new()
	var a := _source("a")
	var b := _source("b")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	assert_false(list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0), \
		"an equal layer displaced the incumbent")
	assert_almost_eq(list.amount_of(Status.Effect.SPEED_CAP), 0.5, 0.0001, \
		"the incumbent's value changed")

func test_an_equal_layer_conflict_is_reported_once() -> void:
	# Polling would otherwise repeat the warning every refresh_interval and
	# make the console unusable.
	var list := StatusList.new()
	var a := _source("a")
	var b := _source("b")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	for i in 5:
		list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0)
	assert_eq(list.warning_count(), 1, "the same conflict was reported more than once")

func test_a_countdown_expires_and_infinity_does_not() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_JUMP, 1.0), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_SLIDE, INF), a, 0)
	list.tick(0.9)
	assert_true(list.has(Status.Effect.BLOCK_JUMP), "expired early")
	list.tick(0.2)
	assert_false(list.has(Status.Effect.BLOCK_JUMP), "countdown did not expire")
	assert_true(list.has(Status.Effect.BLOCK_SLIDE), "INF expired")

func test_remove_without_a_subject_takes_every_subject() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe2"), a, 0)
	list.remove(Status.Effect.BLOCK_INTEREST_LINE, &"")
	assert_eq(list.entry_count(), 0, "a bare remove left subjects behind")

func test_remove_with_a_subject_takes_only_that_one() -> void:
	var list := StatusList.new()
	var a := _source("a")
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), a, 0)
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe2"), a, 0)
	list.remove(Status.Effect.BLOCK_INTEREST_LINE, &"pipe1")
	assert_false(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe1"), "pipe1 survived")
	assert_true(list.has(Status.Effect.BLOCK_INTEREST_LINE, &"pipe2"), "pipe2 was taken too")

func test_clear_all_empties_the_list_and_the_warning_memory() -> void:
	var list := StatusList.new()
	var a := _source("a")
	var b := _source("b")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0)
	list.clear_all()
	assert_eq(list.entry_count(), 0, "clear_all left entries")
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), a, 0)
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.3), b, 0)
	assert_eq(list.warning_count(), 2, "the warning memory survived clear_all")

func test_signals_report_what_arrived_and_what_left() -> void:
	var list := StatusList.new()
	var a := _source("a")
	watch_signals(list)
	list.apply(_spec(Status.Effect.BLOCK_JUMP, 1.0), a, 0)
	assert_signal_emitted(list, "status_applied", "no status_applied")
	list.tick(1.1)
	assert_signal_emitted(list, "status_removed", "no status_removed")

func test_speed_scale_is_one_without_a_cap() -> void:
	var list := StatusList.new()
	assert_almost_eq(list.speed_scale(), 1.0, 0.0001, "an empty list scaled the cap")

func test_speed_scale_reports_the_cap_in_force() -> void:
	var list := StatusList.new()
	list.apply(_spec(Status.Effect.SPEED_CAP, INF, 0.5), _source("a"), 0)
	assert_almost_eq(list.speed_scale(), 0.5, 0.0001, "the cap was not reported")

func test_a_blocked_move_is_reported_by_its_own_name() -> void:
	var list := StatusList.new()
	list.apply(_spec(Status.Effect.BLOCK_JUMP), _source("a"), 0)
	assert_true(list.is_move_blocked(Move.JUMP), "JUMP was not blocked")
	assert_false(list.is_move_blocked(Move.SLIDE), "SLIDE was blocked too")

func test_a_move_with_no_effect_of_its_own_can_never_be_blocked() -> void:
	# WALKING / FALLING / LANDING / FALL_UNCONTROLLED have no enum value, so
	# the table has no row for them and the answer is always false. This is the
	# other half of the guard: the mistake cannot be authored, and it cannot be
	# reached by accident either.
	var list := StatusList.new()
	for name in [Move.WALKING, Move.FALLING, Move.LANDING, Move.FALL_UNCONTROLLED]:
		assert_false(list.is_move_blocked(name), "%s was blockable" % name)

func test_only_the_named_line_is_blocked() -> void:
	var list := StatusList.new()
	list.apply(_spec(Status.Effect.BLOCK_INTEREST_LINE, INF, 0.0, &"pipe1"), _source("a"), 0)
	assert_true(list.is_line_blocked(&"pipe1"), "pipe1 was not blocked")
	assert_false(list.is_line_blocked(&"pipe2"), "pipe2 was blocked too")
	assert_false(list.is_line_blocked(&""), "an untagged line was blocked")

func test_forced_view_is_none_until_something_forces_it() -> void:
	var list := StatusList.new()
	assert_eq(list.forced_view(), Status.View.NONE, "an empty list forced a view")

func test_forced_view_reports_which_view_is_forced() -> void:
	var list := StatusList.new()
	var spec := _spec(Status.Effect.FORCE_VIEW)
	spec.view = Status.View.FIRST
	list.apply(spec, _source("a"), 0)
	assert_eq(list.forced_view(), Status.View.FIRST, "the forced view was not reported")

func test_the_two_views_are_one_key_so_the_layer_decides() -> void:
	# First and third person are two VALUES of one effect, not two effects. As
	# two effects they would be two keys, could coexist, and the priority rule
	# -- which only compares within a key -- would never see them.
	var list := StatusList.new()
	var first := _spec(Status.Effect.FORCE_VIEW)
	first.view = Status.View.FIRST
	var third := _spec(Status.Effect.FORCE_VIEW)
	third.view = Status.View.THIRD
	list.apply(first, _source("low"), 0)
	list.apply(third, _source("high"), 1)
	assert_eq(list.entry_count(), 1, "the two views became two entries")
	assert_eq(list.forced_view(), Status.View.THIRD, "the higher layer did not win")

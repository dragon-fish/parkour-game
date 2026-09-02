extends ParkourTest

# The seam tutorial copy names keys through. Today it answers from the
# hardcoded bindings; when rebinding lands it answers from the map, and not
# one line of copy changes. What is asserted is that seam, not the strings --
# those are content and will be reworded.

func test_every_action_has_a_label() -> void:
	for action in [InputNames.MOVE, InputNames.JUMP, InputNames.CROUCH,
			InputNames.WALK, InputNames.TURN]:
		var label := InputNames.label(action)
		assert_false(label.is_empty(),
			"action %s has no label" % action)
		assert_false(label.contains("?"),
			"action %s produced the unknown marker instead of a real key" % action)

func test_an_unknown_action_does_not_crash_or_lie() -> void:
	# Copy asking for a key that does not exist should be obvious on screen,
	# not silently plausible.
	var label: String = InputNames.label(&"NoSuchAction")
	assert_false(label.is_empty(), "an unknown action produced an empty label")
	assert_true(label.contains("?"), "an unknown action produced a plausible-looking key: %s" % label)

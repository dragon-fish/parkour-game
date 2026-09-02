extends ParkourTest

# The seam tutorial copy names keys through. Today it answers from the
# hardcoded bindings; when rebinding lands it answers from the map, and not
# one line of copy changes. What is asserted is that seam, not the strings --
# those are content and will be reworded.

func test_every_action_has_a_label() -> void:
	for action in [InputNames.MOVE, InputNames.JUMP, InputNames.CROUCH,
			InputNames.WALK, InputNames.TURN]:
		assert_false(InputNames.label(action).is_empty(),
			"action %s has no label" % action)

func test_an_unknown_action_does_not_crash_or_lie() -> void:
	# Copy asking for a key that does not exist should be obvious on screen,
	# not silently plausible.
	var label: String = InputNames.label(&"NoSuchAction")
	assert_false(label.is_empty(), "an unknown action produced an empty label")
	assert_true(label.contains("?"), "an unknown action produced a plausible-looking key: %s" % label)

func test_the_labels_match_what_the_input_source_actually_reads() -> void:
	# THE POINT OF THE TABLE. If these drift apart, the tutorial teaches keys
	# the game does not listen to.
	assert_eq(InputNames.label(InputNames.JUMP), OS.get_keycode_string(KEY_SPACE),
		"jump's label does not match the key KeyboardInputSource polls")
	assert_eq(InputNames.label(InputNames.CROUCH), OS.get_keycode_string(KEY_SHIFT),
		"crouch's label does not match the key KeyboardInputSource polls")
	assert_eq(InputNames.label(InputNames.TURN), OS.get_keycode_string(KEY_Q),
		"turn's label does not match the key KeyboardInputSource polls")

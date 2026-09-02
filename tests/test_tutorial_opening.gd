extends ParkourTest

# The only three lines the tutorial ever says about controls. What is asserted
# is that they exist, arrive in order, stop, and name keys through the table --
# not their wording, which is content and will be reworded.

var _opening: TutorialOpening
var _subtitle: Subtitle

func _built() -> TutorialOpening:
	_subtitle = Subtitle.new()
	add_child_autofree(_subtitle)
	_opening = TutorialOpening.new()
	_opening.subtitle = _subtitle
	_opening.hold = 0.05
	_opening.gap = 0.05
	add_child_autofree(_opening)
	await step(1)
	return _opening

func test_there_are_exactly_three_lines() -> void:
	# Three, and this number is the design: move, up, down. A fourth means
	# something is being taught that the two directions should have covered.
	var opening: TutorialOpening = await _built()
	assert_eq(opening.lines().size(), 3, "the opening is not three lines")

func test_every_line_names_its_key_through_the_table() -> void:
	# Copy with a key spelled into it keeps telling the player to press Shift
	# after he has rebound crouch. This catches the literal at authoring time.
	var opening: TutorialOpening = await _built()
	var text: String = " ".join(opening.lines())
	for action in [InputNames.MOVE, InputNames.JUMP, InputNames.CROUCH]:
		assert_true(text.contains(InputNames.label(action)),
			"no line names %s through InputNames" % action)

func test_the_lines_arrive_in_order_and_then_stop() -> void:
	var opening: TutorialOpening = await _built()
	var seen: Array[int] = []
	opening.spoken.connect(func(i: int) -> void: seen.append(i))
	var ended := [0]
	opening.done.connect(func() -> void: ended[0] += 1)

	opening.play()
	await step(60)

	assert_eq(seen, [0, 1, 2] as Array[int], "the lines did not arrive in order: %s" % [seen])
	assert_eq(ended[0], 1, "the opening announced its end %d times" % ended[0])

func test_it_says_nothing_without_a_subtitle_layer() -> void:
	# A level built without one (every test world is) must not crash.
	var opening := TutorialOpening.new()
	add_child_autofree(opening)
	await step(1)
	opening.play()
	await step(10)
	assert_eq(opening.lines().size(), 3, "the lines went missing without a subtitle")

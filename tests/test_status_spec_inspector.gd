extends ParkourTest

# The editor-facing half of StatusSpec. Not a tuning value and not a visual --
# a wrong summary or a stray field is a level authored wrong, which is a
# structural problem.

func _spec(effect: int) -> StatusSpec:
	var s := StatusSpec.new()
	s.effect = effect
	return s

func test_the_summary_names_the_effect_and_its_payload() -> void:
	var cap := _spec(Status.Effect.SPEED_CAP)
	cap.amount = 0.5
	cap.seconds = 2.0
	var text := cap.summary()
	assert_string_contains(text, "SPEED_CAP", "the effect is not named")
	assert_string_contains(text, "0.5", "the payload is missing")
	assert_string_contains(text, "2", "the duration is missing")

func test_an_endless_status_says_so_rather_than_printing_inf() -> void:
	var block := _spec(Status.Effect.BLOCK_JUMP)
	block.seconds = INF
	assert_string_contains(block.summary(), "until removed",
		"an endless status printed a number")

func test_a_line_block_shows_which_line() -> void:
	var b := _spec(Status.Effect.BLOCK_INTEREST_LINE)
	b.subject = &"pipe1"
	assert_string_contains(b.summary(), "pipe1", "the subject is missing")

func test_only_the_fields_an_effect_reads_stay_visible() -> void:
	# _validate_property() hides the rest. Checked through the same reflection
	# the inspector uses, so this fails if the schema and the UI drift apart.
	var block := _spec(Status.Effect.BLOCK_JUMP)
	var hidden := []
	for prop in block.get_property_list():
		if prop["name"] in ["amount", "subject", "view"] \
				and (prop["usage"] & PROPERTY_USAGE_EDITOR) == 0:
			hidden.append(prop["name"])
	assert_eq(hidden.size(), 3, "BLOCK_JUMP still shows payload it never reads")

	var cap := _spec(Status.Effect.SPEED_CAP)
	for prop in cap.get_property_list():
		if prop["name"] == "amount":
			assert_true((prop["usage"] & PROPERTY_USAGE_EDITOR) != 0,
				"SPEED_CAP hid the one field it does read")

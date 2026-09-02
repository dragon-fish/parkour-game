extends ParkourTest

# The corner toast: the game REPORTING that something happened, as opposed to
# Subtitle, which is the game talking to the player. What is asserted here is
# the queue's contract -- how many may stand, who leaves when a fourth
# arrives, and which end new ones join. Colours, slide distance and fade
# timings are tuning and are not asserted.

func _toast() -> Toast:
	var toast := Toast.new()
	add_child_autofree(toast)
	await step(1)
	return toast

func test_a_toast_shows_its_text() -> void:
	var toast: Toast = await _toast()
	assert_eq(toast.count(), 0, "test setup: a fresh toast layer was not empty")
	toast.show_text("检查点 天台 已保存")
	await step(1)
	assert_eq(toast.count(), 1, "showing one toast did not put one on screen")
	assert_true(toast.texts().has("检查点 天台 已保存"),
		"the line is not among the standing toasts: %s" % [toast.texts()])

func test_a_fourth_toast_pushes_the_oldest_out() -> void:
	# Three may stand. The fourth does not queue behind them -- it evicts.
	var toast: Toast = await _toast()
	for line in ["一", "二", "三"]:
		toast.show_text(line)
		await step(1)
	assert_eq(toast.count(), 3, "three toasts did not all stand")

	toast.show_text("四")
	await step(1)
	assert_eq(toast.count(), 3, "a fourth toast pushed the count past the limit")
	assert_false(toast.texts().has("一"), "the oldest toast was not evicted")
	assert_true(toast.texts().has("四"), "the newest toast never arrived")

func test_new_toasts_join_at_the_bottom() -> void:
	# Newest lowest, so an expiring toast frees the TOP and the rest rise.
	var toast: Toast = await _toast()
	toast.show_text("上")
	await step(1)
	toast.show_text("下")
	await step(1)
	var ys: Array[float] = toast.slot_ys()
	assert_eq(ys.size(), 2, "test setup: expected two standing toasts")
	assert_true(ys[1] > ys[0],
		"a newer toast did not land below an older one: %s" % [ys])

func test_an_expiring_toast_lets_the_ones_below_rise() -> void:
	var toast: Toast = await _toast()
	toast.show_text("上", 0.05)
	await step(1)
	toast.show_text("下")
	await step(1)
	var lower_before: float = toast.slot_ys()[1]

	# Let the short-held one run out. The suite runs at --fixed-fps 60 and the
	# toast ages on accumulated delta, so frames are the honest clock here.
	await step(20)
	assert_eq(toast.count(), 1, "the short-held toast did not expire")
	assert_true(toast.slot_ys()[0] < lower_before,
		"the survivor did not rise into the freed slot")

func test_the_hold_can_be_overridden_per_line() -> void:
	# The default outlives a line given a short hold -- that is the whole
	# point of the override, and the reason DeathSequence-length lines and
	# checkpoint blips can share one layer.
	var toast: Toast = await _toast()
	toast.show_text("短", 0.05)
	toast.show_text("长")
	await step(1)
	assert_eq(toast.count(), 2, "test setup: both lines should be standing")
	await step(20)
	assert_eq(toast.texts(), PackedStringArray(["长"]),
		"the overridden hold did not expire on its own clock: %s" % [toast.texts()])

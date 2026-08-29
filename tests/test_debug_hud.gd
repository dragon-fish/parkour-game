extends ParkourTest

# The readout is the only way to see most of what the movement layer does, so
# what is asserted here is that it stays readable: the compact tier keeps the
# rows worth glancing at, and Tab cycles rather than flips.

const TestWorld = preload("res://tests/world_fixture.gd")

var _worlds: Array = []

func after_each() -> void:
	for world in _worlds:
		TestWorld.teardown(world)
	_worlds.clear()

func _hud() -> DebugHud:
	var world := TestWorld.build(get_tree(), MovementConfig.new())
	_worlds.append(world)
	var hud := DebugHud.new()
	hud.player = world["player"]
	add_child_autofree(hud)
	await step(2)
	return hud

func _tab(hud: DebugHud) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_TAB
	press.pressed = true
	hud._unhandled_input(press)

func test_tab_cycles_off_compact_full_rather_than_flipping() -> void:
	var hud := await _hud()
	var seen: Array[int] = []
	for i in 4:
		seen.append(hud._tier)
		_tab(hud)
	# Whatever it started at, four presses walk every tier and come home.
	assert_eq(seen[3], seen[0], "Tab did not come back round to where it began")
	assert_eq(seen.duplicate().size() - _unique(seen).size(), 1, \
		"Tab is not visiting all three tiers")

func _unique(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for v in values:
		if not out.has(v):
			out.append(v)
	return out

func test_the_compact_tier_keeps_position_and_facing() -> void:
	# Asked for by name: they are what the owner reads constantly while
	# placing things, and the first cut of this tier dropped them.
	var hud := await _hud()
	assert_true(hud._worth_reading_while_playing("at         (1.0, 2.0, 3.0)  yaw +0  pitch +0"), \
		"the compact tier dropped where the body is")

func test_the_compact_tier_keeps_health_and_the_key_legend() -> void:
	var hud := await _hud()
	assert_true(hud._worth_reading_while_playing("health     100.0 / 100  full  last FALL"), \
		"the compact tier dropped the health readout")
	assert_true(hud._worth_reading_while_playing("Tab HUD  F10 capsule"), \
		"a readout that hides its own keys is worse, not smaller")

func test_the_compact_tier_drops_the_rows_that_answer_one_question() -> void:
	var hud := await _hud()
	for row in ["shimmy     -", "model      y +0.00", "wall ahead -", "swing      -"]:
		assert_false(hud._worth_reading_while_playing(row), \
			"'%s' is a specific question's answer and belongs in the full tier" % row)

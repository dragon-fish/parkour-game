extends ParkourTest

# Lights drawn all at once stalled a level's first frames for over ten seconds
# while the curtain had already lifted. An extracted level's lights come on a
# few per frame, and the level is not ready until the last one has.

const LIGHTS_SCRIPT := preload("res://tools/me_level/me_lights.gd")

func test_lights_come_on_a_few_per_frame_and_hold_the_level_until_lit() -> void:
	var lights := Node3D.new()
	lights.set_script(LIGHTS_SCRIPT)
	var count := LIGHTS_SCRIPT.LIGHTS_PER_FRAME * 3
	for i in count:
		lights.add_child(OmniLight3D.new())
	add_child_autofree(lights)
	var lit := func() -> int: return lights.get_children().filter(func(l): return l.visible).size()
	assert_eq(lit.call(), 0, "lights were on before any frame was drawn")
	assert_true(lights.is_in_group(Arena.WARMING), "a lights node still dark did not hold the level")
	var before: int = lit.call()
	var most_in_a_frame := 0
	for i in 8:
		await get_tree().process_frame
		var now: int = lit.call()
		most_in_a_frame = maxi(most_in_a_frame, now - before)
		before = now
	assert_lte(most_in_a_frame, LIGHTS_SCRIPT.LIGHTS_PER_FRAME, "one frame lit more than its budget")
	assert_eq(lit.call(), count, "not every light came on")
	assert_false(lights.is_in_group(Arena.WARMING), "a fully lit node kept holding the level")

extends TestCase

# The scripted source is what every movement test drives the player with, so
# its edge semantics must match the keyboard source exactly.

func test_scripted_source_returns_what_was_set() -> void:
	await step(1)
	var src := ScriptedInputSource.new()
	src.state.move = Vector2(0.0, 1.0)
	src.state.walk_held = true
	var snapshot := src.poll()
	check(snapshot.move == Vector2(0.0, 1.0), "move was not passed through")
	check(snapshot.walk_held, "walk_held was not passed through")

func test_jump_pressed_is_an_edge_lasting_one_poll() -> void:
	await step(1)
	var src := ScriptedInputSource.new()
	src.press_jump()

	var first := src.poll()
	check(first.jump_pressed, "jump_pressed missing on the first poll")
	check(first.jump_held, "jump_held missing on the first poll")

	var second := src.poll()
	check(not second.jump_pressed, "jump_pressed must not survive a second poll")
	check(second.jump_held, "jump_held must persist until released")

func test_copy_is_independent() -> void:
	await step(1)
	var a := MoveInput.new()
	a.move = Vector2(1.0, 0.0)
	var b := a.copy()
	b.move = Vector2(0.0, 1.0)
	check(a.move == Vector2(1.0, 0.0), "copy() returned a shared reference")
